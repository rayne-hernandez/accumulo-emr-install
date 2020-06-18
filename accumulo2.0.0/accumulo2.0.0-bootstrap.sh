#!/bin/bash
# Output commands to STDOUT, and exit if failure
set -x -e
# Copy install script from S3
aws s3 cp s3://kountable2.0/accumulo/emr-install/accumulo2.0.0-install.sh /home/hadoop/
aws s3 cp s3://kountable2.0/accumulo/emr-install/presto0.225-install.sh /home/hadoop/

# Set Crontab to try install script every 2 minutes
sudo sh -c "echo 'SHELL=/bin/bash' > /etc/crontab"
sudo sh -c "echo 'PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/aws/bin' >> /etc/crontab"
sudo sh -c "echo '' >> /etc/crontab"
sudo sh -c "echo '*/2 * * * * hadoop source /home/hadoop/.bash_profile >> /home/hadoop/accumulo-install.log 2>&1; \
sh /home/hadoop/accumulo2.0.0-install.sh >> /home/hadoop/accumulo-install.log 2>&1; \
sh /home/hadoop/presto0.225-install.sh >> /home/hadoop/presto-install.log 2>&1' >> /etc/crontab"
