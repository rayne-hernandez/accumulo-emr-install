#!/bin/bash
# Output commands to STDOUT, and exits if failure
set -x -e

# If Accumulo installation does not exist and Zookeeper installation exists, then proceed with Accumulo installation
if [ ! -d "/home/hadoop/accumulo-2.0.0" ] && [ -d "/usr/lib/zookeeper" ]
then
    # Wait for Zookeeper to finish installing
    sleep 15
    cd /home/hadoop/

    # Change swappiness and IPV6 disable
    echo -e "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee --append /etc/sysctl.conf
    echo -e "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee --append /etc/sysctl.conf
    echo -e "net.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee --append /etc/sysctl.conf
    echo -e "vm.swappiness = 10" | sudo tee --append /etc/sysctl.conf
    sudo sysctl -w vm.swappiness=10
  
    # Change open file limits
    echo -e "" | sudo tee --append /etc/security/limits.conf
    echo -e "*\t\tsoft\tnofile\t65536" | sudo tee --append /etc/security/limits.conf
    echo -e "*\t\thard\tnofile\t65536" | sudo tee --append /etc/security/limits.conf
    
    # Load environment variables
    MASTER_INSTANCE_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.masterInstanceId' | tr -d '"')
    CLUSTER_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.jobFlowId' | tr -d '"')
    MASTER_IP_ADDRESS=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.Ec2InstanceId == "'$MASTER_INSTANCE_ID'") | .PrivateIpAddress' | tr -d '"')
    CORE_INSTANCE_GROUP_ID=$(aws emr describe-cluster --cluster-id ${CLUSTER_ID} | jq '.Cluster.InstanceGroups[] | select(.Name | contains("Core")) | .Id' | tr -d '"')
    CORE_IP_ADDRESSES=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$CORE_INSTANCE_GROUP_ID'") | .PrivateIpAddress' | tr -d '"')
    ZOOKEEPER_HOST=${MASTER_IP_ADDRESS}
    KEY_PAIR_NAME="kountable-dev-2"
    ACCUMULO_DOWNLOAD="http://mirror.olnevhost.net/pub/apache/accumulo/2.0.0/accumulo-2.0.0-bin.tar.gz"

    # Determines if all the Core nodes in the cluster have initialized Accumulo
    core_nodes_initialized() {
        for CORE_IP_ADDRESS in $(echo "$CORE_IP_ADDRESSES")
        do
            if ! ssh $CORE_IP_ADDRESS stat /home/hadoop/accumulo-2.0.0/conf/tracers &> /dev/null
            then
                return 1
            fi
        done
        return 0
    }
    
    # Get Accumulo ditribution
    wget http://mirror.olnevhost.net/pub/apache/accumulo/2.0.0/accumulo-2.0.0-bin.tar.gz
    tar xzf accumulo-2.0.0-bin.tar.gz 
    
    # Add accumulo binaries to PATH
    export PATH=$PATH:"/home/hadoop/accumulo-2.0.0/bin/"
    # Add Java JDK to JAVA_HOME
    export JAVA_HOME="/usr/lib/jvm/java-openjdk"

    cd accumulo-2.0.0

    # Build Accumulo
    accumulo-util build-native
    
    # Configure `accumulo.properties`
    sed -i "s;instance.volumes=hdfs://localhost:8020/accumulo;instance.volumes=hdfs://${MASTER_IP_ADDRESS}:8020/accumulo;g" conf/accumulo.properties
    sed -i "s;instance.zookeeper.host=localhost:2181;instance.zookeeper.host=${ZOOKEEPER_HOST}:2181;g" conf/accumulo.properties
    sed -i "s;instance.secret=DEFAULT;instance.secret=J2vgaxF4VVjdP6FqArAQbZrJ;g" conf/accumulo.properties
    
    # Configure `accumulo-env.sh`
    sed -i 's;export HADOOP_HOME="${HADOOP_HOME:-/path/to/hadoop}";export HADOOP_HOME="${HADOOP_HOME:-/usr/lib/hadoop}";g' conf/accumulo-env.sh
    sed -i 's;export ZOOKEEPER_HOME="${ZOOKEEPER_HOME:-/path/to/zookeeper}";export ZOOKEEPER_HOME="${ZOOKEEPER_HOME:-/usr/lib/zookeeper}";g' conf/accumulo-env.sh
    sed -i 's;CLASSPATH="${CLASSPATH}:${lib}/\*:${HADOOP_CONF_DIR}:${ZOOKEEPER_HOME}/\*:${HADOOP_HOME}/share/hadoop/client/\*";CLASSPATH="${CLASSPATH}:${lib}/\*:${lib}/ext/\*:${HADOOP_CONF_DIR}:${ZOOKEEPER_HOME}/\*:${HADOOP_HOME}/client/\*";g' conf/accumulo-env.sh 
    
    # Configure `accumulo-client.properties`
    sed -i "s;instance.name=;instance.name=kountable-accumulo;g" conf/accumulo-client.properties 
    sed -i "s;instance.zookeepers=localhost:2181;instance.zookeepers=${ZOOKEEPER_HOST}:2181;g" conf/accumulo-client.properties 
    sed -i "s;auth.principal=;auth.principal=root;g" conf/accumulo-client.properties
    sed -i "s;auth.token=;auth.token=secret;g" conf/accumulo-client.properties
    
    # Create clustering configuation files
    accumulo-cluster create-config
    
    # Configure Accumulo clustering
    echo $MASTER_IP_ADDRESS > conf/masters
    echo $MASTER_IP_ADDRESS > conf/gc
    echo $MASTER_IP_ADDRESS > conf/monitor
    echo "$CORE_IP_ADDRESSES" > conf/tservers
    echo "" > conf/tracers
    
    # If this is the Master node and Core nodes finished bootrapping, then initialize Accumulo, setup SSH, and copy Hadoop client JARs to Core nodes
    if grep isMaster /mnt/var/lib/info/instance.json | grep true
    then 
        # Grab EMR cluster private key
        aws s3 cp s3://kountable2.0/accumulo/emr-install/${KEY_PAIR_NAME}.pem /home/hadoop/
        chmod 700 /home/hadoop/${KEY_PAIR_NAME}.pem
        mv /home/hadoop/${KEY_PAIR_NAME}.pem /home/hadoop/.ssh/${KEY_PAIR_NAME}.pem
    
        # Setup SSH config
        for CORE_IP_ADDRESS in $(echo "$CORE_IP_ADDRESSES")
        do
            echo "Host $CORE_IP_ADDRESS" >> /home/hadoop/.ssh/config
            echo "  HostName $CORE_IP_ADDRESS" >> /home/hadoop/.ssh/config
            echo "  IdentityFile ~/.ssh/${KEY_PAIR_NAME}.pem" >> /home/hadoop/.ssh/config
            echo "  UserKnownHostsFile /dev/null" >> /home/hadoop/.ssh/config
            echo "  StrictHostKeyChecking no" >> /home/hadoop/.ssh/config
            echo "  User hadoop" >> /home/hadoop/.ssh/config
            echo "" >> /home/hadoop/.ssh/config
        done
        chmod 700 /home/hadoop/.ssh/config

        while true
        do
            # wait for Core nodes to finish bootstrapping
            sleep 15

            if core_nodes_initialized
            then
                # Initialize Accumulo
                accumulo init <<< 'kountable-accumulo
secret
secret'
                # Copy Hadoop client JARS to core nodes
                for CORE_IP_ADDRESS in $(echo "$CORE_IP_ADDRESSES")
                do
                    scp -r /usr/lib/hadoop/client $CORE_IP_ADDRESS:/home/hadoop/client
                    ssh $CORE_IP_ADDRESS "sudo mv /home/hadoop/client/ /usr/lib/hadoop/client/"
                done 
                # Start Accumulo cluster
                accumulo-cluster start
                break
            fi
        done
    fi
fi
