#!/bin/bash
TEMPLATES_DIR=${TEMPLATES_DIR:='templates'}
TCP='TCP'
UDP='UDP'
expose()       { local p=$2; open-port $1 ${p:="TCP"}; }
juju_log()     { local l;[ ! -z "$2" ] && l="--log-level $1" && shift; juju-log $l $*; }
relation_ids() { relation-ids $*; }
relation_list(){ relation-list -r $*; }
relation_get() { local a; [ -z "$3" ] && a="-r $3"; a="$a $1" [ -z "$2" ] && a="$a $2"; relation-ids $a; }
relation_set() { local a b;
 while [ $# -ne 0 ]; do
  if [ $1 == 'rid' ]; then
   a="$a -r $2"
  else
   b="$b $1=$2"
  fi; shift 2
 done
 relation-set $a $b;
}
unit_get()     { unit-get $*; }
get_unit_hostname() { hostname; }
get_host_ip()  { dig +short $(hostname); }
