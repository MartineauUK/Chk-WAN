#!/bin/sh
VER="v1.11"
#============================================================================================ © 2016-2018 Martineau v1.11
#
# Monitor WAN connection state using PINGs to multiple hosts, or a single cURL 15 Byte data request and optionally a 12MB/500B WGET/CURL data transfer.
#         NOTE: The cURL data transfer rate/perfomance threshold may also be checked e.g. to switch from a 'slow' (Dual) WAN interface.
#         Usually the Recovery action (REBOOT or restart the WAN) occurs in about 90 secs (PING ONLY) or in about 03:30 mins for 'force' data download
#
# Usage:    ChkWAN  [help|-h]
#                   [reboot | wan | noaction] [force[big | small]] [nowait] [quiet] [once] [i={[wan0|wan1]}] [googleonly] [curl] [ping='ping_target[,..]'] 
#                   [tries=number] [fails=number] [curlrate=number]
#
#           ChkWAN
#                   Will REBOOT router if the PINGs to ALL of the hosts FAILS
#           ChkWAN  force
#                   Will REBOOT router if the PINGs to ALL of the hosts FAIL, but after each group PING attempt, a physical 12MByte data download is attempted.
#           ChkWAN  forcesmall
#                   Will REBOOT router if the PINGs to ALL of the hosts FAIL, but after each group PING attempt, a physical 500Byte data download is attempted.
#                   (For users on a metered connection assuming that the 15Byte cURL is deemed unreliable?)
#           ChkWAN  wan
#                   Will restart the WAN interface (instead of a FULL REBOOT) if the PINGs to ALL of the hosts FAIL
#           ChkWAN  curl
#                   Will REBOOT router if cURL (i.e. NO PINGs attempted) fails to retrieve the remote end-point IP address of the WAN (Max 15bytes)
#           ChkWAN  cron
#                   Will REBOOT router if the PINGs to ALL of the hosts FAILS, cron entry is added: Runs every 5mins.
#                   'cru a ChkWAN "*/5 * * * * /jffs/scripts/ChkWAN.sh"'
#           ChkWAN  nowait
#                   By default the script will wait 10 secs before actually starting the check; 'nowait' (when used by cron) skips this delay.
#           ChkWAN  googleonly
#                   Only the two Google DNS severs will be PING'd - WAN Gateway/local DNS config will be ignored
#           ChkWAN  i=wan1 noaction
#                   In a Dual-WAN environment check WAN1 interface, but if it's DOWN simply return RC=99
#           ChkWAN  ping=1.2.3.4,1.1.1.1
#                   PING the two hosts 1.2.3.4 and 1.1.1.1, rather than the defaults.
#           ChkWAN  tries=1 fails=1
#                   Reduce the number of retry attempts to 1 instead of the default 3 and maximum number of fails is 1 rather than 3
#           ChkWAN  force curlrate=1000000
#                   If the 12MB average curl transfer rate is <1000000 Bytes per second (1MB), then treat this as a FAIL

# [URL="https://www.snbforums.com/threads/need-a-script-that-auto-reboot-if-internet-is-down.43819/#post-371791"]Need a script that auto reboot if internet is down[/URL]

