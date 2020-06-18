#!/bin/bash
# Output commands to STDOUT, and exit if failure
set -x -e

# Copy install script from S3
aws s3 cp s3://kountable2.0/accumulo/emr-install/accumulo1.9.3-install.sh /home/hadoop/
# Copy backup script from S3
aws s3 cp s3://kountable2.0/accumulo/emr-install/accumulo-backup.sh /home/hadoop/

# Setup crontab boilerplate
sudo sh -c "echo 'SHELL=/bin/bash' > /etc/crontab"
sudo sh -c "echo 'PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/aws/bin' >> /etc/crontab"
sudo sh -c "echo '' >> /etc/crontab"
# Set crontab to try install script every two minutes. Script will exit automatically if already installed
sudo sh -c "echo '*/2 * * * * hadoop source /home/hadoop/.bash_profile >> /home/hadoop/accumulo-install.log 2>&1; \
sh /home/hadoop/accumulo1.9.3-install.sh >> /home/hadoop/accumulo-install.log 2>&1' >> /etc/crontab"
# Set crontab to run Accumulo backup script every 6 hours
sudo sh -c "echo '* 6 * * * hadoop source /home/hadoop/.bash_profile >> /home/hadoop/accumulo-backup.log 2>&1; \
sh /home/hadoop/accumulo-backup.sh >> /home/hadoop/accumulo-backup.log 2>&1' >> /etc/crontab"
