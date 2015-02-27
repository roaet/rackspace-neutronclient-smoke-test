#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
cd $DIR

if [ -z "$1" ]; then
    echo "A configuration file must be passed in"
    exit 1
fi
conf=`readlink -f $1`
if [ ! -e "$conf" ]; then
    echo -e "Conf file not found"
    exit 1
fi


source $DIR/common/basics.sh 

testdir=$DIR/_testing
requires=( python virtualenv pip mkdir readlink )
state=sanity
ret=0

network_name="rs_nc_test_network"

while true ; do
    case $state in
        install)
            next_state=setup
            mkdir $testdir
            cd $testdir
            virtualenv .venv > /dev/null 2>&1
            source .venv/bin/activate
            in_venv=`in_venv`
            if [ $in_venv -ne 1 ]; then
                echo -e "Not in virtualenv somehow."
                state=exit
                continue
            fi
            prev_neutron=`which neutron`
            pip install rackspace-neutronclient > /dev/null 2>&1
            val=`has_prog neutron`
            if [ $val -ne 1 ]; then
                echo -e "No neutron found after install"
                state=exit
                continue
            fi
            curr_neutron=`which neutron`
            if [ "$prev_neutron" == "$curr_neutron" ]; then
                echo -e "Neutron binary didn't change after install"
                state=exit
                continue
            fi
            state=$next_state
            ;;
        setup)
            next_state=testing
            source $conf
            envreq=( OS_AUTH_URL OS_USERNAME OS_PASSWORD OS_AUTH_STRATEGY )
            for env in "${envreq[@]}"
            do
                val=`has_prog $check`
                if [ -z "$env" ]; then
                    echo -e "Missing required configuration $env"
                    state=exit
                    continue
                fi
            done
            state=$next_state
            ;;
        testing)
            next_state=cleanup
            netmk=`neutron net-create $network_name 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Network create failed.\n$netmk"
                ret=1
                continue
            fi
            netid=`echo "$netmk" | grep " id " | awk '{print $4}'`

            submk=`neutron subnet-create $network_name 192.168.1.0/24 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Subnet create failed.\n$submk"
                ret=1
                continue
            fi
            subid=`echo "$submk" | grep " id " | awk '{print $4}'`

            portmk=`neutron port-create $network_name 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Port create failed.\n$portmk"
                ret=1
                continue
            fi
            portid=`echo "$portmk" | grep " id " | awk '{print $4}'`

            state=$next_state
            ;;
        cleanup)
            next_state=exit
            portdl=`neutron port-delete $portid 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Port delete failed.\n$portdl"
                ret=1
            fi
            subdl=`neutron subnet-delete $subid 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Subnet delete failed.\n$subdl"
                ret=1
            fi
            netdl=`neutron net-delete $netid 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Network delete failed.\n$netdl"
                ret=1
            fi
            state=$next_state
            ;;
        sanity)
            next_state=install
            for check in "${requires[@]}"
            do
                val=`has_prog $check`
                if [ $val -ne 1 ]; then
                    echo -e "No $check. Exiting"
                    exit 1;
                fi
            done
            in_venv=`in_venv`
            if [ $in_venv -ne 0 ]; then
                echo -e "In virtualenv. Please deactivate."
                exit 1;
            fi
            state=$next_state
            ;;
        exit)
            deactivate
            rm -rf $testdir
            exit $ret
            ;;
    esac
done
