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
#################################################################################
# Steps: 
#################################################################################
# 
#  1. (Hypervisor) NFS Server
#      1.1. Install nfs if not installed
#      1.2. Configure ports
#      1.3. Configure IPTables
#      1.4. Exports + Save them
#      1.5. Restart NFS
#  2. (KVM) Fix CGROUPS
#      2.1. Change cgconfig.conf
#  3. (KVM) SSHD
#      3.1. Start SSHD
#  4. (Hypervisor) Configure the cloudstack environment with cloudmonkey
#      4.1. Install + link docker containers
#           docker run -it --rm --link cloudstack-mgmt:8080 cloudstack/cloudmonkey
#      4.2. Run configure.sh
#  5. (Hypervisor) Network Configuration
#      5.1. Add cloudbr0 interface
#      5.2. Create docker0.100 VLAN
#      5.3. Add docker0.100 vlan to cloudbr0
#      5.4. Add VNET1 (eth1 SSVM) and VNET4 (eth1 CPVM) to docker0 bridge
#  6. Done
#
##################################################################################
##                                   Utils                                      ##
##################################################################################

function print_green {
    echo -e "\e[92m$@\e[39m"
}

function print_blue {
    echo -e "\e[34m$@\e[39m"
}

function print_red {
    echo -e "\e[31m$@\e[39m"
}

function print_title {
    print_blue "#########################################################"
    print_blue "$@"
    print_blue "#########################################################"
}

function print_error {
    print_red "[ERROR] $@" 1>&2
    exit
}

##################################################################################
##                                   Step 1                                     ##
##################################################################################
print_title '[NFS] (Hypervisor) Getting the NFS server ready'

# Install NFS if not installed
print_green '[NFS] Installing NFS if it is not installed'

if ! yum list installed "nfs-utils" >/dev/null 2>&1; then 
    yum install -y nfs-utils
fi

if ! yum list installed "nfs-utils-lib" >/dev/null 2>&1; then
    yum install -y nfs-utils-lib
fi

# Configure ports
print_green '[NFS] Configuring the NFS ports'

cat <<EOF > /etc/sysconfig/nfs
LOCKD_TCPPORT=32803
LOCKD_UDPPORT=32769
MOUNTD_PORT=892
NEED_STATD=yes
STATD_PORT=662
STATD_OUTGOING_PORT=2020
GSS_USE_PROXY="yes"
RPCNFSDARGS="-N 4 -N 4.1 -N 4.2"
EOF

# Configure IPTables
print_green '[NFS] Configuring IPTables to allow incoming traffic'

# See: https://www.centos.org/docs/5/html/5.2/Deployment_Guide/s2-sysconfig-nfs.html
iptables -A INPUT -m state --state NEW -p udp --dport 111   -j ACCEPT # Portmap/sunrpc
iptables -A INPUT -m state --state NEW -p tcp --dport 111   -j ACCEPT # Portmap/sunrpc
iptables -A INPUT -m state --state NEW -p udp --dport 2049  -j ACCEPT # Main Port
iptables -A INPUT -m state --state NEW -p tcp --dport 2049  -j ACCEPT # Main Port
iptables -A INPUT -m state --state NEW -p tcp --dport 32803 -j ACCEPT # LOCKD_TCPPORT
iptables -A INPUT -m state --state NEW -p udp --dport 32769 -j ACCEPT # LOCKD_UDPPORT
iptables -A INPUT -m state --state NEW -p tcp --dport 892   -j ACCEPT # Mountd
iptables -A INPUT -m state --state NEW -p udp --dport 892   -j ACCEPT # Mountd
iptables -A INPUT -m state --state NEW -p tcp --dport 875   -j ACCEPT 
iptables -A INPUT -m state --state NEW -p udp --dport 875   -j ACCEPT
iptables -A INPUT -m state --state NEW -p tcp --dport 662   -j ACCEPT # Statd
iptables -A INPUT -m state --state NEW -p udp --dport 662   -j ACCEPT # Statd

# Exports + Save
print_green '[NFS] Exporting the directories for cloudstack'

# Set chmod 777 on exported dir, http://mail-archives.apache.org/mod_mbox/cloudstack-users/201505.mbox/%3CCAHed4gZJqSkZW-gRGUudPP1tS7_XvBxcD70iz9qAMNRET8s0Zw@mail.gmail.com%3E
chmod -R 777 /root/docker-compose-test/mgmt

