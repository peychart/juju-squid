#!/bin/bash
# 201506-Philippe.eychart@informatique.gov.pf
# licence GNU-v3
set -e
hook_name=$(basename $(echo $0|grep -v bash))
hook_name=${hook_name:="hook.sh"}
mytmp="/tmp/.${hook_name}$(date +%Y%m%d.%H%M%S)"
trap "rm -f $mytmp" 0 1 2 3 5

default_squid3_config_dir="/etc/squid3"
default_squid3_config=${default_squid3_config_dir}"/squid.conf"
default_squid3_config_cache_dir="/var/run/squid3"
templates_dir="../templates"

DEBUG=1

refresh_patterns=$(config-get 'refresh_patterns' 2>/dev/null || true)
[ $DEBUG -ne 0 ] && refresh_patterns=${refresh_patterns:='{"http://www.ubuntu.com": {min: 0, percent: 20, max: 60}, "http://www.canonical.com": {min: 0, percent: 20, max: 120}}'}

################################################################################
# Supporting functions
################################################################################
open_port()    { [ -z "$(which open-port)"  ] || for i in $*; do open-port  $i; done; }
close_port()   { [ -z "$(which open-close)" ] || for i in $*; do close-port $i; done; }
format_jshon() { sed -e 's/\([^"A-Za-z]\)\([A-Za-z][A-Za-z]*\):/\1"\2":/g'; }
config.port()  { local p=$(config-get port || true); echo ${p:="3128"}; }

refresh_patterns.keys() {
 [ -z "$refresh_patterns" ] || echo $refresh_patterns| format_jshon| jshon -k
}

refresh_patterns() {
 [ -z "$refresh_patterns" ] || \
  echo $refresh_patterns| format_jshon| jshon $(while [ $# -ne 0 ]; do
   echo "-e $1"; shift
  done)
}

apt_get_install() {
 juju-log "installing packages"
 DEBIAN_FRONTEND=noninteractive apt-get -y install $*
}

################################################################################
# End "Supporting functions"
################################################################################
resource_template() { local dest=$2; [ -z "$2" ] || dest=">$dest"
 <$0 awk '{ if ( $0 ~ /resource_template()/ ) bool=1; if (!bool) print $0 }' >$mytmp
 cat >>$mytmp <<EOF
cat $dest <<@@@
EOF
 cat >>$mytmp <$templates_dir/$1
 cat >>$mytmp <<EOF
@@@
EOF
 [ $DEBUG -ne 0 ] && less $mytmp
 $SHELL $mytmp
 [ $DEBUG -ne 0 ] && less $2
}
################################################################################


################################################################################
# Hook functions
################################################################################
install_hook() {
 [ -z "$(which jshon)" ] && apt_get_install jshon
 [ -z "$(which jshon)" ] && juju-log "the \"jshon\" command is not installed!" && exit 1
 [ $DEBUG -eq 0 ] && apt_get_install squid
 resource_template "main_config.template" "/tmp/squid.conf"
}

config_changed() {
 echo;
}

start_hook() {
 echo;
}

stop_hook() {
 echo;
}

proxy_interface() {
 echo;
}

################################################################################
# Main section
################################################################################
[ $DEBUG -ne 0 ] && install_hook

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
