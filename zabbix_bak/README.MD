**Usage:**


*full_zabbix_bak.sh* - 
1. create temp directory for backup, copy zabbix server conf file. 
2. Runs *zabbix-mysql-bak.sh* to create mysql dump (only procedures, users,  hosts, items and database structure are backuped).
3. Creates tar.gz archive
4. Downloads backup to s3 bucket (cie-zabbix-config-backup). AWS session is esteblished for user *autoprov*
5. Deletes temp folder with current backup

**Restore:**
1. If needed copy zabbix conf file to (in current case)  /usr/local/etc/zabbix_server.conf
2. Restore mysql database:
```
 mysql -u <user> -p zabbix < <name_of_sql_dump.sql>
 ```
 If this is fresh install (for example new OS or new MySQL instance) restore MySQL users
 ```
 mysql -u root mysql < mysql_user_table.sql
 ```
3. Set job in cron to manage partitions (/etc/cron.d/zabbix)
```
05  00    * * *  root    /usr/local/scripts/manage_partitions.sh
```

In our case, for purpose of efficiency, mysql partitioning is using.
After redeploy check if needed partitions are existed by run for each of tables: history, history_uint, history_str, history_text, history_log, trends, trends_uint:
```

```
For example today 2019-10-29 and you should see something like that:
```
history | CREATE TABLE `history` (
  `itemid` bigint(20) unsigned NOT NULL,
  `clock` int(11) NOT NULL DEFAULT '0',
  `value` double(16,4) NOT NULL DEFAULT '0.0000',
  `ns` int(11) NOT NULL DEFAULT '0',
  KEY `history_1` (`itemid`,`clock`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin
/*!50100 PARTITION BY RANGE ( clock)
(PARTITION p2019_10_22 VALUES LESS THAN (1571769000) ENGINE = InnoDB,
 PARTITION p2019_10_23 VALUES LESS THAN (1571855400) ENGINE = InnoDB,
 PARTITION p2019_10_24 VALUES LESS THAN (1571941800) ENGINE = InnoDB,
 PARTITION p2019_10_25 VALUES LESS THAN (1572028200) ENGINE = InnoDB,
 PARTITION p2019_10_26 VALUES LESS THAN (1572114600) ENGINE = InnoDB,
 PARTITION p2019_10_27 VALUES LESS THAN (1572201000) ENGINE = InnoDB,
 PARTITION p2019_10_28 VALUES LESS THAN (1572287400) ENGINE = InnoDB,
 PARTITION p2019_10_29 VALUES LESS THAN (1572480000) ENGINE = InnoDB) */ |
 ```

 There are partitions for today, so all fine. Next partitions would be created manage_partitions.sh script

If there are not partitions for current day (it could happen if backup was restored in several days  after  crash) try to run:


```
mysql -u root -e 'call zabbix.create_next_partitions("zabbix");' zabbix
```

To delete old partitions
```
mysql -u root -e 'call zabbix.drop_partitions("zabbix");' zabbix
```














