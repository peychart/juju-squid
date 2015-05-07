# Overview

Squid is a high-performance proxy caching server for web clients, supporting
FTP, gopher, and HTTP data objects.
 
Squid version 3 is a major rewrite of Squid in C++ and introduces a number of
new features including ICAP and ESI support.

http://www.squid-cache.org/

# Usage

## General

This charm provides squid in a forward proxy setup. 

http://en.wikipedia.org/wiki/Proxy_server#Forward_proxies

The most common scenario is having a service that you do not want to grant
direct Internet access use the forward proxy. It can both filter outgoing
http requests and cache frequent requests to the same targets.

Another scenario is providing a proxy server for an office environment.

The charm can be deployed in a single or multi-unit setup.

To deploy a single unit:

    juju deploy squid-forwardproxy

To add more units:

    juju add-unit squid-forwardproxy 

Once deployed, you can ssh into the deployed service:

    juju ssh <unit>

To list running units:

    juju status

To start monitoring Squid using Nagios:

    juju deploy nrpe-external-master
    juju add-relation squid-forwardproxy nrpe-external-master



This charm requires the following relation settings from clients:

    ip: service ip address
    port: service port
    sitenames: space-delimited list of sites to whitelist

The options that can be configured in config.yaml should be self-explanatory. If not, please file a bug against this charm.

## Monitoring

This charm provides relations that support monitoring via Nagios using nrpe_external_master as a subordinate charm.