ShowHelp() {
	awk '/^#==/{f=1} f{print; if (!NF) exit}' $0
}
ANSIColours() {

	cRESET="\e[0m";cBLA="\e[30m";cRED="\e[31m";cGRE="\e[32m";cYEL="\e[33m";cBLU="\e[34m";cMAG="\e[35m";cCYA="\e[36m";cGRA="\e[37m"
	cBGRA="\e[90m";cBRED="\e[91m";cBGRE="\e[92m";cBYEL="\e[93m";cBBLU="\e[94m";cBMAG="\e[95m";cBCYA="\e[96m";cBWHT="\e[97m"
	aBOLD="\e[1m";aDIM="\e[2m";aUNDER="\e[4m";aBLINK="\e[5m";aREVERSE="\e[7m"
	cRED_="\e[41m";cGRE_="\e[42m"

}
Say(){
   echo -e $$ $@ | logger -st "($(basename $0))"
}
SayT(){
   echo -e $$ $@ | logger -t "($(basename $0))"
}
Is_Private_IPv4() {
	# 127.  0.0.0 – 127.255.255.255     127.0.0.0 /8
	# 10.   0.0.0 –  10.255.255.255      10.0.0.0 /8
	# 172. 16.0.0 – 172. 31.255.255    172.16.0.0 /12
	# 192.168.0.0 – 192.168.255.255   192.168.0.0 /16
	#grep -oE "(^192\.168\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])$)|(^172\.([1][6-9]|[2][0-9]|[3][0-1])\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])$)|(^10\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])\.([0-9]|[0-9][0-9]|[0-2][0-5][0-5])$)"
	grep -oE "(^127\.)|(^(0)?10\.)|(^172\.(0)?1[6-9]\.)|(^172\.(0)?2[0-9]\.)|(^172\.(0)?3[0-1]\.)|(^169\.254\.)|(^192\.168\.)"
}
Get_WAN_IF_Name () {

	local INDEX=0
	
	if [ -n "$1" ];then
		local INDEX=$1
	fi
	
	local IF_NAME=$(nvram get wan${INDEX}_ifname)				# DHCP/Static ?

	# Usually this is probably valid for both eth0/ppp0e ?
	if [ "$(nvram get wan${INDEX}_gw_ifname)" != "$IF_NAME" ];then
		local IF_NAME=$(nvram get wan${INDEX}_gw_ifname)
	fi

	if [ -n "$(nvram get wan0_pppoe_ifname)" ];then
		local IF_NAME="$(nvram get wan0_pppoe_ifname)"		# PPPoE
	fi

	echo $IF_NAME

}
Check_WAN(){

    CNT=0
    STATUS=0

	local PING_INTERFACE=
	local CURL_INTERFACE=
	if [ -n "$DEV" ];then							# Specific interface requested?
		PING_INTERFACE="-I "$DEV
		CURL_INTERFACE="--interface "$DEV
	fi

	# If the WAN IP is '0.0.0.0' then no point in pinging this as it will actually ping 127.0.0.1 and give a false positive.
	if [ "$1" == "0.0.0.0" ];then
		return 1
	fi

	echo -en $cBYEL
	if [ "$1" != "CURL" ];then								# Assume $1 is a PING target
		while [ $CNT -lt $TRIES ]; do
				ping $PING_INTERFACE -q -c 1 -W 2 $1 2> /dev/null
				local RC=$?
				if [ $RC -eq 0 ];then
					STATUS=1
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
	else
		IP=$(curl $CURL_INTERFACE --connect-timeout 5 -s "http://ipecho.net/plain")		# Max 15 char retrieval
		if [ -n "$IP" ];then
			STATUS=1
		fi
	fi

	# FORCE a cURL data transfer retrieval to confirm?
	if [ -n "$2" ];then
		if [ "$QUIET" != "quiet" ];then
			TXT_RATE=
			if [ $FORCE_WGET_MIN_RATE -gt 0 ];then
				TXT_RATE="NOTE: Transfer rate must be faster than "$FORCE_WGET_MIN_RATE" Bytes/sec"
			fi
			echo -en $cBWHT"\n"
			CURL_TXT="Starting cURL 'big' data transfer.....(Expect 12MB approx @3.1MB/sec on 20Mbps download = 00:04 secs)"
			if [ "$2" == "$FORCE_WGET_500B" ];then
				CURL_TXT="Starting cURL 'small' data transfer.....(Expect 500Byte download = <1 second)"
			fi
			Say $CURL_TXT
			if [ -n "TXT_RATE" ];then
				Say $TXT_RATE
			fi
			echo -en $cBYEL
		fi
		WGET_DATA=$2
		#wget -O /dev/null -t2 -T2 $WGET_DATA
		RESULTS=$(curl $CURL_INTERFACE  -s $WGET_DATA -w "%{time_connect},%{time_total},%{speed_download},%{http_code},%{size_download},%{url_effective}\n" -o /dev/null)
		RC=$?
		if [ $RC -eq 0 ];then
			STATUS=1
			FORCE_OK=1												# Used to make this a priority status summary
			case "$2" in
				"$FORCE_WGET_12MB") Say "cURL $(($(echo $RESULTS | cut -d',' -f5)/1000000))MByte transfer took:" $(printf "00:%05.2f secs @%6.0f B/sec" "$(echo $RESULTS | cut -d',' -f2)" "$(echo $RESULTS | cut -d',' -f3)")
									;;
				"$FORCE_WGET_500B") Say "cURL $(($(echo $RESULTS | cut -d',' -f5)))Byte transfer took:" $(printf "00:%05.2f secs @%6.0f B/sec" "$(echo $RESULTS | cut -d',' -f2)" "$(echo $RESULTS | cut -d',' -f3)")
									;;
				*)					Say "cURL $(($(echo $RESULTS | cut -d',' -f5)))transfer took:" $(printf "00:%05.2f secs" "$(echo $RESULTS | cut -d',' -f2)")
									;;
			esac
			
			# Check if transfer rate is less than the specified acceptable rate 
			#Say "***DEBUG FORCE_WGET_MIN_RATE="$FORCE_WGET_MIN_RATE
			if [ $(echo $RESULTS | cut -d',' -f3 | cut -d'.' -f1) -lt $FORCE_WGET_MIN_RATE ];then
				STATUS=0
				echo -en $cBRED"\n\a"
				Say "***ERROR cURL file transfer rate '"$(echo $RESULTS | cut -d',' -f3 | cut -d'.' -f1)"' Bytes/sec, is less than the acceptable minimum specified '"$FORCE_WGET_MIN_RATE"' Bytes/sec" 
				echo -en $cBYEL
				METHOD=" using MINIMIUM acceptable cURL transfer rate"
			fi
		else
			echo -en $cBRED
			Say "***ERROR WGET '"$WGET_DATA"' transfer FAILED RC="$RC
			FORCE_OK=0
			if [ $RC -ne 8 ];then
				STATUS=0												# Override PING/curl status!!
			else
				Say "*Warning WGET '"$WGET_DATA"' URL invalid?"		# URL invalid so could be OFFLINE so ignore it
			fi
		fi
	fi
}
#=============================================================Main==============================================================
Main(){}

