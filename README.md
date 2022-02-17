# ChkWAN
ASUS Router Check WAN status


This script can monitor the connection status of a WAN interface, and if the status is found to be unacceptable, can perform one of the following:

      1. Report the status of the WAN connection.
      2. Attempt to restart the WAN interface.
      3. REBOOT the router.
  
The monitoring method is either

1.	A simple PING to 5 predefined target PING hosts

		ISP WAN_gateway
		ISP_DNS 		x 2
		8.8.8.8			(Google Primary DNS)
		1.1.1.1			(Cloudflare Primary DNS)
		
		or a custom list of WAN PING targets e.g. ping=9.9.9.9,185.228.168.9 (Quad9 Primary DNS, Clean Browsing Primary)

2.	A cURL data transfer retrieval from the WAN - either a 15 Byte (default) or either a ~500 Byte or 12MB. 
   
		**Beware if using a metered connection!**
		
		Optionally an expected transfer rate may be specified to perform the desired action if the transfer is deemed slow.

NOTE: Only one of the test criteria needs to succeed, i.e. if 5 PING hosts are used, the test will terminate with the first successful host that responds to the PING - ignoring the others.

  To prevent transient false positives, the number of retries and a maximum number of fails permitted for each method defaults to       retries=3 and fails=3, and be tailored
  e.g. retries=1 fails=1 whilst the result being immediate, may seemingly fail, due to the PING or cURL target entity being briefly   unavailable 

The complete list of command options may be retrieved using
  
  	ChkWAN.sh   help

```
#============================================================================================ © 2016-2020 Martineau v1.15
#
# Monitor WAN connection state using PINGs to multiple hosts, or a single cURL 15 Byte data request and optionally a 12MB/500B WGET/CURL data transfer.
#         NOTE: The cURL data transfer rate/perfomance threshold may also be checked e.g. to switch from a 'slow' (Dual) WAN interface.
#         Usually the Recovery action (REBOOT or restart the WAN) occurs in about 90 secs (PING ONLY) or in about 03:30 mins for 'force' data download
#
# Usage:    ChkWAN  [help|-h]
#                   [reboot | wan | noaction] [force[big | small]] [nowait] [quiet] [once] [i={[wan0|wan1]}] [googleonly] [curl] [ping='ping_target[,..]']
#                   [tries=number] [fails=number] [curlrate=number] [verbose] [cron[=[cron_spec]]] [status] [stop]
#
#           ChkWAN
#                   Will REBOOT router if the PINGs to ALL of the hosts FAILS
#           ChkWAN  force
#                   Will REBOOT router if the PINGs to ALL of the hosts FAIL, but after each group PING attempt, a physical 12MByte data download is attempted.
#           ChkWAN  forcesmall
#                   Will REBOOT router if the PINGs to ALL of the hosts FAIL, but after each group PING attempt, a physical 500Byte data download is attempted.
#                   (For users on a metered connection assuming that the 15Byte cURL is deemed unreliable?)
#           ChkWAN  status
#                   Will report if Check WAN monitor is running
#           ChkWAN  wan
#                   Will restart the WAN interface (instead of a FULL REBOOT) if the PINGs to ALL of the hosts FAIL
#           ChkWAN  stop
#                   Will request termination of script. It will be dependent on the 'sleep' interval
#                   NOTE: If scheduled by cron this will have no effect.
#           ChkWAN  curl
#                   Will REBOOT router if cURL (i.e. NO PINGs attempted) fails to retrieve the remote end-point IP address of the WAN (Max 15bytes)
#           ChkWAN  cron
#                   Will REBOOT router if the PINGs to ALL of the hosts FAILS, cron entry is added: Runs every 30mins.
#                   'cru a ChkWAN "*/30 * * * * /jffs/scripts/ChkWAN.sh"'
#           ChkWAN  cron=\*/5
#                   Will REBOOT router if the PINGs to ALL of the hosts FAILS, cron entry is added: Runs every 5mins.
#                   'cru a ChkWAN "*/5 * * * * /jffs/scripts/ChkWAN.sh"'
#                   NOTE: You need to escape the '*' on the commandline :-(
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
#           ChkWAN  curl verbose
#                   The 'verbose' directive applies to any cURL transfer, and will display the cURL request data transfer as it happens

```


Installation

Enable SSH on router, then use your preferred SSH Client e.g. Xshell6,MobaXterm, PuTTY etc. to copy'n'paste:

	curl --retry 3 "https://raw.githubusercontent.com/MartineauUK/Chk-WAN/master/ChkWAN.sh" -o "/jffs/scripts/ChkWAN.sh" && chmod 755 "/jffs/scripts/ChkWAN.sh"

You can manually test the script with the default PING method, and the script will simply passively report the status, rather proactively restart the WAN or REBOOT

	./ChkWAN.sh noaction once nowait

but for automated monitoring, you would include the call to the script in

~~/jffs/scripts/wan-start~~
deprecated https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#wan-start

/jffs/scripts/wan-event see https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts#wan-event

e.g. The following can be pasted into a SSH terminal (assuming **__'/jffs/scripts/wan-event'__** doesn't already exist)
	
    cat > /jffs/scripts/wan-event << EOF;chmod +x /jffs/scripts/wan-event
    #!/bin/sh

    if [ "\$2" == "connected" ];then
       #sleep 5
       # No need for recommended 'sleep n' as ChkWAN.sh has default 10 secs delay
       # Check WAN connectivity every 30 seconds (Possibly excessive!)
       sh /jffs/scripts/CHKWAN.sh &
    fi
    EOF

or preferably use cru (cron) to schedule the script at a pre-determined scheduled time

e.g. Every 5 minutes

    cat > /jffs/scripts/wan-event << EOF;chmod +x /jffs/scripts/wan-event
    #!/bin/sh

    if [ "\$2" == "connected" ];then
       # sleep 5
       # No need for recommended 'sleep n' as ChkWAN.sh has default 10 secs delay
       # Check WAN connectivity every 5 minutes
       sh /jffs/scripts/ChkWAN.sh cron="\*/5 \* \* \* \*" &
    fi
    EOF

Check desired cru (cron) schedule has been created

    cru l
    
    */5 * * * * /jffs/scripts/ChkWAN.sh #WAN_Check#


NOTE: You could configure the cron schedule such that the scipt will restart the WAN say 3 times, but every fourth attempt will action the REBOOT.
