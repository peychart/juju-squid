#!/bin/bash
# 201506-Philippe.eychart@informatique.gov.pf
# licence GNU-v3
set -e
hook_name=$(basename $(echo $0|grep -v bash))
hook_name=${hook_name:="hook.sh"}
cd $(dirname $0)
mytmp="/tmp/.${hook_name}$(date +%Y%m%d.%H%M%S)"
trap "rm -f $mytmp" 0 1 2 3 5

default_squid3_config_dir="/etc/squid3"
default_squid3_config=${default_squid3_config_dir}"/squid.conf"
default_squid3_config_cache_dir="/var/run/squid3"

DEBUG=1
# JUJU ENV... (to comment)
config-get() { shift
 case $1 in
  snmp_community)	echo "public";;
  snmp_allowed_ips)	echo '["192.168.10.100", "10.0.0.0/8"]';;
  refresh_patterns)	echo '{"http://www.ubuntu.com": {min: 0, percent: 20, max: 60}, "http://www.canonical.com": {min: 0, percent: 20, max: 120}}';;
  cache_dir)		echo '/var/spool/squid3';;
  max_obj_size_kb)	echo '8192';;
  cache_size_mb)	echo '512';;
  cache_mem_mb)		echo '256';;
  target_objs_per_dir)	echo '400';;
  avg_obj_size_kb)	echo '16';;
  log_format)		echo '%>a %ui %un [%tl] "%rm %ru HTTP/%rv" %>Hs %<st "%{Referer}>h" "%{User-Agent}>h" %Ss:%Sh';;
  *) false
 esac
}
# End JUJU ENV (to comment)

################################################################################
# Supporting functions
################################################################################
open_port()    { [ -z "$(which open-port)"  ] || for i in $*; do open-port  $i; done; }
close_port()   { [ -z "$(which open-close)" ] || for i in $*; do close-port $i; done; }
format_jshon() { sed -e 's/\([^"A-Za-z]\)\([A-Za-z][A-Za-z]*\):/\1"\2":/g'; }
get_config()   { config-get '--format=json' $1; }
service_ports(){ [ -z "$1" ] || egrep -w "http_port" $1| egrep -w "([0-9]+)"; }
get_json_keys(){ [ -z "$*" ] || echo "$*"| format_jshon| jshon -k; }
get_json_len() { [ -z "$*" ] || echo "$*"| format_jshon| jshon -l; }
get_json()     { 
 [ -z "$*" ] || format_jshon| jshon $(while [ $# -ne 0 ]; do echo "-e $1"; shift; done)
}

cache_l1() { local r
 r=$(expr $(get_config cache_size_mb) \* 64 )
 r=$(expr $r / $(get_config target_objs_per_dir))
 r=$(expr $r / $(get_config avg_obj_size_kb))
 r=$(expr $r \* $r)
 echo $r
}

apt_get_install() {
 juju-log "installing packages"
 DEBIAN_FRONTEND=noninteractive apt-get -y install $*
}

################################################################################
# End "Supporting functions"
################################################################################
resource_template() { local dest=$2; [ -z "$2" ] || dest=">$dest"
 <$hook_name awk '{ if ( $0 ~ /resource_template()/ ) bool=1; if (!bool) print $0 }' >$mytmp
 cat >>$mytmp <<EOF
cat $dest <<@@@
EOF
 cat >>$mytmp <../templates/$1
 cat >>$mytmp <<EOF
@@@
EOF
 [ 0$DEBUG -ne 0 ] && less $mytmp
 $SHELL $mytmp
 [ 0$DEBUG -ne 0 ] && less $2
}
################################################################################


################################################################################
# Hook functions
################################################################################
install_hook() {
 [ -z "$(which jshon)" ] && apt_get_install jshon
 [ -z "$(which jshon)" ] && juju-log "the \"jshon\" command is not installed!" && exit 1
 [ 0$DEBUG -eq 0 ] && apt_get_install squid
 resource_template "main_config.template" "/tmp/squid.conf"
}

config_changed() {
 echo
}

start_hook() {
 echo
}

stop_hook() {
 echo
}

proxy_interface() {
 echo
}

################################################################################
# Main section
################################################################################
[ 0$DEBUG -ne 0 ] && install_hook

case $hook_name in
 "install")
	install_hook			;;
 "config-changed")
	config_changed			;;
 "start")
	start_hook			;;
 "stop")
	stop_hook			;;
 "cached-website-relation-joined")
	proxy_interface "joined"	;;
 "cached-website-relation-changed")
	proxy_interface "changed"	;;
 "cached-website-relation-broken")
	proxy_interface "broken"	;;
 "cached-website-relation-departed")
	proxy_interface "departed"	;;
 "nrpe-external-master-relation-changed")
	update_nrpe_checks		;;
 "env-dump")
	echo relation_get_all		;;
 *)	echo "Unknown hook"
	exit 1
esac
