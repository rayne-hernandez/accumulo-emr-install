#!/bin/bash
# Output commands to STDOUT, and exits if failure
set -x -e

# If Accumulo installation does not exist and Zookeeper installation exists, then proceed with Accumulo installation
if [ ! -d "/home/hadoop/accumulo-1.9.3" ] && [ -d "/usr/lib/zookeeper" ]
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
    MASTER_IP_ADDRESS=$(cat /mnt/var/lib/info/job-flow.json | jq '.masterPrivateDnsName' | tr -d '"')
    CLUSTER_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.jobFlowId' | tr -d '"')
    MASTER_INSTANCE_GROUP_ID=$(aws emr describe-cluster --cluster-id ${CLUSTER_ID} | jq '.Cluster.InstanceGroups[] | select(.Name | contains("Master")) | .Id' | tr -d '"')
    MASTER_DNS_ADDRESS=$(echo $MASTER_IP_ADDRESS | sed 's/\./-/g' | sed 's/[^ ]* */ip-&.ext.d.us-west-2.kountable.com/g')
    #MASTER_DNS_ADDRESS=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$MASTER_INSTANCE_GROUP_ID'") | .PrivateDnsName' | tr -d '"')
    CORE_INSTANCE_GROUP_ID=$(aws emr describe-cluster --cluster-id ${CLUSTER_ID} | jq '.Cluster.InstanceGroups[] | select(.Name | contains("Core")) | .Id' | tr -d '"')
    CORE_IP_ADDRESSES=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$CORE_INSTANCE_GROUP_ID'") | .PrivateIpAddress' | tr -d '"')
    #CORE_DNS_ADDRESSES=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$CORE_INSTANCE_GROUP_ID'") | .PrivateDnsName' | tr -d '"')
    CORE_DNS_ADDRESSES=$(echo "$CORE_IP_ADDRESSES" | sed 's/\./-/g' | sed 's/[^ ]* */ip-&.ext.d.us-west-2.kountable.com/g')
    ZOOKEEPER_HOST=${MASTER_DNS_ADDRESS}
    KEY_PAIR_NAME="kountable-dev-2"
    ACCUMULO_DOWNLOAD="https://archive.apache.org/dist/accumulo/1.9.3/accumulo-1.9.3-bin.tar.gz"

    # Determines if all the Core nodes in the cluster have initialized Accumulo
    core_nodes_initialized() {
        for CORE_IP_ADDRESS in $(echo "$CORE_IP_ADDRESSES")
        do
            # Checks if Core node configuration is present
            if ! ssh $CORE_IP_ADDRESS stat /home/hadoop/accumulo/conf/tracers &> /dev/null
            then
                return 1
            fi
        done
        return 0
    }

    # Get Accumulo ditribution
    wget $ACCUMULO_DOWNLOAD 
    tar xzf accumulo-1.9.3-bin.tar.gz
    ln -s /home/hadoop/accumulo-1.9.3 /home/hadoop/accumulo

    # Add Java JDK to JAVA_HOME
    export JAVA_HOME="/usr/lib/jvm/java-openjdk"

    cd accumulo

    # Build native code
    bin/build_native_library.sh 

    # Create configuration files. This sets up the CLASSPATH. Very important
    bin/bootstrap_config.sh <<< '1
2
2'

    # Set instance secret key
    sed -i "s;<value>DEFAULT</value>;<value>J2vgaxF4VVjdP6FqArAQbZrJ</value>;g" conf/accumulo-site.xml
    # Set Zookeeper host
    sed -i "s;<value>localhost:2181</value>;<value>${ZOOKEEPER_HOST}:2181</value>;g" conf/accumulo-site.xml
    # Set HDFS location
    sed -i "s;<value></value>;<value>hdfs://${MASTER_DNS_ADDRESS}:8020/accumulo</value>;g" conf/accumulo-site.xml

    # Set HADOOP_PREFIX
    sed -i "s;export HADOOP_PREFIX=/path/to/hadoop;export HADOOP_PREFIX=/usr/lib/hadoop;g" conf/accumulo-env.sh
    # Set JAVA_HOME
    sed -i "s;export JAVA_HOME=/path/to/java;export JAVA_HOME=/usr/lib/jvm/java-openjdk;g" conf/accumulo-env.sh
    # Set ZOOKEEPER_HOME
    sed -i "s;export ZOOKEEPER_HOME=/path/to/zookeeper;export ZOOKEEPER_HOME=/usr/lib/zookeeper;g" conf/accumulo-env.sh

    # configure master process
    echo $MASTER_IP_ADDRESS > conf/masters
    # configure garbage collector process
    echo $MASTER_IP_ADDRESS > conf/gc
    # configure monitor process
    echo $MASTER_IP_ADDRESS > conf/monitor
    # configure slave processes
    echo "$CORE_IP_ADDRESSES" > conf/slaves
    # configure tracer processes
    echo $MASTER_IP_ADDRESS > conf/tracers

    # Grab EMR cluster private key
    aws s3 cp s3://kountable2.0/accumulo/emr-install/${KEY_PAIR_NAME}.pem /home/hadoop/
    chmod 700 /home/hadoop/${KEY_PAIR_NAME}.pem
    mv /home/hadoop/${KEY_PAIR_NAME}.pem /home/hadoop/.ssh/${KEY_PAIR_NAME}.pem

    # If this is the Master node and Core nodes finished bootrapping, then initialize Accumulo, setup SSH, and copy Hadoop client JARs to Core nodes
    if grep isMaster /mnt/var/lib/info/instance.json | grep true
    then 
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
                # Initializes Accumulo
                bin/accumulo init <<< 'kountable-accumulo
secret
secret'

                # start Accumulo cluster
                bin/start-all.sh

                # configure Thrift Proxy
                echo "useMockInstance=false" > conf/proxy.properties
                echo "useMiniAccumulo=false" >> conf/proxy.properties
                echo "protocolFactory=org.apache.thrift.protocol.TCompactProtocol\$Factory" >> conf/proxy.properties
                echo "tokenClass=org.apache.accumulo.core.client.security.tokens.PasswordToken" >> conf/proxy.properties
                echo "port=42424" >> conf/proxy.properties
                echo "maxFrameSize=16M" >> conf/proxy.properties
                echo "instance=kountable-accumulo" >> conf/proxy.properties
                echo "zookeepers=${ZOOKEEPER_HOST}:2181" >> conf/proxy.properties

                # start thrift proxy
                nohup bin/accumulo proxy -p conf/proxy.properties &
                break
            fi
        done
    else
        echo "Host $MASTER_IP_ADDRESS" >> /home/hadoop/.ssh/config
        echo "  HostName $MASTER_IP_ADDRESS" >> /home/hadoop/.ssh/config
        echo "  IdentityFile ~/.ssh/${KEY_PAIR_NAME}.pem" >> /home/hadoop/.ssh/config
        echo "  UserKnownHostsFile /dev/null" >> /home/hadoop/.ssh/config
        echo "  StrictHostKeyChecking no" >> /home/hadoop/.ssh/config
        echo "  User hadoop" >> /home/hadoop/.ssh/config
        echo "" >> /home/hadoop/.ssh/config

        chmod 700 /home/hadoop/.ssh/config
    fi
fi
