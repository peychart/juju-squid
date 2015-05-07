#!/usr/bin/env python

import json
import yaml
import os
import random
import re
import string
import subprocess
import sys
import math
import grp
import pwd
import shutil
import glob
import utils

###############################################################################
# Global variables
###############################################################################
default_squid3_config_dir = "/etc/squid3"
default_squid3_config = "%s/squid.conf" % default_squid3_config_dir
default_squid3_config_cache_dir = "/var/run/squid3"
hook_name = os.path.basename(sys.argv[0])

###############################################################################
# Supporting functions
###############################################################################


#------------------------------------------------------------------------------
# config_get:  Returns a dictionary containing all of the config information
#              Optional parameter: scope
#              scope: limits the scope of the returned configuration to the
#                     desired config item.
#------------------------------------------------------------------------------
def config_get(scope=None):
    try:
        config_cmd_line = ['config-get']
        if scope is not None:
            config_cmd_line.append(scope)
        config_cmd_line.append('--format=json')
        config_data = json.loads(subprocess.check_output(config_cmd_line))
    except Exception, e:
        utils.juju_log('INFO', str(e))
        config_data = None
    finally:
        return(config_data)


#------------------------------------------------------------------------------
# relation_json:  Returns json-formatted relation data
#                Optional parameters: scope, relation_id
#                scope:        limits the scope of the returned data to the
#                              desired item.
#                unit_name:    limits the data ( and optionally the scope )
#                              to the specified unit
#                relation_id:  specify relation id for out of context usage.
#------------------------------------------------------------------------------
def relation_json(scope=None, unit_name=None, relation_id=None):
    try:
        relation_cmd_line = ['relation-get', '--format=json']
        if relation_id is not None:
            relation_cmd_line.extend(('-r', relation_id))
        if scope is not None:
            relation_cmd_line.append(scope)
        else:
            relation_cmd_line.append('-')
        relation_cmd_line.append(unit_name)
        relation_data = subprocess.check_output(relation_cmd_line)
    except Exception, e:
        utils.juju_log('INFO', str(e))
        relation_data = None
    finally:
        return(relation_data)


#------------------------------------------------------------------------------
# relation_get:  Returns a dictionary containing the relation information
#                Optional parameters: scope, relation_id
#                scope:        limits the scope of the returned data to the
#                              desired item.
#                unit_name:    limits the data ( and optionally the scope )
#                              to the specified unit
#                relation_id:  specify relation id for out of context usage.
#------------------------------------------------------------------------------
def relation_get(scope=None, unit_name=None, relation_id=None):
    try:
        relation_data = json.loads(relation_json())
    except Exception, e:
        utils.juju_log('WARNING', str(e))
        relation_data = None
    finally:
        return(relation_data)


#------------------------------------------------------------------------------
# relation_ids:  Returns a list of relation ids
#                optional parameters: relation_type
#                relation_type: return relations only of this type
#------------------------------------------------------------------------------
def relation_ids(relation_type='cached-website'):
    # accept strings or iterators
    if isinstance(relation_type, basestring):
        reltypes = [relation_type]
    else:
        reltypes = relation_type
    relids = []
    for reltype in reltypes:
        relid_cmd_line = ['relation-ids', '--format=json', reltype]
        relids.extend(json.loads(subprocess.check_output(relid_cmd_line)))
    return relids


#------------------------------------------------------------------------------
# relation_get_all:  Returns a dictionary containing the relation information
#                optional parameters: relation_type
#                relation_type: limits the scope of the returned data to the
#                               desired item.
#------------------------------------------------------------------------------
def relation_get_all():
    reldata = {}
    relids = relation_ids()
    for relid in relids:
        units_cmd_line = ['relation-list', '--format=json', '-r', relid]
        units = json.loads(subprocess.check_output(units_cmd_line))
        for unit in units:
            reldata[unit] = json.loads(relation_json(relation_id=relid,
                                                     unit_name=unit))
            if 'sitenames' in reldata[unit]:
                reldata[unit]['sitenames'] = reldata[unit]['sitenames'].split()
            reldata[unit]['relation-id'] = relid
            reldata[unit]['name'] = unit.replace("/", "_")
    return reldata


#------------------------------------------------------------------------------
# load_squid3_config:  Convenience function that loads (as a string) the
#                       current squid3 configuration file.
#                       Returns a string containing the squid3 config or
#                       None
#------------------------------------------------------------------------------
def load_squid3_config(squid3_config_file="/etc/squid3/squid.conf"):
    if os.path.isfile(squid3_config_file):
        return(open(squid3_config_file).read())
    else:
        return(None)


