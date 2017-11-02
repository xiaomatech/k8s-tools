#!/usr/bin/env bash

DEVS="/dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg"
CIDR="10.3.136.1/24"
REG_URL="registry.example.com"

yum install -y docker

#docker storage
if [ ! -f /dev/mapper/docker--pool-thinpool ];then
    sudo pvcreate $DEVS
    sudo vgcreate docker-pool $DEVS
    sudo lvcreate --wipesignatures y -n thinpool docker-pool -l 95%VG
    sudo lvcreate --wipesignatures y -n thinpoolmeta docker-pool -l 1%VG
    sudo lvconvert -y --zero n -c 512K --thinpool docker-pool/thinpool --poolmetadata docker-pool/thinpoolmeta
    sudo lvchange --metadataprofile docker-thinpool docker-pool/thinpool
    sudo rm -rf  /var/lib/docker
fi

#docker network
ip link show docker0 >/dev/null 2>&1 || rc="$?"
if [[ "$rc" -eq "0" ]]; then
  sudo ip link set dev docker0 down
  sudo ip link delete docker0
  sudo brctl addbr br0
  sudo ip addr add $CIDR dev br0
  sudo ip link set dev br0 up
fi

echo -ne 'activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
'>/etc/lvm/profile/docker-thinpool.profile

echo -ne '
OPTIONS=" --selinux-enabled=false --log-driver=journald -s devicemapper --default-ulimit nofile=2560000:2560000 "
DOCKER_CERT_PATH=/etc/docker
ADD_REGISTRY="--add-registry='$REG_URL'"
INSECURE_REGISTRY="--insecure-registry='$REG_URL'"
DOCKER_TMPDIR=/var/tmp
LOGROTATE=true
'>/etc/sysconfig/docker


echo -ne '
DOCKER_NETWORK_OPTIONS="-b=none"
#DOCKER_NETWORK_OPTIONS="-b=br0"
'>/etc/sysconfig/docker-network

echo -ne '
DOCKER_STORAGE_OPTIONS=" --storage-driver devicemapper --storage-opt dm.fs=xfs --storage-opt dm.thinpooldev=/dev/mapper/docker--pool-thinpool --storage-opt dm.use_deferred_removal=true --storage-opt dm.use_deferred_deletion=true "
'>/etc/sysconfig/docker-storage

echo -ne '
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target rhel-push-plugin.socket
Wants=docker-storage-setup.service

[Service]
Type=notify
NotifyAccess=all
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-storage
EnvironmentFile=-/etc/sysconfig/docker-network
Environment=GOTRACEBACK=crash
ExecStart=/usr/bin/docker-current daemon \
          --exec-opt native.cgroupdriver=systemd \
          $OPTIONS \
          $DOCKER_STORAGE_OPTIONS \
          $DOCKER_NETWORK_OPTIONS \
          $ADD_REGISTRY \
          $BLOCK_REGISTRY \
          $INSECURE_REGISTRY
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=0
MountFlags=slave
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/docker.service

systemctl daemon-reload
systemctl enable docker
systemctl start docker