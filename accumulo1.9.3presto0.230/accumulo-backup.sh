#!/bin/bash
set -x -e

if grep isMaster /mnt/var/lib/info/instance.json | grep true
then
    DATETIME=$(date +%Y_%m_%d_%H)
    #backup records table
    echo -ne '\n\n\n\n\n\n' | ~/accumulo/bin/accumulo shell -u root -p secret -e "tables" | while read TABLE
    do
        if [[ $TABLE == *"202"* ]] || [[ $TABLE == *"----"* ]] || [[ $TABLE == *"accumulo."* ]]
        then
            continue
        fi
        {
            hadoop fs -rm -R /tmp/${DATETIME}_${TABLE}_backup
            ~/accumulo/bin/accumulo shell -u root -p secret -e "deletetable -f ${DATETIME}_${TABLE}_backup"
        } || {
            echo ""
        }
        ~/accumulo/bin/accumulo shell -u root -p secret -e "clonetable $TABLE ${DATETIME}_${TABLE}_backup"
        ~/accumulo/bin/accumulo shell -u root -p secret -e "offline ${DATETIME}_${TABLE}_backup"
        ~/accumulo/bin/accumulo shell -u root -p secret -e "exporttable -t ${DATETIME}_${TABLE}_backup /tmp/${DATETIME}_${TABLE}_backup"
        s3-dist-cp --src=/tmp/${DATETIME}_${TABLE}_backup --dest=s3://kountable-emr-backups/${DATETIME}_backup/${TABLE}
        hadoop fs -rm -R /tmp/${DATETIME}_${TABLE}_backup
        ~/accumulo/bin/accumulo shell -u root -p secret -e "deletetable -f ${DATETIME}_${TABLE}_backup"
    done
fi