ANSIColours

MYROUTER=$(nvram get computer_name)
FIRMWARE=$(echo $(nvram get buildno) | awk 'BEGIN { FS = "." } {printf("%03d%02d",$1,$2)}')

# Can only run in Router Mode;
#if [ "$(Check_Router_Mode)" != "Router" ];then
	#echo -e "\e[41m\a\n\n\n\n\t\t\t\t** "$(Check_Router_Mode)" mode is not supported stand-alone; Ensure main router is configured **\t\t\t\t\t\n\n\n\e[0m"

#fi

METHOD=
ACTION="REBOOT"
FORCE_WGET_500B="http://proof.ovh.net/files/md5sum.txt"
FORCE_WGET_12MB="http://proof.ovh.net/files/100Mb.dat"
FORCE_WGET=
FORCE_OK=0
FORCE_WGET_MIN_RATE=0										# v1.09 Minimum acceptable transfer rate in Bytes per second 

QUIET=

# Validate args if supplied
if [ -n "$1" ];then
	if [ $(echo $@ | grep -c "debug") -gt 0 ];then			# 'debug'	requested?
		DEBUG="debug"
		if [ "$1" == "debug" ];then
			shift											# Remove from arg list!
		fi
		set -x												# Enable trace
	fi

	if [ "$(echo $@ | grep -cw 'reboot')" -gt 0 ];then
		ACTION="REBOOT"
	fi

	if [ "$(echo $@ | grep -cw 'wan')" -gt 0 ];then
		ACTION="WANONLY"
	fi

	# cURL transfer....so allow specification of minimum transfer rate to be provided by User
	if [ "$(echo $@ | grep -cw 'force')" -gt 0 ] || [ "$(echo $@ | grep -cw 'forcebig')" -gt 0 ] || [ "$(echo $@ | grep -cw 'forcesmall')" -gt 0 ];then
	
		if [ "$(echo $@ | grep -cw 'forcesmall')" -gt 0 ];then
			FORCE_WGET=$FORCE_WGET_500B
		else
			FORCE_WGET=$FORCE_WGET_12MB
		fi
	
		if [ "$(echo $@ | grep -c 'curlrate=')" -gt 0 ];then				# v1.09 Minimum acceptable cURL transfer rate specified? 
			FORCE_WGET_MIN_RATE="$(echo "$@" | sed -n "s/^.*curlrate=//p" | awk '{print $1}' | grep -E "[[:digit:]]")"
			if [ -z "$FORCE_WGET_MIN_RATE" ];then
				echo -en $cBRED"\a\n\t"
				Say "***ERROR cURL minimum acceptable transfer RATE INVALID 'i="$(echo "$@" | sed -n "s/^.*curlrate=//p" | awk '{print $1}')"'"
				echo -en $cRESET
				exit 998
			fi
		fi
	fi

	if [ "$(echo $@ | grep -cw 'quiet')" -gt 0 ];then
		QUIET="quiet"
	fi

	if [ "$(echo $@ | grep -cw 'once')" -gt 0 ];then
		ONCE="once"
	fi
	
	WAN_NAME="WAN"
	THIS="wan0"
	DEV=
	if [ "$(echo $@ | grep -c 'i=')" -gt 0 ];then				# Specific WAN interface specified? v1.08
		WAN_NAME="$(echo "$@" | sed -n "s/^.*i=//p" | awk '{print $1}' | tr 'a-z' 'A-Z')"
		THIS=$(echo "$WAN_NAME" | tr 'A-Z' 'a-z')
		WAN_INDEX=$(echo "$THIS" | tr -d '[a-z]')
		DEV=$(Get_WAN_IF_Name "$WAN_INDEX")						# Virtual 'wan0/wan1' -> $dev e.g. 'wan0' -> 'eth0' v1.08a
		if [ -z "$DEV" ];then
			echo -en $cBRED"\a\n\t"
			Say "***ERROR WAN interface INVALID 'i="$(echo "$@" | sed -n "s/^.*i=//p" | awk '{print $1}')"'"
			echo -en $cRESET
			exit 999
		fi
	fi

	if [ "$(echo $@ | grep -cw 'cron')" -gt 0 ];then
		if [ -n "$(cru l | grep "$0")" ];then
			CRON_ARGS=$(echo $@ | sed -e 's/\<cron\>//g')	# Strip 'cron' from being passed to the cru entry
			cru d Wan_Check
			cru a Wan_Check "*/30 0 * * * /jffs/scripts/$0 $CRON_ARGS"		# Every 30 mins on the half hour
			CRONJOB=$(cru l | grep "$0")
			Say "ChkWAN scheduled by cron"
			echo -e "$CRONJOB"
		fi
	fi

