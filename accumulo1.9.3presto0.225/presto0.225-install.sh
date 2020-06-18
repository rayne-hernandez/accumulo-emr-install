#!/bin/bash
#
# This script installs Presto 0.225 on an EMR instance with a connector to Accumulo 1.9.3 and authentication using an 
# LDAP server.
#
# Output commands to STDOUT, and exits if failure
set -x -e

# If Presto installation does not exist, continue installation
if [ ! -d "/home/hadoop/presto-server-0.225" ]
then
    cd /home/hadoop/

    # Setup variables
    PRESTO_HOME="/home/hadoop/presto-server"
    PRESTO_CATALOG="/etc/presto/conf.dist/catalog"
    ACCUMULO_HOME="/home/hadoop/accumulo"
    CLUSTER_ID=$(cat /mnt/var/lib/info/job-flow.json | jq '.jobFlowId' | tr -d '"')
    MASTER_IP_ADDRESS=$(cat /mnt/var/lib/info/job-flow.json | jq '.masterPrivateDnsName' | tr -d '"')
    MASTER_INSTANCE_GROUP_ID=$(aws emr describe-cluster --cluster-id ${CLUSTER_ID} | jq '.Cluster.InstanceGroups[] | select(.Name | contains("Master")) | .Id' | tr -d '"')
    MASTER_DNS_ADDRESS=$(echo $MASTER_IP_ADDRESS | sed 's/\./-/g' | sed 's/[^ ]* */ip-&.ext.d.us-west-2.kountable.com/g')
    #MASTER_DNS_ADDRESS=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$MASTER_INSTANCE_GROUP_ID'") | .PrivateDnsName' | tr -d '"')
    CORE_INSTANCE_GROUP_ID=$(aws emr describe-cluster --cluster-id ${CLUSTER_ID} | jq '.Cluster.InstanceGroups[] | select(.Name | contains("Core")) | .Id' | tr -d '"')
    CORE_IP_ADDRESSES=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$CORE_INSTANCE_GROUP_ID'") | .PrivateIpAddress' | tr -d '"')
    CORE_DNS_ADDRESSES=$(echo "$CORE_IP_ADDRESSES" | sed 's/\./-/g' | sed 's/[^ ]* */ip-&.ext.d.us-west-2.kountable.com/g')
    #CORE_DNS_ADDRESSES=$(aws emr list-instances --cluster-id ${CLUSTER_ID} | jq '.Instances[] | select(.InstanceGroupId == "'$CORE_INSTANCE_GROUP_ID'") | .PrivateDnsName' | tr -d '"')
    INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    ZOOKEEPER_HOST=$MASTER_DNS_ADDRESS
    ENVIRONMENT="dev"

    # Checks if Accumulo is running on the Master node
    master_node_initialized() {
        if ssh $MASTER_IP_ADDRESS stat /home/hadoop/accumulo/conf/tracers &> /dev/null
        then
            return 0
        else
            return 1
        fi
    }

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

    # Download Presto distribution tarball
    wget https://repo1.maven.org/maven2/com/facebook/presto/presto-server/0.225/presto-server-0.225.tar.gz
    # Untar tarball
    tar xzf presto-server-0.225.tar.gz
    # Create symlink for Presto distrubution 
    ln -s /home/hadoop/presto-server-0.225 /home/hadoop/presto-server

    cd presto-server

    # Create a configuration folder for Presto distribution
    mkdir etc/

    # Create a folder for Presto logging
    mkdir -p /var/log/presto/data
    # Create node configuration file
    touch etc/node.properties
    echo "node.environment=dev" > etc/node.properties
    echo "node.id=$INSTANCE_ID" >> etc/node.properties
    echo "node.data-dir=/var/log/presto/data" >> etc/node.properties

    # Create JVM configuration file
    touch etc/jvm.config
    cat > etc/jvm.config <<< '-server
-Xmx16G
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+UseGCOverheadLimit
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+ExitOnOutOfMemoryError'

    # Create logging configuration file
    touch etc/log.properties
    echo "com.facebook.presto=DEBUG" > etc/log.properties

    # Create Accumulo Presto connector configuration file
    mkdir etc/catalog/
    touch etc/catalog/accumulo.properties
    echo "connector.name=accumulo" > etc/catalog/accumulo.properties
    echo "accumulo.instance=kountable-accumulo" >> etc/catalog/accumulo.properties
    echo "accumulo.zookeepers=$ZOOKEEPER_HOST:2181" >> etc/catalog/accumulo.properties
    echo "accumulo.username=root" >> etc/catalog/accumulo.properties
    echo "accumulo.password=secret" >> etc/catalog/accumulo.properties

    # Check if current instance is a Master node
    if grep isMaster /mnt/var/lib/info/instance.json | grep true
    then 

         # Create instance configuration file
        touch etc/config.properties
        echo "coordinator=true" > etc/config.properties
        echo "node-scheduler.include-coordinator=false" >> etc/config.properties
        echo "http-server.http.port=8080" >> etc/config.properties
        echo "query.max-memory=50GB" >> etc/config.properties
        echo "query.max-memory-per-node=1GB" >> etc/config.properties
        echo "query.max-total-memory-per-node=2GB" >> etc/config.properties
        echo "discovery-server.enabled=true" >> etc/config.properties
        echo "discovery.uri=http://$MASTER_IP_ADDRESS:8080" >> etc/config.properties

        # Download Presto CLI executable
        wget https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.225/presto-cli-0.225-executable.jar
        mv presto-cli-0.225-executable.jar bin/presto
        chmod +x bin/presto

        # Check if core nodes are initialized, then copy over nessesary JARs
        while true
        do
            sleep 15
            if core_nodes_initialized
            then    
                for CORE_IP_ADDRESS in $(echo "$CORE_IP_ADDRESSES")
                do
                    #ssh $CORE_IP_ADDRESS "mkdir -p $ACCUMULO_HOME/lib/ext"
                    scp $PRESTO_HOME/plugin/accumulo/presto-accumulo-0.225.jar $CORE_IP_ADDRESS:$ACCUMULO_HOME/lib/ext
                done
                break
            fi
        done
    else
        # Create instance configuration file
        touch etc/config.properties
        echo "coordinator=false" > etc/config.properties
        echo "http-server.http.port=8080" >> etc/config.properties
        echo "query.max-memory=50GB" >> etc/config.properties
        echo "query.max-memory-per-node=1GB" >> etc/config.properties
        echo "query.max-total-memory-per-node=2GB" >> etc/config.properties
        echo "discovery.uri=http://$MASTER_IP_ADDRESS:8080" >> etc/config.properties

        # Add time for Master node to initialize Accumulo
        while true
        do
            sleep 15
            if master_node_initialized
            then 
                break
            fi
        done
    fi

    # Start Presto
    bin/launcher start
fi
