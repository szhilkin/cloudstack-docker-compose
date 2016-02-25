# cloudstack-docker-compose
Docker Compose files to run a full Apache CloudStack environment

# Requirements
 - A recent kernel (I prefer 3.19 series on Ubuntu 14.04)
 - Port 22 should be available on the host, for the KVM container, which means you'll have to set up your ssh on another port

# Docker configuration
Docker should be manually configured with a subnet range, in particular to allow configuration of the network.

For ubuntu, add the following to `/etc/default/docker`:
`DOCKER_OPTS="--bip=192.168.100.1/24 --fixed-cidr=192.168.100.0/28"`