#------------------------------------------------------------------------------
# get_service_ports:  Convenience function that scans the existing squid3
#                     configuration file and returns a list of the existing
#                     ports being used.  This is necessary to know which ports
#                     to open and close when exposing/unexposing a service
#------------------------------------------------------------------------------
def get_service_ports(squid3_config_file="/etc/squid3/squid.conf"):
    squid3_config = load_squid3_config(squid3_config_file)
    if squid3_config is None:
        return(None)
    return(re.findall("http_port ([0-9]+)", squid3_config))


#------------------------------------------------------------------------------
# open_port:  Convenience function to open a port in juju to
#             expose a service
#------------------------------------------------------------------------------
def open_port(port=None, protocol="TCP"):
    if port is None:
        return(None)
    return(subprocess.call(['/usr/bin/open-port', "%d/%s" %
                            (int(port), protocol)]))


#------------------------------------------------------------------------------
# close_port:  Convenience function to close a port in juju to
#              unexpose a service
#------------------------------------------------------------------------------
def close_port(port=None, protocol="TCP"):
    if port is None:
        return(None)
    return(subprocess.call(['/usr/bin/close-port', "%d/%s" %
                            (int(port), protocol)]))


#------------------------------------------------------------------------------
# update_service_ports:  Convenience function that evaluate the old and new
#                        service ports to decide which ports need to be
#                        opened and which to close
#------------------------------------------------------------------------------
def update_service_ports(old_service_ports=None, new_service_ports=None):
    if old_service_ports is None or new_service_ports is None:
        return(None)
    for port in old_service_ports:
        if port not in new_service_ports:
            close_port(port)
    for port in new_service_ports:
        if port not in old_service_ports:
            open_port(port)


#------------------------------------------------------------------------------
# pwgen:  Generates a random password
#         pwd_length:  Defines the length of the password to generate
#                      default: 20
#------------------------------------------------------------------------------
def pwgen(pwd_length=20):
    alphanumeric_chars = [l for l in (string.letters + string.digits)
                          if l not in 'Iil0oO1']
    random_chars = [random.choice(alphanumeric_chars)
                    for i in range(pwd_length)]
    return(''.join(random_chars))


#------------------------------------------------------------------------------
# construct_squid3_config:  Convenience function to write squid.conf
#------------------------------------------------------------------------------
def construct_squid3_config():
    config_data = config_get()
    relations = relation_get_all()
    if config_data['refresh_patterns']:
        ## Try originally supported JSON formatted config
        try:
            refresh_patterns = json.loads(config_data['refresh_patterns'])
        ## else use YAML (current):
        except ValueError:
            refresh_patterns = yaml.load(config_data['refresh_patterns'])
    else:
        refresh_patterns = {}
    if config_data['auth_list']:
        auth_list = yaml.load(config_data['auth_list'])
    else:
        auth_list = {}

    config_data['cache_l1'] = int(math.ceil(math.sqrt(
        int(config_data['cache_size_mb']) * 1024 / (16 *
        int(config_data['target_objs_per_dir']) * int(config_data['avg_obj_size_kb'])))))
    config_data['cache_l2'] = config_data['cache_l1'] * 16

    with open(default_squid3_config, 'w') as squid3_config:
        templ_vars = {
            'config': config_data,
            'relations': relations,
            'refresh_patterns': refresh_patterns,
            'auth_list': auth_list,
        }
        squid3_config.write(utils.render_template('main_config.template',
                                                  templ_vars))


#------------------------------------------------------------------------------
# service_squid3:  Convenience function to start/stop/restart/reload
#                   the squid3 service
#------------------------------------------------------------------------------
def service_squid3(action=None, squid3_config=default_squid3_config):
    if action is None or squid3_config is None:
        return(None)
    elif action == "check":
        retVal = subprocess.call(['/usr/sbin/squid3', '-f', squid3_config, '-k', 'parse'])
        if retVal == 1:
            return(False)
        elif retVal == 0:
            return(True)
        else:
            return(False)
    elif action == 'status':
        status = subprocess.check_output(['status', 'squid3'])
        if re.search('running', status) is not None:
            return(True)
        else:
            return(False)
    elif action in ('start', 'stop', 'reload', 'restart'):
        retVal = subprocess.call([action, 'squid3'])
        if retVal == 0:
            return(True)
        else:
            return(False)


