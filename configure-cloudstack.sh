#!/bin/bash
#################################################################################
#
#          FILE:  configure.sh
#         USAGE:  ./configure.sh
#   DESCRIPTION: This script will configure the entire cloudstack environment
#                as soon as the docker-compose up script has finished booting
#
#       OPTIONS:  
#
#  REQUIREMENTS:  docker-compose up should be finished
#        AUTHOR:  Xavier Geerinck (xavier.geerinck@gmail.com)
#       COMPANY:  /
#       VERSION:  1.0.0
#       CREATED:  17/FEB/16 10:36 CET
#      REVISION:  1.0 - Base POC script
#
##################################################################################
##                            Environment Variables                             ##
##################################################################################
dns_ext=172.31.221.250
dns_int=172.31.221.250
nmask=255.255.255.0
hpvr=KVM
pod_gw=172.17.0.1
pod_start=172.17.0.220
pod_end=172.17.0.254
vlan_gw=10.30.28.1
vlan_start=10.30.28.220
vlan_end=10.30.28.254
 
#Put space separated host ips in following
host_ips=10.30.28.4
host_user=root
host_passwd=password
sec_storage=nfs://10.30.28.4/root/docker-compose-test/mgmt/exports/secondary
prm_storage=nfs://10.30.28.4/root/docker-compose-test/mgmt/exports/primary
 
##################################################################################
##                                   Utils                                      ##
##################################################################################
function execute_cmd {
    docker exec cloudmonkey /bin/bash -c "cloudmonkey -p local -c config $@"
}

function print_green {
    echo -e "\e[92m$@\e[39m"
}

function print_blue {
    echo -e "\e[34m$@\e[39m"
}

function print_red {
    echo -e "\e[31m$@\e[39m"
}

function print_yellow {
    echo -e "\e[33m$@\e[39m"
}

function print_title {
    print_blue "#########################################################"
    print_blue "$@"
    print_blue "#########################################################"
}

function print_error {
    print_red "[ERROR] $@" 1>&2
    exit 1
}

# $1 = file
# $2 = key
# $3 = new value
function set_config {
    if [ -z $1 -o -z $1 ]; then
        return;
    fi

    sed -i "s/^\($2\s*=\s*\).*\$/\2$3/" $1
}

##################################################################################
##                                   Script                                     ##
##################################################################################
# Make sure that the cloudmonkey container exists
if ! docker ps | grep cloudmonkey >/dev/null; then
    print_error "[Cloudmonkey] No container named cloudmonkey";
fi

execute_cmd "list accounts"

print_green "[Cloudmonkey] Creating zone" $zone_id
zone_id=`execute_cmd "create zone dns1=$dns_ext internaldns1=$dns_int name=DemoZone2 networktype=Basic" | grep ^id\ = | awk '{print $3}'`
 
print_green "[Cloudmonkey] Creating physical network" $phy_id
phy_id=`execute_cmd "create physicalnetwork name=phy-network zoneid=$zone_id" | grep ^id\ = | awk '{print $3}'`

print_green "[Cloudmonkey] Adding guest traffic"
# kvmnetworklabel=cloudbr0
execute_cmd "add traffictype traffictype=Guest physicalnetworkid=$phy_id kvmnetworklabel=cloudbr0"
print_green "[Cloudmonkey] Adding mgmt traffic"
execute_cmd "add traffictype traffictype=Management physicalnetworkid=$phy_id kvmnetworklabel=docker0"
print_green "[Cloudmonkey] Enabling physicalnetwork"
execute_cmd "update physicalnetwork state=Enabled id=$phy_id"
 
print_green "[Cloudmonkey] Enabling virtual router element and network service provider"
nsp_id=`execute_cmd "list networkserviceproviders name=VirtualRouter physicalnetworkid=$phy_id" | grep ^id\ = | awk '{print $3}'`
vre_id=`execute_cmd "list virtualrouterelements nspid=$nsp_id" | grep ^id\ = | awk '{print $3}'`
execute_cmd "api configureVirtualRouterElement Enabled=true id=$vre_id"
execute_cmd "update networkserviceprovider state=Enabled id=$nsp_id"
 
print_green "[Cloudmonkey] Enabling security group provider"
nsp_sg_id=`execute_cmd "list networkserviceproviders name=SecurityGroupProvider physicalnetworkid=$phy_id" | grep ^id\ = | awk '{print $3}'`
execute_cmd "update networkserviceprovider state=Enabled id=$nsp_sg_id"
 
print_green "[Cloudmonkey] Creating network $net_id for zone" $zone_id
netoff_id=`execute_cmd "list networkofferings name=DefaultSharedNetworkOfferingWithSGService" | grep ^id\ = | awk '{print $3}'`
net_id=`execute_cmd "create network zoneid=$zone_id name=guestNetworkForBasicZone displaytext=guestNetworkForBasicZone networkofferingid=$netoff_id" | grep ^id\ = | awk '{print $3}'`
 
print_green "[Cloudmonkey] Creating pod"
pod_id=`execute_cmd "create pod name=DemoPod zoneid=$zone_id gateway=$pod_gw netmask=$nmask startip=$pod_start endip=$pod_end" | grep ^id\ = | awk '{print $3}'`
 
print_green "[Cloudmonkey] Creating IP ranges for instances"
execute_cmd "create vlaniprange podid=$pod_id networkid=$net_id gateway=$vlan_gw netmask=$nmask startip=$vlan_start endip=$vlan_end forvirtualnetwork=false"
 
print_green "[Cloudmonkey] Creating cluster" $cluster_id
cluster_id=`execute_cmd "add cluster zoneid=$zone_id hypervisor=$hpvr clustertype=CloudManaged podid=$pod_id clustername=DemoCluster" | grep ^id\ = | awk '{print $3}'`
 
# Fix the agent.properties on the KVM
#docker exec cloudstack-kvm /bin/bash -c "sudo sed -i \"s/^\(private.network.device\s*=\s*\).*\$/\1docker0/\" /etc/cloudstack/agent/agent.properties"

#Put loop here if more than one
for host_ip in $host_ips;
do
  print_green "[Cloudmonkey] Adding host" $host_ip;
  execute_cmd "add host zoneid=$zone_id podid=$pod_id clusterid=$cluster_id hypervisor=$hpvr username=$host_user password=$host_passwd url=http://$host_ip";
done;

service nfs restart 
print_green "[Cloudmonkey] Adding primary storage"
execute_cmd "create storagepool zoneid=$zone_id podid=$pod_id clusterid=$cluster_id name=DemoPrimary url=$prm_storage"
 
print_green "[Cloudmonkey] Adding secondary storage"
execute_cmd "add secondarystorage zoneid=$zone_id url=$sec_storage"
 
# Done creating
execute_cmd "update zone allocationstate=Enabled id=$zone_id"
print_green "[Cloudmonkey] Basic zone deloyment completed!"

# Poll every 10 seconds until the systemvms are up
arr_vms=(`execute_cmd "list systemvms state=Running" | grep "^name =" | cut -d ' ' -f 3`)

while [ ${#arr_vms[@]} -eq 0 ]; do
    sleep 10
    arr_vms=(`execute_cmd "list systemvms state=Running" | grep "^name =" | cut -d ' ' -f 3`)
    print_yellow "[Cloudmonkey] Waiting till the systemvms are up"
done
