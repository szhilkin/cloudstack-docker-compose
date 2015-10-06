#!/bin/bash

# Configure NFS
yum install -y portmap nfs-utils openssh-server
echo "root:password" | chpasswd
sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
cat <<EOF > /etc/exports
/exports  *(rw,async,no_root_squash,no_subtree_check,fsid=0)
/mgmt *(rw,async,no_root_squash,no_subtree_check,fsid=0)
EOF

#Start NFS services
service rpcbind start
service nfs start
service nfs restart
service sshd start

exportfs -a

# Wait for MySQL server
sleep 10

# Install systemvm template
#if [ ! -f /mgmt/exports/secondary/template/tmpl/1/3/template.properties ]; then
#    /usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt \ 
#    -m /mgmt/exports/secondary \ 
#    -h kvm \ 
#    -F \ 
#    -u http://jenkins.buildacloud.org/job/build-systemvm64-master/lastSuccessfulBuild/artifact/tools/appliance/dist/systemvm64template-master-4.6.0-kvm.qcow2.bz2 \ 
#    -o ${MYSQL_PORT_3306_TCP_ADDR}
#fi



# Ugly hack to get api.integration.port configured
#grep 'integration.api.port' /root/init.sh
#if [ $? = 1 ]; then
#    cat <<EOF >/root/add.txt
#mysql -hdatabase -uroot -p${MYSQL_ENV_MYSQL_ROOT_PASSWORD} -e "UPDATE cloud.configuration SET value='8096' WHERE name='integration.api.port'"
#EOF
#sed -i '/esac/r /root/add.txt' /root/init.sh
#fi
# Continue with regular mgmt server startup
/root/init.sh

