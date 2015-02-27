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
sg_name="rs_nc_test_sg"

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
            state=cleanup
            netlist=`neutron net-list 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Network list failed.\n$netlist"
                ret=1
                continue
            fi

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

            sublist=`neutron subnet-list 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Subnet list failed.\n$sublist"
                ret=1
                continue
            fi

            portmk=`neutron port-create $network_name 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Port create failed.\n$portmk"
                ret=1
                continue
            fi
            portid=`echo "$portmk" | grep " id " | awk '{print $4}'`

            portlist=`neutron port-list 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Port list failed.\n$portlist"
                ret=1
                continue
            fi

            sgmk=`neutron security-group-create $sg_name 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Security group create failed.\n$sgmk"
                ret=1
                continue
            fi
            sgid=`echo "$sgmk" | grep " id " | awk '{print $4}'`

            sglist=`neutron security-group-list 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Security group list failed.\n$sglist"
                ret=1
                continue
            fi

            sgrmk=`neutron security-group-rule-create --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 80 --port-range-max 80 $sg_name 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Security group rule create failed.\n$sgrmk"
                ret=1
                continue
            fi
            sgrid=`echo "$sgrmk" | grep " id " | awk '{print $4}'`

            sgrlist=`neutron security-group-rule-list 2> /dev/null`
            if [ $? -ne 0 ]; then
                echo -e "Security group rule list failed.\n$sglist"
                ret=1
                continue
            fi

            ;;
        cleanup)
            next_state=exit
            
            if [ ! -z ${sgrid+x} ]; then
                sgrdl=`neutron security-group-rule-delete $sgrid 2> /dev/null`
                if [ $? -ne 0 ]; then
                    echo -e "security group rule delete failed.\n$sgrdl"
                    ret=1
                fi
            fi

            if [ ! -z ${sgid+x} ]; then
                sgdl=`neutron security-group-delete $sgid 2> /dev/null`
                if [ $? -ne 0 ]; then
                    echo -e "security group delete failed.\n$sgdl"
                    ret=1
                fi
            fi

            if [ ! -z ${portid+x} ]; then
                portdl=`neutron port-delete $portid 2> /dev/null`
                if [ $? -ne 0 ]; then
                    echo -e "Port delete failed.\n$portdl"
                    ret=1
                fi
            fi

            if [ ! -z ${subid+x} ]; then
                subdl=`neutron subnet-delete $subid 2> /dev/null`
                if [ $? -ne 0 ]; then
                    echo -e "Subnet delete failed.\n$subdl"
                    ret=1
                fi
            fi

            if [ ! -z ${netid+x} ]; then
                netdl=`neutron net-delete $netid 2> /dev/null`
                if [ $? -ne 0 ]; then
                    echo -e "Network delete failed.\n$netdl"
                    ret=1
                fi
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
