#!/usr/bin/env python3

import boto3
from ucsmsdk.ucshandle import UcsHandle
from ucsmsdk.mometa.comm.CommSnmpUser import CommSnmpUser
from ucsmsdk.mometa.comm.CommSnmp import CommSnmp

aws_session = boto3.session.Session(profile_name='strln')

secretManager = aws_session.client(service_name='secretsmanager',
                                   region_name='eu-central-1')

req_snmp_pass = secretManager.get_secret_value(
    SecretId='service_creds/ucs_snmpv3_cred')["SecretString"]

req_user_pass = secretManager.get_secret_value(
    SecretId='ucs/users/rdeviate')["SecretString"]

snmpv3_pass = req_snmp_pass.replace("{",
                                    "").replace("}",
                                                "").replace('"',
                                                            "").split(":")[1]
user_pass = req_user_pass.replace("{",
                                  "").replace("}",
                                              "").replace('"',
                                                          "").split(":")[1]

ucs_list = []

for host in ucs_list:
    sysLocation = host.split(".")[2-3].upper()

    handle = UcsHandle(host, "rdeviate", user_pass)

    handle.login()

    mo_enable_snmp = CommSnmp(parent_mo_or_dn="sys/svc-ext",
                              admin_state="enabled",
                              sys_contact="cie-eng.compute-services@cisco.com",
                              sys_location=sysLocation)

    mo_user_snmp = CommSnmpUser(parent_mo_or_dn="sys/svc-ext/snmp-svc",
                                auth="sha",
                                name="cs-snmp",
                                privpwd=snmpv3_pass,
                                pwd=snmpv3_pass,
                                use_aes="yes")

    handle.add_mo(mo_enable_snmp, True)
    handle.add_mo(mo_user_snmp)

    handle.commit()
    handle.logout()
