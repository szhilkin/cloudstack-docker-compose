# cloudstack-docker-compose
Docker Compose files to run a full Apache CloudStack environment

# Requirements
* A recent kernel (I prefer 3.19 series on Ubuntu 14.04)
* Port 22 should be available on the host, for the KVM container, which means you'll have to set up your ssh on another port
* Docker v1.10

# Install CentOS based cloudstack
1. Start by building the kvm container:
```
cd containers
docker build -f Dockerfile.kvmhost -t cloudstack-kvm .
```
2. Once that is done, start the containers by going to our root (cd ..) and run: `docker-compose up`
3. Now run `./configure.sh` and watch the setup being configured
4. If everything goes successfully (hopefully), go to the cloudstack dashboard (user: admin, password: test) and towards 'Global Settings'. There search for secstorage and edit the line that says: secstorage.allowed... and add the IP addresses of the servers that you will download the templates from.
5. Restart the management container by running: `docker exec -it cloudstack-mgmt /bin/bash -c "mknod /dev/loop5 -m0660 b 7 5; losetup -d /dev/loop6; service cloudstack-mgmt restart"`
6. Go to templates and download a template by adding it, then try to start and hope that it goes well 

# Docker configuration
Docker should be manually configured with a subnet range, in particular to allow configuration of the network.

For ubuntu, add the following to `/etc/default/docker`:
`DOCKER_OPTS="--bip=192.168.100.1/24 --fixed-cidr=192.168.100.0/28"`

