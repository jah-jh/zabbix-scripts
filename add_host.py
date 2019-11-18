#!/usr/bin/env python3
import os
import sys
from pyzabbix.api import ZabbixAPI
import boto3
import subprocess as sp

'''
Zabbix API library: 
                pip3 install py-zabbix
                https://github.com/adubkov/py-zabbix
Zabbix API Docs: https://www.zabbix.com/documentation/4.0/manual/api
'''


try:
    host_to_add = sys.argv[1]
except IndexError as e:
    print("Host is not specified\nUsage: " + sys.argv[0] + " <hostname>")
    exit(1)

host_ping_status, result = sp.getstatusoutput("ping -c3" + host_to_add)
if host_ping_status == 0: 
    pass
else:
    print("Warning!!!\nHost {} will be added but is not reachable".format(host_to_add))


username = "zabbix_admin"
hosts_list = []


def get_pass_from_sm(username):
    aws_session = boto3.session.Session(profile_name='strln')

    secretManager = aws_session.client(service_name='secretsmanager',
                                       region_name='eu-central-1')
    req_user_pass = secretManager.get_secret_value(SecretId='service_creds/' +
                                                   username)["SecretString"]

    user_pass = req_user_pass.replace("{",
                                      "").replace("}",
                                                  "").replace('"',
                                                              "").split(":")[1]
    return (user_pass)


def main():
    zabbix_conn = ZabbixAPI(url="http://librenms.bm.compute.strln.net/zabbix",
                            user=username,
                            password=get_pass_from_sm(username))

    for host in zabbix_conn.host.get():
        hosts_list.append(host["host"])
    if host_to_add in hosts_list:
        print("Host {} exists".format(host_to_add))
    else:
        zabbix_conn.host.create(host=host_to_add,
                                name=host_to_add,
                                status=0, #Host status - Enabled
                                interfaces=[{
                                    'interfaceid': '2', #ID of the interface.
                                    'main': '1', #Whether the interface is used as default on the host. Only one interface of some type can be set as default on a host. 
                                    'type': '2', #Interface type. 2 - SNMP
                                    'useip': '0', #Whether the connection should be made via IP. 0 - connect using host DNS name; 
                                    'ip': '', #IP address used by the interface. Can be empty if the connection is made via DNS.
                                    'dns': host_to_add, #DNS host address
                                    'port': '161', #SNMP port
                                    'bulk': '1' #Whether to use bulk SNMP requests. 
                                }],
                                groups=[{
                                    "groupid": "15" #UCS group
                                }],
                                templates=[{
                                    "templateid": "10278" #Template Module Interfaces Simple SNMPv3
                                }, {
                                    "templateid": "10280" #Template UCS SNMPv3 Vethernet interfaces
                                }, {
                                    "templateid": "10389" #Template Module Interfaces Error SNMPv3
                                }])
        print("Host {} is added".format(host_to_add))

        

    zabbix_conn.user.logout()


if __name__ == '__main__':
    main()
