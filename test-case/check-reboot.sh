#!/bin/bash

##
## Case Name: test reboot
## Preconditions:
##    N/A
## Description:
##    run reboot for the test
## Case step:
##    1. check system status is correct
##    2. wait for the delay time
##    3. trigger for the reboot
## Expect result:
##    Test execute without report error in the LOG
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['d']='delay'    OPT_DESC_lst['d']='delay after system bootup'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=2

func_opt_parse_option $*

func_lib_check_sudo
loop_count=${OPT_VALUE_lst['l']}
delay=${OPT_VALUE_lst['d']}

# write the total & current count to the status file
status_log=$LOG_ROOT/status.txt
echo $loop_count >> $status_log
count=$(head -n 1 $status_log|awk '{print $1;}')
current=$[ $count - $loop_count ]

dlogi "Round: $current/$count"

# verify-pcm-list.sh & verify-tplg-binary.sh need TPLG file
export TPLG=$(sof-get-default-tplg.sh)

declare -a verify_lst
verify_lst=(${verify_lst[*]} "verify-firmware-presence.sh")
verify_lst=(${verify_lst[*]} "verify-kernel-module-load-probe.sh")
verify_lst=(${verify_lst[*]} "verify-pcm-list.sh")
verify_lst=(${verify_lst[*]} "verify-sof-firmware-load.sh")
verify_lst=(${verify_lst[*]} "verify-tplg-binary.sh")

# because for the 1st round those information write by nohup command redirect
# but after system reboot the nohup redirect is missing
dlogi "Check status begin"
for i in ${verify_lst[*]}
do
    dlogc "$(dirname ${BASH_SOURCE[0]})/$i"
    $(dirname ${BASH_SOURCE[0]})/$i
    if [ $? -ne 0 ];then
        # last line add failed keyword
        sed -i '$s/$/ fail/' $status_log
        dlogi "$i: fail" 
        exit 1
    else
        # last line add pass keyword
        dlogi "$i: pass" 
    fi
done
dlogi "Round $current: Status check finished"
sed -i '$s/$/ pass/' $status_log
[[ $loop_count -le 0 ]] && exit 0

dlogi "Do the prepare for the next round bootup"
# run the script for the next round
next_count=$[ $loop_count - 1 ]

full_cmd=$(ps -p $PPID -o args --no-header)
# parent process have current script name
# like: bash -c $0 .....
if [ "$full_cmd" =~ "bash -c" ]; then
    full_cmd=${full_cmd#bash -c}
else
    full_cmd=$(ps -p $$ -o args --no-header)
    full_cmd=${full_cmd#\/bin\/bash}
fi

# load script default value for the really full command
if [ $# -eq 0 ]; then
    full_cmd=$(echo $full_cmd|sed "s:$0:& -l $loop_count:g")
fi

# convert relative path to absolute path
full_cmd=$(echo $full_cmd|sed "s:$0:$(realpath $0):g")
# some load will use '~' which is $HOME, but after system reboot, in rc.local $USER is root
# so the '~' will lead to the error path
full_cmd=$(echo $full_cmd|sed "s:~:$HOME:g")
# now convert full current command to next round command
full_cmd=$(echo $full_cmd|sed "s:-l $loop_count:-l $next_count:g")

boot_file=/etc/rc.local
# if miss rc.local file let sof-boot-once.sh to create it
[[ ! -f $boot_file ]] && sudo sof-boot-once.sh

# change the file own & add write permission
sudo chmod u+w $boot_file
sudo chown $UID $boot_file
old_content="$(cat $boot_file|grep -v '^exit')"
# write the information to /etc/rc.local
# LOG_ROOT to make sure all tests, including sub-cases, write log to the same target folder
# DMESG_LOG_START_LINE to just keep last kernel bootup log
boot_once_flag=$(realpath $(which sof-boot-once.sh))
cat << END > $boot_file
$old_content

$boot_once_flag
export LOG_ROOT='$(realpath $LOG_ROOT)'
export DMESG_LOG_START_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
bash -c '$full_cmd'

exit 0
END
# * restore file own to root
sudo chown 0 $boot_file

#dlogi "dump boot file: $boot_file"
#cat $boot_file
#cp $boot_file $LOG_ROOT/boot-$loop_count
# template delay before reboot
sleep $delay

dlogc "reboot"
sudo reboot
#exit 0