fi

# Generate appropriate PING target Hosts.....
if [ "$(echo $@ | grep -cw 'googleonly')" -gt 0 ];then
		HOSTS="8.8.8.8 8.8.4.4"
else
	# cURL rather than PING requested? but 'ping=xxx.xxx.xxx.xxx' directive overrides 'curl'
	if [ "$(echo $@ | grep -cw 'curl')" -gt 0 ] && [ "$(echo $@ | grep -c 'ping=')" -eq 0 ];then
		HOSTS="CURL CURL"										# Sometimes the first request returns blank??
	else
		if [ "$(echo $@ | grep -c 'ping=')" -gt 0 ];then
			HOSTS="$(echo "$@" | sed -n "s/^.*ping=//p" | awk '{print $1}' | tr ',' ' ')"		# Custom .CSV list specified
		else
			if [ "$DEV" != "ppp0" ];then
				# List of PING hosts to check...the 1st I/P is usually the appropriate default gateway (except for ppp0!) for the specified WAN interface,
				# Include 												Google/Cloudflare public DNS
				HOSTS="$(nvram get ${THIS}_gateway) $(nvram get wan_dns) 8.8.8.8 1.1.1.1"		# Target PING hosts
			else
				HOSTS="$(nvram get wan_dns) 8.8.8.8 1.1.1.1"		# Target PING hosts excludes the non-PINGable ppp0!
			fi
		fi
	fi
