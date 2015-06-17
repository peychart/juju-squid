#!/bin/bash
# 201506-Philippe.eychart@informatique.gov.pf
# licence GNU-v3
set -e
hook_name=$(basename $(echo $0| sed -e 's;.* ;;'))
dirname=$(dirname $(echo $0| sed -e 's;.* ;;'))
TEMPLATES_DIR='templates'
mytmp="/tmp/.${hook_name}$(date +%Y%m%d.%H%M%S)"
trap "rm -f $mytmp" 0 1 2 3 5

default_squid3_config_dir="/etc/squid3"
default_squid3_config=${default_squid3_config_dir}"/squid.conf"
default_squid3_config_cache_dir="/var/run/squid3"

DEBUG=0

################################################################################
# Supporting functions in templates
################################################################################
open_port()    { [ -z "$(which open-port)"  ] || for i in $*; do open-port  $i; done; }
close_port()   { [ -z "$(which open-close)" ] || for i in $*; do close-port $i; done; }
service_ports(){ [ -z "$1" ] || egrep -w "http_port" $1| egrep -w "([0-9]+)"; }
get_json_keys(){ jshon -k || true; }
get_json_len() { jshon -l || true; }
get_json()     { #Syntaxe: echo <String>| get_json <key>  # cf. man jshon
 [ -z "$*" ] || jshon $(while [ $# -ne 0 ]; do echo "-e $1"; shift; done)| sed -e 's;\\/;/;g' -e 's/^"//' -e 's/"$//'
}
get_config()   { config-get $*; }

cache_l1() { local r
 r=$(expr $(get_config cache_size_mb) \* 64 )
 r=$(expr $r / $(get_config target_objs_per_dir))
 r=$(expr $r / $(get_config avg_obj_size_kb))
 expr $r \* $r
}

# End "Supporting functions"
################################################################################
resource_template() {
 <$dirname/$hook_name awk '{ if ( $0 ~ /resource_template()/ ) bool=1; if (!bool) print $0 }' >$mytmp
 echo "cat $([ -z "$2" ] || echo '>')$2 <<@@@" >>$mytmp
 cat >>$mytmp <$dirname/../$TEMPLATES_DIR/$1
 echo "@@@" >>$mytmp
 [ 0$DEBUG -eq 0 ] || less $mytmp
 $SHELL $mytmp
 [ 0$DEBUG -eq 0 ] || less $2
}

################################################################################
# Hook functions
################################################################################
source $dirname/utils.sh

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

service_squid3() {
 echo -s "\c"
}

update_service_ports() {
 echo -s "\c"
}

construct_squid3_config() {
 [ -d $default_squid3_config_dir ] || mkdir -p $default_squid3_config_dir
 [ ! -e $default_squid3_config ] || \
   cp -pf $default_squid3_config $default_squid3_config.$(date +%y%m%d.%H%M%S)

 resource_template "main_config.template" $default_squid3_config
}

install_hook() {
 [ -z "$(which jshon)" ] \
   && juju_log "installing packages" \
   && DEBIAN_FRONTEND=noninteractive apt-get -y install jshon
 [ -z "$(which jshon)" ] && juju_log "the \"jshon\" command is not installed!" && exit 1

 juju_log "installing packages squid3" \
   && DEBIAN_FRONTEND=noninteractive apt-get -y install squid

 construct_squid3_config
}

get_service_ports() {
 egrep -w "[^#]*http_port[ \t]+([0-9]+)" $default_squid3_config| sed -s 's/.*http_port[ \t]*//'
}

config_changed() {
 current_service_ports=$(get_service_ports)
 construct_squid3_config

 if service_squid3 'check'; then
  updated_service_ports=$(get_service_ports)
  update_service_ports current_service_ports updated_service_ports
  service_squid3 'reload'
 else
  false
 fi
}

start_hook() {
 if service squid2 status; then
  service squid2 restart
 else
  service squid2 start
 fi
}

stop_hook() {
 service squid2 status \
  && service squid2 stop
}

proxy_interface() {
 case "$1" in
  'joined'|'changed'|'broken'|'departed')
   s=$(get_service_ports)
   if [ ! -z "$s" ]; then
    set $s
    relation-set port=$1
   fi
   config_changed
 esac
}

################################################################################
# Main section
################################################################################
case "$hook_name" in
 'install')
	install_hook			;;
 'config-changed')
	config_changed			;;
 'start')
	start_hook			;;
 'stop')
	stop_hook			;;
 'cached-website-relation-joined')
	proxy_interface 'joined'	;;
 'cached-website-relation-changed')
	proxy_interface 'changed'	;;
 'cached-website-relation-broken')
	proxy_interface 'broken'	;;
 'cached-website-relation-departed')
	proxy_interface 'departed'	;;
 'nrpe-external-master-relation-changed')
	update_nrpe_checks		;;
 'env-dump')
	echo relation_get_all		;;
 *)	echo "Unknown hook" && false
esac
