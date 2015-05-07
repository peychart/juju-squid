
#
# Copyright 2012 Canonical Ltd.
#
# Authors:
#  James Page <james.page@ubuntu.com>
#  Paul Collins <paul.collins@canonical.com>
#

import os
import subprocess
import socket
import sys


def do_hooks(hooks):
    hook = os.path.basename(sys.argv[0])

    try:
        hooks[hook]()
    except KeyError:
        juju_log('INFO',
                 "This charm doesn't know how to handle '{}'.".format(hook))


def install(*pkgs):
    apt_locked = True
    while apt_locked:
        cmd = [ 'lsof', '/var/lib/dpkg/lock' ]
        try:
            subprocess.check_call(cmd)
            apt_locked = True
        except:
            apt_locked = False
        if not apt_locked:
            cmd = [
                'apt-get',
                '-y',
                'install'
                  ]
            for pkg in pkgs:
                cmd.append(pkg)
                subprocess.check_call(cmd)


TEMPLATES_DIR = 'templates'

try:
    import jinja2
except ImportError:
    install('python-jinja2')
    import jinja2


def render_template(template_name, context, template_dir=TEMPLATES_DIR):
    templates = jinja2.Environment(
                    loader=jinja2.FileSystemLoader(template_dir)
                    )
    template = templates.get_template(template_name)
    return template.render(context)


def install_unattended(*pkgs):
    """Use this only if you understand how it behaves with your packages!

    For example, you may need to pre-seed debconf with appropriate
    values for the installed package to operate correctly."""

    cmd = [
        'env',
        'DEBIAN_FRONTEND=noninteractive',
        'apt-get',
        '-y',
        '-odpkg::options::=--force-confdef',  # always take the default
        '-odpkg::options::=--force-confold',  # set the default to "N"
        'install'
          ]
    for pkg in pkgs:
        cmd.append(pkg)
    subprocess.check_call(cmd)


def configure_source():
    source = config_get('source')
    if (source.startswith('ppa:') or
        source.startswith('cloud:')):
        cmd = [
            'add-apt-repository',
            source
            ]
        subprocess.check_call(cmd)
    if source.startswith('http:'):
        with open('/etc/apt/sources.list.d/ceph.list', 'w') as apt:
            apt.write("deb " + source + "\n")
        key = config_get('key')
        if key != "":
            cmd = [
                'apt-key',
                'import',
                key
                ]
            subprocess.check_call(cmd)
    cmd = [
        'apt-get',
        'update'
        ]
    subprocess.check_call(cmd)

# Protocols
TCP = 'TCP'
UDP = 'UDP'


def expose(port, protocol='TCP'):
    cmd = [
        'open-port',
        '{}/{}'.format(port, protocol)
        ]
    subprocess.check_call(cmd)


def juju_log(severity, message):
    cmd = [
        'juju-log',
        '--log-level', severity,
        message
        ]
    subprocess.check_call(cmd)


def relation_ids(relation):
    cmd = [
        'relation-ids',
        relation
        ]
    return subprocess.check_output(cmd).split()  # IGNORE:E1103


def relation_list(rid):
    cmd = [
        'relation-list',
        '-r', rid,
        ]
    return subprocess.check_output(cmd).split()  # IGNORE:E1103


def relation_get(attribute, unit=None, rid=None):
    cmd = [
        'relation-get',
        ]
    if rid:
        cmd.append('-r')
        cmd.append(rid)
    cmd.append(attribute)
    if unit:
        cmd.append(unit)
    return subprocess.check_output(cmd).strip()  # IGNORE:E1103


def relation_set(**kwargs):
    cmd = [
        'relation-set'
        ]
    args = []
    for k, v in kwargs.items():
        if k == 'rid':
            cmd.append('-r')
            cmd.append(v)
        else:
            args.append('{}={}'.format(k, v))
    cmd += args
    subprocess.check_call(cmd)


def unit_get(attribute):
    cmd = [
        'unit-get',
        attribute
        ]
    return subprocess.check_output(cmd).strip()  # IGNORE:E1103


def config_get(attribute):
    cmd = [
        'config-get',
        attribute
        ]
    return subprocess.check_output(cmd).strip()  # IGNORE:E1103


def get_unit_hostname():
    return socket.gethostname()


def get_host_ip(hostname):
    if not hostname:
        hostname=unit_get('private-address')
    cmd = [
        'dig',
        '+short',
        hostname
        ]
    return subprocess.check_output(cmd).strip()  # IGNORE:E1103


def do_basenode():
    juju_log('INFO', 'Let there be basenode.')
    try:
        subprocess.check_call(['sh', '-c',
                               'cd basenode && python setup.py install'])
    except subprocess.CalledProcessError:
            juju_log('ERROR', 'Installation of basenode failed!')
            raise
    from basenode import basenode_init
    basenode_init()
    juju_log('INFO', 'Done with basenode.')


def try_basenode():
    try:
        shall_we_dance = int(config_get('basenode'))
        if shall_we_dance:
            do_basenode()
    except ValueError:
        juju_log('ERROR',
                 'Config setting "basenode" is not an integer, forging ahead.')


def debconf_set_selections(selections):
    command = ['debconf-set-selections']
    p = subprocess.Popen(command, close_fds=True, stdin=subprocess.PIPE)

    for selection in selections:
        p.stdin.write(selection + "\n")
    p.stdin.close()

    if p.wait() != 0:
        raise subprocess.CalledProcessError(
            cmd=command, returncode=p.returncode)
