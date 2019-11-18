#!/bin/bash

CURDATE=$(date +%F)
DIR="/tmp/zabbix-backup/$CURDATE"
SCRIPT_DIR="/usr/local/scripts/zabbix-bak"

$SCRIPT_DIR/zabbix-mysql-bak.sh -z /usr/local/etc/zabbix_server.conf -u root -d zabbix -o $DIR -0

mysqldump -u root mysql user > $DIR/mysql_user_table.sql

cp /usr/local/etc/zabbix_server.conf $DIR


tar -czvf $DIR/$CURDATE.tar.gz -C $DIR .

aws s3 cp $DIR/$CURDATE.tar.gz s3://cie-zabbix-config-backup/

rm -r $DIR
