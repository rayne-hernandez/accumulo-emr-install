#!/bin/bash
# Output commands to STDOUT, and exit if failure
set -x -e
# Copy install scripts from S3
aws s3 cp s3://kountable2.0/dev/emr/accumulo-presto/bootstrap/accumulo1.9.3-install.sh /home/hadoop/
aws s3 cp s3://kountable2.0/dev/emr/accumulo-presto/bootstrap/presto0.230-install.sh /home/hadoop/
# Copy backup script from S3
aws s3 cp s3://kountable2.0/dev/emr/accumulo-presto/bootstrap/accumulo-backup.sh /home/hadoop/
# Copy crontab config from S3
sudo sh -c "aws s3 cp s3://kountable2.0/dev/emr/accumulo-presto/bootstrap/crontab /etc/crontab"
# Copy Accumulo logrotate config from S3
sudo sh -c "aws s3 cp s3://kountable2.0/dev/emr/accumulo-presto/bootstrap/accumulo-logrotate /etc/logrotate.d/"
