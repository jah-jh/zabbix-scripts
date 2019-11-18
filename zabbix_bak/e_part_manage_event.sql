DELIMITER $$
 
USE `zabbix`$$

CREATE EVENT IF NOT EXISTS `e_part_manage`
       ON SCHEDULE EVERY 1 DAY
       STARTS '2019-10-30 23:00:00'
       ON COMPLETION PRESERVE
       ENABLE
       COMMENT 'Creating and dropping partitions'
       DO BEGIN
            CALL zabbix.drop_partitions('zabbix');
            CALL zabbix.create_next_partitions('zabbix');
       END$$
DELIMITER ;