fi

DEV_TXT=														# v1.08a
if [ -n "$DEV" ];then
	DEV_TXT="("$DEV")"
fi

# Help request ?
if [ "$1" == "help" ] || [ "$1" == "-h" ];then
   echo -e $cBWHT
   ShowHelp							# Show help
   echo -e $cRESET
   exit 0
fi


# No of times to check each host before trying next
TRIES=3										# TRIES=3 With 5 hosts and PING ONLY usually recovery action is initiated within 01:30 minutes?
											# TRIES=3 With 5 hosts and WGET;     usually recovery action is initiated within 03:30 minutes?
if [ "$(echo $@ | grep -c 'tries=')" -gt 0 ];then
	TRIES="$(echo "$@" | sed -n "s/^.*tries=//p" | awk '{print $1}')"		# Custom number of tries
fi
											
# How often to check if WAN connectivity is found to be OK
INTERVAL_SECS=30

# How long to wait between the TRIES attempts if ALL hosts FAIL
INTERVAL_ALL_FAILED_SECS=10

# How many cycle fails before recovery ACTION taken/issued
MAX_FAIL_CNT=3
if [ "$(echo $@ | grep -c 'fails=')" -gt 0 ];then
	MAX_FAIL_CNT="$(echo "$@" | sed -n "s/^.*fails=//p" | awk '{print $1}')"		# Custom number of Fails v1.08b
fi

STATUS=0

FAIL_CNT=0

if [ "$(echo $@ | grep -cw 'nowait')" -eq 0 ] && [ "$QUIET" != "quiet" ];then
	echo -e $cBCYA
	Say  $VER $WAN_NAME "connection status monitoring will begin in" $INTERVAL_ALL_FAILED_SECS "seconds....."
	sleep $INTERVAL_ALL_FAILED_SECS
fi

TXT="$(echo $HOSTS | wc -w) target PING hosts ("$HOSTS")"
if [ "$HOSTS" == "CURL CURL" ];then
	TXT="using cURL data IP retrieval method"
fi

if [ "$QUIET" != "quiet" ];then
	echo -e $cBMAG
	Say $VER "Monitoring" $WAN_NAME $DEV_TXT "connection using" $TXT "(Tries="$TRIES")"
fi


if [ "$QUIET" != "quiet" ];then
	echo -en $cBWHT
	Say "Monitoring pass" $(($FAIL_CNT+1)) "out of" $TRIES
fi

