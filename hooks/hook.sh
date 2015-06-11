#!/bin/bash
# 201506-Philippe.eychart@informatique.gov.pf
# licence GNU-v3
set -e
hook_name=$(basename $(echo $0| grep -v bash))
hook_name=${hook_name:="hook.sh"}
TEMPLATES_DIR='templates'
cd $(dirname $0)
mytmp="/tmp/.${hook_name}$(date +%Y%m%d.%H%M%S)"
trap "rm -f $mytmp" 0 1 2 3 5

default_squid3_config_dir="/etc/squid3"
default_squid3_config=${default_squid3_config_dir}"/squid.conf"
default_squid3_config_cache_dir="/var/run/squid3"

############################### TO REMOVE ######################################
DEBUG=1
nop() { echo -e "\c"; }
# JUJU ENV... (to comment)
config-get() { shift
 case $1 in
  snmp_community)	echo "public";;
  snmp_allowed_ips)	echo '["192.168.10.100", "10.0.0.0/8"]';;
  refresh_patterns)	echo '{"http://www.ubuntu.com": {"min": 0, "percent": 20, "max": 60}, "http://www.canonical.com": {"min": 0, "percent": 20, "max": 120}}';;
  cache_dir)		echo '/var/spool/squid3';;
  max_obj_size_kb)	echo '8192';;
  cache_size_mb)	echo '512';;
  cache_mem_mb)		echo '256';;
  target_objs_per_dir)	echo '400';;
  avg_obj_size_kb)	echo '16';;
  log_format)		echo '%>a %ui %un [%tl] "%rm %ru HTTP/%rv" %>Hs %<st "%{Referer}>h" "%{User-Agent}>h" %Ss:%Sh';;
  auth_list)		echo '[{"dstdomain": ["www.ubuntu.com"], "src": ["1.2.3.4", "5.6.7.0/24"]}, {"url_regex": ["https?://[^/]+[.]internal(/.*)?"], "src": ["192.168.0.0/16"]}]';;
  *) false
 esac
}
# End JUJU ENV (to comment)
############################### END "TO REMOVE" ################################

################################################################################
# Supporting functions in templates
################################################################################
open_port()    { [ -z "$(which open-port)"  ] || for i in $*; do open-port  $i; done; }
close_port()   { [ -z "$(which open-close)" ] || for i in $*; do close-port $i; done; }
get_config()   { config-get '--format=json' $1; }
service_ports(){ [ -z "$1" ] || egrep -w "http_port" $1| egrep -w "([0-9]+)"; }
get_json_keys(){ jshon -k || true; }
get_json_len() { jshon -l || true; }
get_json()     { #Syntaxe: echo <String>| get_json <key>  # cf. man jshon
 [ -z "$*" ] || jshon $(while [ $# -ne 0 ]; do echo "-e $1"; shift; done)| sed -e 's;\\/;/;g'
}

cache_l1() { local r
 r=$(expr $(get_config cache_size_mb) \* 64 )
 r=$(expr $r / $(get_config target_objs_per_dir))
 r=$(expr $r / $(get_config avg_obj_size_kb))
 expr $r \* $r
}

# End "Supporting functions"
################################################################################
resource_template() {
 <$hook_name awk '{ if ( $0 ~ /resource_template()/ ) bool=1; if (!bool) print $0 }' >$mytmp
 echo "cat $([ -z "$2" ] || echo '>')$2 <<@@@" >>$mytmp
 cat >>$mytmp <../$TEMPLATES_DIR/$1
 echo "@@@" >>$mytmp
 [ 0$DEBUG -ne 0 ] && less $mytmp
 $SHELL $mytmp
 [ 0$DEBUG -ne 0 -a ! -z "$2" ] && less $2
}

################################################################################
# Hook functions
################################################################################
source ./utils.sh

relation_json() { # $0 scope unit_name relation_id
 local a
 [ -z "$3" ] || a="-r $3"; if [ -z "$1" ]; then a="$a -"; else a="$a $1"; fi
 relation-get --format=json $a $2
}

relation_ids() { # $0 relation_type
 local reltype reltypes
 reltypes=( $* )
 for reltype in ${reltypes[@]}; do
  relation-ids --format=json $reltype
 done
}

relation_get_all() { local reldata relid unit
 for relid in $(relation_ids| get_json_keys); do
  for unit in $(seq 0 $(expr $(relation-list --format=json -r $relid| get_json_lena) - 1)); do
   relation-list --format=json -r $relid| get_json $unit
  done
 done
}

install_hook() {
 [ -z "$(which jshon)" ] \
   && juju_log "installing packages" \
   && DEBIAN_FRONTEND=noninteractive apt_get -y install jshon
 [ -z "$(which jshon)" ] && juju_log "the \"jshon\" command is not installed!" && exit 1

 [ 0$DEBUG -eq 0 ] \
   && juju_log "installing packages" \
   && DEBIAN_FRONTEND=noninteractive apt_get -y install squid

 [ -d $default_squid3_config_dir ] || mkdir -p $default_squid3_config_dir
 [ ! -e $default_squid3_config ] || \
   cp -pf $default_squid3_config $default_squid3_config.$(date +%y%m%d.%H%M%S)

 resource_template "main_config.template" $default_squid3_config
}
[ 0$DEBUG -ne 0 ] && install_hook

config_changed() {
 nop
}

start_hook() {
 nop
}

stop_hook() {
 nop
}

proxy_interface() {
 nop
}

################################################################################
# Main section
################################################################################
case "$hook_name" in
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
 *)	echo "Unknown hook" && false
esac
