#!/bin/bash
echo -n "Management: "
docker inspect --format '{{ .NetworkSettings.IPAddress }}' cloudstack-mgmt
echo -n "KVM Node: "
docker inspect --format '{{ .NetworkSettings.IPAddress }}' cloudstack-kvm
echo -n "MySQL server: "
docker inspect --format '{{ .NetworkSettings.IPAddress }}' mysql-server
