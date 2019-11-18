**add_host.py** - add host to group UCS and attach two template:<br/>
Template UCS SNMPv3 Vethernet interfaces - for Vethernet traffic monitoring.<br/>
Template Module Interfaces Simple SNMPv3 - for Ethernet interfaces traffic and ethernet statistic.

**snmpv3_config.py**  - configure snmp on UCS

**zabbix_bak/** - scripts to create zabbix backup. Only mysql tables structure, host, items and zabbix server config file.
Cron job runs every Sunday.  More info in directory