while [ $FAIL_CNT -lt $MAX_FAIL_CNT ]; do
    for TARGET in $HOSTS; do
        UP=0;
		IP=

		# Check if PING target is 'private'; indicating ASUS is behind another router (double NAT) or DNS is a local server
		if [ -n "$(echo $TARGET | Is_Private_IPv4)" ];then
				Say "Private LAN" $TARGET "will be skipped for WAN PING check!"
				continue
		else
			echo -en $cRESET
			Check_WAN $TARGET $FORCE_WGET
			if [ $STATUS -gt 0 ]; then
				UP=1
				break
			else
				echo -e $cRED
				if [ -z "$METHOD" ] || [ -n "$(echo "$METHOD" | grep "PING")" ];then				# v1.10
					METHOD="using PING method to "$TARGET
					if [ "$HOSTS" == "CURL CURL" ];then
						METHOD="using cURL data IP retrieval method"
					fi
				fi
				Say $VER "Monitoring" $WAN_NAME $DEV_TXT "connection" $METHOD "check FAILED"
			fi
		fi
    done

    if [ $UP -gt 0 ]; then
        FAIL_CNT=0
		echo -e $cBGRE
		TXT="Successful ping to '"$TARGET"'"
		if [ "$HOSTS" == "CURL CURL" ];then
			TXT="cURL successfully retrieved WAN end-point IP='"$IP"'"
		fi
		
		if [ "$FORCE_OK" -eq 1 ];then
			if [ "$FORCE_WGET" == "$FORCE_WGET_12MB" ];then
				TXT="using 'default' 12MByte cURL data transfer OK"
			else
				TXT="using 'small' ~500Byte cURL data transfer OK"
			fi
		fi
		
		if [ -z "$(cru l | grep "$0")" ];then
			if [ -z "$ONCE" ];then
				if [ "$QUIET" != "quiet" ];then
					Say "Monitoring" $WAN_NAME $DEV_TXT "connection OK.....("$TXT"). Will check" $WAN_NAME "again in" $INTERVAL_SECS "secs"
					echo -en $cRESET
				fi

				sleep $INTERVAL_SECS
			else
				Say "Monitoring" $WAN_NAME $DEV_TXT "connection OK.....("$TXT")."
				echo -en $cRESET
				exit 0
			fi
		else
			if [ "$QUIET" != "quiet" ];then
				Say "Monitoring" $WAN_NAME $DEV_TXT "connection OK.....("$TXT"); Terminating due to ACTIVE cron schedule"
				echo -e $cRESET
			fi
			exit 0
		fi
    else
        FAIL_CNT=$((FAIL_CNT+1))
		if [ $FAIL_CNT -ge $MAX_FAIL_CNT ];then
			break
		fi
		sleep $INTERVAL_ALL_FAILED_SECS

		if [ "$QUIET" != "quiet" ];then
			echo -e $cBWHT
			Say "Monitoring pass" $(($FAIL_CNT+1)) "out of" $TRIES
		fi
		echo -en $cRESET
    fi
done

# Was 'noaction' specified ?									# v1.08
if [ "$(echo $@ | grep -cw 'noaction')" -gt 0 ];then
	echo -en $cRESET
	exit 99
fi

echo -e $cBYEL"\a"
# Failure after $INTERVAL_ALL_FAILED_SECS*$MAX_FAIL_CNT secs ?
if [ "$ACTION" == "WANONLY" ];then
	Say "Renewing DHCP and restarting" $WAN_NAME "(Action="$ACTION")"
	killall -USR1 udhcpc
	sleep 10
	if [ -z "$WAN_INDEX" ];then
		service restart_wan
	else
		service "restart_wan_if $WAN_INDEX"
	fi

	#Say "Re-requesting monitoring....in" $INTERVAL_SECS "secs"
	#sleep $INTERVAL_SECS
	#sh /jffs/scripts/$0 &							# Let wan-start 'sh /jffs/scripts/ChkWAN.sh &' start the monitoring!!!!!

else
	echo -e ${cBRED}$aBLINK"\a\n\n\t"
	Say "Rebooting..... (Action="$ACTION")"
	echo -e "\n\t\t**********Rebooting**********\n\n"$cBGRE
	service start_reboot							# Default REBOOT
fi

echo -e $cRESET"\n"
