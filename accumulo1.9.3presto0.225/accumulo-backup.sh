#!/bin/bash
set -x -e

if grep isMaster /mnt/var/lib/info/instance.json | grep true
then
    DATETIME=$(date +%Y_%m_%d_%H)
    #backup records table
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "clonetable records ${DATETIME}_records_backup"
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "offline ${DATETIME}_records_backup"
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "exporttable -t ${DATETIME}_records_backup /tmp/${DATETIME}_records_backup"
    #hadoop distcp -f /tmp/${DATETIME}_records_backup/distcp.txt s3n://kountable-emr-backups/${DATETIME}_backup/records
    s3-dist-cp --src=/tmp/${DATETIME}_records_backup/distcp.txt --dest=s3://kountable-emr-backups/${DATETIME}_backup/records
    hadoop fs -rm -R /tmp/${DATETIME}_records_backup
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "deletetable -f ${DATETIME}_records_backup"

    #backup project_feed table
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "clonetable project_feed ${DATETIME}_project_feed_backup"
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "offline ${DATETIME}_project_feed_backup"
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "exporttable -t ${DATETIME}_project_feed_backup /tmp/${DATETIME}_project_feed_backup"
    #hadoop distcp -f /tmp/${DATETIME}_project_feed_backup/distcp.txt s3n://kountable-emr-backups/${DATETIME}_backup/project_feed
    s3-dist-cp --src=/tmp/${DATETIME}_project_feed_backup/distcp.txt --dest=s3://kountable-emr-backups/${DATETIME}_backup/project_feed
    hadoop fs -rm -R /tmp/${DATETIME}_project_feed_backup
    ~/accumulo-1.9.3/bin/accumulo shell -u root -p secret -e "deletetable -f ${DATETIME}_project_feed_backup"
fi