# Create exports
cat <<EOF > /etc/exports
/root/docker-compose-test/mgmt *(rw,async,no_root_squash,no_subtree_check,fsid=0,insecure)
EOF

print_green '[NFS] Saving the exports'

exportfs -rav # Save exports

# Restart NFS
print_green '[NFS] Restarting NFS'
service nfslock stop
service nfs stop
service rpc-statd stop
service rpcbind stop
umount /proc/fs/nfsd
service rpcbind start
service rpc-statd start
service nfs start
service nfslock start

##################################################################################
##                                   Step 2                                     ##
##################################################################################
print_title '[CGROUPS] (KVM) Fixing CGROUPS'

# Changing the cgconfig.conf file
print_green '[CGROUPS] Fixing the cgconfig.conf file'

docker exec cloudstack-kvm /bin/bash -c "cat <<EOF > /etc/cgconfig.conf
mount {
        cpuset          = /cgroup/cpuset;
        cpu,cpuacct     = /cgroup/cpu,cpuacct;
        memory          = /cgroup/memory;
        devices         = /cgroup/devices;
        freezer         = /cgroup/freezer;
        net_cls         = /cgroup/net_cls;
        blkio           = /cgroup/blkio;
}
EOF"
##################################################################################
##                                   Step 3                                     ##
##################################################################################
print_title '[SSHD] (KVM) Starting'
print_green '[SSHD] Starting SSHD so that we can use it as a host'
docker exec cloudstack-kvm /bin/bash -c "service sshd start"

##################################################################################
##                                   Step 4                                     ##
##################################################################################
print_title '[Cloudmonkey] (Hypervisor) Configuring the cloudstack environment'

# First configure the bridges
################################################################################
# add cloudbr0 interface
print_green '[Network] Adding cloudbr0 bridge'

if ! brctl show | grep -e "^cloudbr0" >/dev/null; then
    brctl addbr cloudbr0
fi

# Add docker0.100 VLAN
if ! brctl show | grep -e "^docker0" >/dev/null; then
    print_error 'docker0 bridge does not exist, exiting'
fi

print_green '[Network] Adding the docker0.100 VLAN'

if ! ip link | grep docker0.100@ >/dev/null; then
    ip link add link docker0 name docker0.100 type vlan id 100
fi

# Add docker0.100 VLAN to the cloudbr0 bridge
print_green '[Network] Adding docker0.100 VLAN to the cloudbr0 bridge'

# Add docker0.100 VLAN to the cloudbr0 bridge
print_green '[Network] Adding docker0.100 VLAN to the cloudbr0 bridge'

if ! brctl show cloudbr0 | grep docker0.100 >/dev/null; then
    brctl addif cloudbr0 docker0.100
fi

# Now the cloudmonkey setup
##################################################################################
print_green '[Cloudmonkey] Installing the cloudmonkey container and running our configure'
docker run -itd -v `pwd`:/cloudmonkey --name cloudmonkey cloudstack/cloudstack-cloudmonkey
./configure-cloudstack.sh
docker stop cloudmonkey
#docker rm cloudmonkey

# Cleanup cloudmonkey
docker rm -f $(docker ps -a | grep cloudstack/cloudstack-cloudmonkey | awk "{print \$1}")

##################################################################################
##                                   Step 5                                     ##
##################################################################################
print_title '[Network] (Hypervisor) Configuring the network'
print_green '[Network] Removing unneeded lines from iptables'

# Drop specific rules from the iptables output
for i in $(iptables -L FORWARD --line-numbers | grep -E "DROP\s*all" | awk '{ print $1 }'); do 
    iptables -D FORWARD $i
done

# TODO: Needs to sleep here, we need to wait till the agent caught up and created the system vm's
# TODO: So this will need to move to it's own step
# Add vnet1 (eth1 SSVM) and vnet4 (eth1 CPVM) to docker0 bridge
print_green '[Network] Adding vnet1 and vnet4 to the docker0 bridge'

if ! brctl show docker0 | grep vnet1; then 
    brctl delif cloudbr0 vnet1
    brctl addif docker0 vnet1
fi

if ! brctl show docker0 | grep vnet4; then
    brctl delif cloudbr0 vnet4
    brctl addif docker0 vnet4
fi

ifconfig cloudbr0 10.30.28.1 netmask 255.255.255.0
ifconfig cloudbr0 up
