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
    MASTER_INSTANCE_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.masterInstanceId' | tr -d '"')
    CLUSTER_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.jobFlowId' | tr -d '"')
    MASTER_IP_ADDRESS=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.Ec2InstanceId == "'$MASTER_INSTANCE_ID'") | .PrivateIpAddress' | tr -d '"')
    ZOOKEEPER_HOST=${MASTER_IP_ADDRESS}
    KEY_PAIR_NAME="kountable-dev-2"
    ACCUMULO_DOWNLOAD="https://archive.apache.org/dist/accumulo/1.9.3/accumulo-1.9.3-bin.tar.gz"

    # Get Accumulo ditribution
    wget $ACCUMULO_DOWNLOAD 
    tar xzf accumulo-1.9.3-bin.tar.gz

    # Add accumulo binaries to PATH
    export PATH=$PATH:"/home/hadoop/accumulo-1.9.3/bin/"
    # Add Java JDK to JAVA_HOME
    export JAVA_HOME="/usr/lib/jvm/java-openjdk"

    cd accumulo-1.9.3

    # Build native code
    bin/build_native_library.sh 

    # Create configuration files
    bin/bootstrap_config.sh <<< '1
2
2'

    # Set instance secret key
    sed -i "s;<value>DEFAULT</value>;<value>J2vgaxF4VVjdP6FqArAQbZrJ</value>;g" conf/accumulo-site.xml
    # Set Zookeeper host
    sed -i "s;<value>localhost:2181</value>;<value>${ZOOKEEPER_HOST}:2181</value>;g" conf/accumulo-site.xml
    # Set HDFS location
    sed -i "s;<value></value>;<value>hdfs://${MASTER_IP_ADDRESS}:8020/accumulo</value>;g" conf/accumulo-site.xml

    # Set HADOOP_PREFIX
    sed -i "s;export HADOOP_PREFIX=/path/to/hadoop;export HADOOP_PREFIX=/usr/lib/hadoop;g" conf/accumulo-env.sh
    # Set JAVA_HOME
    sed -i "s;export JAVA_HOME=/path/to/java;export JAVA_HOME=/usr/lib/jvm/java-openjdk;g" conf/accumulo-env.sh
    # Set ZOOKEEPER_HOME
    sed -i "s;export ZOOKEEPER_HOME=/path/to/zookeeper;export ZOOKEEPER_HOME=/usr/lib/zookeeper;g" conf/accumulo-env.sh

    bin/accumulo init <<< 'kountable-accumulo
secret
secret'

    # configure master process
    echo $MASTER_IP_ADDRESS > conf/masters
    # configure garbage collector process
    echo $MASTER_IP_ADDRESS > conf/gc
    # configure monitor process
    echo $MASTER_IP_ADDRESS > conf/monitor
    # configure slave processes
    echo $MASTER_IP_ADDRESS > conf/slaves
    # configure tracer processes
    echo $MASTER_IP_ADDRESS > conf/tracers

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
fi
