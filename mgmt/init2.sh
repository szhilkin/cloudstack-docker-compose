#!/bin/bash

#yum install -y nfs-utils portmap rpcbind
#service portmap start
yum install -y portmap

cat <<EOF > /etc/exports
/mgmt/exports  *(rw,async,no_root_squash,no_subtree_check)
EOF

service portmap start
service nfs start
