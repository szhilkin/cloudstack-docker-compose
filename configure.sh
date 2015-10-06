#!/bin/bash

# FIXME: Check if configuration is done
# FIXME: get NFS addresses
NFS_SERVER=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cloudstack-mgmt)

set -e


EXEC="cloudmonkey -p local -c cloudmonkey.config"

# Create the Zone
#echo "Creating Zone"
DUMMY=$($EXEC create zone name="CloudStack Docker Demo - Basic" networktype=Basic dns1=8.8.8.8 internaldns1=8.8.8.8)
ZONE_ID=$($EXEC list zones filter=id | grep id | cut -f 3 -d ' ')

echo "Creating Physical network"
# Create and configure physical network
PHY_ID=$($EXEC create physicalnetwork name=phy-network zoneid=$ZONE_ID | grep ^id\ = | cut -f 3 -d ' ')

DUMMY=$($EXEC add traffictype traffictype=Guest physicalnetworkid=$PHY_ID)
DUMMY=$($EXEC add traffictype traffictype=Management physicalnetworkid=$PHY_ID)
DUMMY=$($EXEC update physicalnetwork state=Enabled id=$PHY_ID)

echo "Configuring Virtual Router"
nsp_id=`$EXEC list networkserviceproviders name=VirtualRouter physicalnetworkid=$PHY_ID | grep ^id\ = | awk '{print $3}'`
vre_id=`$EXEC list virtualrouterelements nspid=$nsp_id | grep ^id\ = | awk '{print $3}'`
DUMMY=$($EXEC api configureVirtualRouterElement enabled=true id=$vre_id)
DUMMY=$($EXEC update networkserviceprovider state=Enabled id=$nsp_id)

echo "Enabling Security Groups"
nsp_sg_id=`$EXEC list networkserviceproviders name=SecurityGroupProvider physicalnetworkid=$PHY_ID | grep ^id\ = | awk '{print $3}'`
DUMMY=$($EXEC update networkserviceprovider state=Enabled id=$nsp_sg_id)

echo "Creating default network"
netoff_id=`$EXEC list networkofferings name=DefaultSharedNetworkOfferingWithSGService | grep ^id\ = | awk '{print $3}'`
net_id=`$EXEC create network zoneid=$ZONE_ID name=guestNetworkForBasicZone displaytext=guestNetworkForBasicZone networkofferingid=$netoff_id | grep ^id\ = | awk '{print $3}'`

echo "Creating Pod"
pod_id=`$EXEC create pod name=DemoPod zoneid=$ZONE_ID gateway=192.168.100.1 netmask=255.255.255.0 startip=192.168.100.20 endip=192.168.100.25 | grep ^id\ = | awk '{print $3}'`

echo "Configuring Guest IP range"
DUMMY=$($EXEC create vlaniprange podid=$pod_id networkid=$net_id gateway=192.168.100.1 netmask=255.255.255.0 startip=192.168.100.30 endip=192.168.100.50 forvirtualnetwork=false)

echo "Creating cluster"
cluster_id=`$EXEC add cluster zoneid=$ZONE_ID hypervisor=KVM clustertype=CloudManaged podid=$pod_id clustername=DemoCluster | grep ^id\ = | awk '{print $3}'`

echo "Adding host"
DUMMY=$($EXEC add host zoneid=$ZONE_ID podid=$pod_id clusterid=$cluster_id hypervisor=KVM username=root password=password url=http://192.168.100.1)

echo "Creating primary storage"
DUMMY=$($EXEC create storagepool zoneid=$ZONE_ID podid=$pod_id clusterid=$cluster_id name=DemoPrimary provider=DefaultPrimary scope=cluster url=nfs://${NFS_SERVER}/exports/primary)

echo "Creating secondary storage"
DUMMY=$($EXEC add imagestore name=DemoSecondary provider=NFS zoneid=$ZONE_ID url=nfs://${NFS_SERVER}/exports/secondary)



echo "Enabling Zone"
$EXEC update zone allocationstate=Enabled id=$ZONE_ID

echo "All done!"

