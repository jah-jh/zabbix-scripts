#!/bin/bash


CURDATE=$(date +%F)

echo "START PART $CURDATE" >>/usr/local/scripts/part_manage.log


mysql -u root -e 'call zabbix.create_next_partitions("zabbix");' zabbix >> /usr/local/scripts/part_manage.log
mysql -u root -e 'call zabbix.drop_partitions("zabbix");' zabbix

echo "___END PART___" >> /usr/local/scripts/part_manage.log

