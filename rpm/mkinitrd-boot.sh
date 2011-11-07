#!/bin/bash
#%stage: device
#%depends: network lldpad
#%programs: /usr/sbin/fipvlan /usr/sbin/fcoeadm
#%modules: $fcoe_drv 8021q
#%if: "$root_fcoe"
#
##### FCoE initialization
##
## This script initializes FCoE (FC over Ethernet).

load_modules

lookup_vlan_if()
{
    local ifname=$1
    local vlan vid if

    IFS="| "; while read vlan vid if; do
	[ "${vlan%% Dev*}" = "VLAN" ] && continue
	[ -z "$vid" ] && continue
	if [ "$if" = "$ifname" ] ; then
	    echo $vlan
	fi
    done < /proc/net/vlan/config
}

lookup_fcoe_host()
{
    local ifname=$1
    local h

    for h in /sys/class/scsi_host/host* ; do
	[ -d "$h" ] || continue
	[ -e $h/symbolic_name ] || continue
	vif=$(sed -n 's/.* over \(.*\)/\1/p' $h/symbolic_name)
	if [ "$vif" ] && [ "$ifname" = "$vif" ] ; then
	    echo ${h##*/}
	    break
	fi
    done
}

wait_for_fcoe_if()
{
    local ifname=$1
    local host vif
    local retry_count=$udev_timeout

    vif=$(lookup_vlan_if $ifname)
    if [ -z "$vif" ] ; then
	echo "No VLAN interface created on $ifname"
	echo "dropping to /bin/sh"
	cd /
	PATH=$PATH PS1='$ ' /bin/sh -i
    fi
    while [ $retry_count -gt 0 ] ; do
	host=$(lookup_fcoe_host $vif)
	[ "$host" ] && break;
	retry_count=$(($retry_count-1))
	sleep 1
    done
    if [ "$host" ] ; then
	echo -n "Wait for FCoE link on $vif: "
	retry_count=$udev_timeout
	while [ $retry_count -gt 0 ] ; do
	    status=$(cat /sys/class/fc_host/$host/port_state 2> /dev/null)
	    if [ "$status" = "Online" ] ; then
		echo "Ok"
		return 0
	    fi
	    echo -n "."
            retry_count=$(($retry_count-1))
            sleep 2
	done
	echo -n "Failed; "
    else
	echo -n "FC host not created; "
    fi

    echo "dropping to /bin/sh"
    cd /
    PATH=$PATH PS1='$ ' /bin/sh -i
}

for if in $fcoe_if ; do
    /usr/sbin/fipvlan -c -s $if
    wait_for_fcoe_if $if
done
if [ -n "$edd_if" ] ; then
    /usr/sbin/fipvlan -c -s $edd_if
    wait_for_fcoe_if $edd_if
fi