def update_nrpe_checks():
    config_data = config_get()
    try:
        nagios_uid = pwd.getpwnam('nagios').pw_uid
        nagios_gid = grp.getgrnam('nagios').gr_gid
    except:
        utils.juju_log('FATAL', "Nagios user not setup, exiting")
        return
    utils.install_unattended('libwww-perl')
    shutil.copy2('%s/files/nrpe-external-master/check_squid' % (os.environ['CHARM_DIR']), '/usr/local/lib/nagios/plugins/')
    unit_name = os.environ['JUJU_UNIT_NAME'].replace('/', '-')
    nrpe_check_file = '/etc/nagios/nrpe.d/check_squidfp.cfg'
    nagios_hostname = "%s-%s-%s" % (config_data['nagios_context'], config_data['nagios_service_type'], unit_name)
    nagios_logdir = '/var/log/nagios'
    nagios_exportdir = '/var/lib/nagios/export'
    nrpe_service_file = '/var/lib/nagios/export/service__%s_check_squidfp.cfg' % (nagios_hostname)
    if not os.path.exists(nagios_logdir):
        os.mkdir(nagios_logdir)
        os.chown(nagios_logdir, nagios_uid, nagios_gid)
    if not os.path.exists(nagios_exportdir):
        utils.juju_log('FATAL', 'Exiting as %s is not accessible' % (nagios_exportdir))
        return
    for f in os.listdir(nagios_exportdir):
        if re.search('.*check_squidfp.cfg', f):
            os.remove(os.path.join(nagios_exportdir, f))
    from jinja2 import Environment, FileSystemLoader
    template_env = Environment(
        loader=FileSystemLoader(os.path.join(os.environ['CHARM_DIR'], 'templates')))
    templ_vars = {
        'nagios_hostname': nagios_hostname,
        'nagios_servicegroup': config_data['nagios_context'],
    }
    template = template_env.get_template('nrpe_service.template').render(templ_vars)
    with open(nrpe_service_file, 'w') as nrpe_service_config:
        nrpe_service_config.write(str(template))
    with open(nrpe_check_file, 'w') as nrpe_check_config:
        nrpe_check_config.write("# check squidfp\n")
        nrpe_check_config.write("command[check_squidfp]=/usr/local/lib/nagios/plugins/check_squid %s - - 127.0.0.1 %s - - 200\n" % (config_data['nagios_check_url'], get_service_ports()[0]))
    if os.path.isfile('/etc/init.d/nagios-nrpe-server'):
        subprocess.call(['service', 'nagios-nrpe-server', 'reload'])


###############################################################################
# Hook functions
###############################################################################
def install_hook():
    for f in glob.glob('exec.d/*/charm-pre-install'):
        if os.path.isfile(f) and os.access(f, os.X_OK):
            subprocess.check_call(['sh', '-c', f])
    if not os.path.exists(default_squid3_config_dir):
        os.mkdir(default_squid3_config_dir, 0600)
    if not os.path.exists(default_squid3_config_cache_dir):
        os.mkdir(default_squid3_config_cache_dir, 0600)
    shutil.copy2('%s/files/default.squid3' % (os.environ['CHARM_DIR']), '/etc/default/squid3')
    return (utils.install_unattended('squid3', 'python-jinja2'))


def config_changed():
    current_service_ports = get_service_ports()
    construct_squid3_config()
    update_nrpe_checks()

    if service_squid3("check"):
        updated_service_ports = get_service_ports()
        update_service_ports(current_service_ports, updated_service_ports)
        service_squid3("reload")
    else:
        sys.exit(1)


def start_hook():
    if service_squid3("status"):
        return(service_squid3("restart"))
    else:
        return(service_squid3("start"))


def stop_hook():
    if service_squid3("status"):
        return(service_squid3("stop"))


def proxy_interface(hook_name=None):
    if hook_name is None:
        return(None)
    if hook_name in ["joined", "changed", "broken", "departed"]:
        # we'll only advertize one port, even if we listen on multiple
        subprocess.call(['relation-set', 'port=%s' % get_service_ports()[0]])
        config_changed()


###############################################################################
# Main section
###############################################################################
def main():
    if hook_name == "install":
        install_hook()
    elif hook_name == "config-changed":
        config_changed()
    elif hook_name == "start":
        start_hook()
    elif hook_name == "stop":
        stop_hook()

    elif hook_name == "cached-website-relation-joined":
        proxy_interface("joined")
    elif hook_name == "cached-website-relation-changed":
        proxy_interface("changed")
    elif hook_name == "cached-website-relation-broken":
        proxy_interface("broken")
    elif hook_name == "cached-website-relation-departed":
        proxy_interface("departed")

    elif hook_name == "nrpe-external-master-relation-changed":
        update_nrpe_checks()

    elif hook_name == "env-dump":
        print relation_get_all()
    else:
        print "Unknown hook"
        sys.exit(1)

if __name__ == '__main__':
    main()
