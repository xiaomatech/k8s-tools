#!/usr/bin/env bash

. environment.sh

id kube >& /dev/null
if [ $? -ne 0 ]
then
   groupadd kube
   useradd -g kube kube -s /sbin/nologin
fi

SERVER_IP=`/sbin/ifconfig  | grep 'inet'| grep -v '127.0.0.1' |head -n1 |tr -s ' '|cut -d ' ' -f3 | cut -d: -f2`
HOSTNAME=`hostname -f`

sudo mkdir -p /etc/cni/net.d /etc/kubernetes /etc/kubernetes/ssl

if [ ! -f /usr/bin/kubelet ] ; then
    wget http://assets.example.com/k8s/kubelet -O /usr/bin/kubelet
    chmod a+x /usr/bin/kubelet
fi

if [ ! -f /usr/bin/kube-proxy ] ; then
    wget http://assets.example.com/k8s/kube-proxy -O /usr/bin/kube-proxy
    chmod a+x /usr/bin/kube-proxy
fi


if [ ! -d /opt/cni ] ; then
    wget http://assets.example.com/k8s/kubernetes-cni.tar.gz -O /tmp/kubernetes-cni.tar.gz
    sudo tar -zxvf /tmp/kubernetes-cni.tar.gz -C /opt
    rm -rf /tmp/kubernetes-cni.tar.gz
fi

if [ ! -f /usr/sbin/pipework ];then
    wget http://assets.example.com/k8s/pipework -O /usr/sbin/pipework
    chmod a+x /usr/sbin/pipework
fi

echo -ne '
KUBE_LOGTOSTDERR="--logtostderr=true"
KUBE_LOG_LEVEL="--v=0"
KUBE_ALLOW_PRIV="--allow-privileged=true"
KUBE_MASTER="--master='$KUBE_APISERVER'"
'>/etc/kubernetes/config

echo -ne '
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/kubelet
ExecStart=/usr/bin/kubelet \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBELET_API_SERVER \
    $KUBELET_ADDRESS \
    $KUBELET_PORT \
    $KUBELET_HOSTNAME \
    $KUBE_ALLOW_PRIV \
    $KUBELET_POD_INFRA_CONTAINER \
    $KUBELET_ARGS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kubelet.service

echo -ne '
KUBELET_ADDRESS="--address='$SERVER_IP'"
KUBELET_PORT="--port=10250"
KUBELET_HOSTNAME="--hostname-override='$HOSTNAME'"
KUBELET_POD_INFRA_CONTAINER="--pod-infra-container-image=registry.meizu.com/common/pause-amd64:3.0"
KUBELET_ARGS="--cgroup-driver=systemd --cluster-dns='$CLUSTER_DNS_SVC_IP' --cluster-domain='$CLUSTER_DNS_DOMAIN' --serialize-image-pulls=false --register-node=true --logtostderr=true --feature-gates=AllAlpha=true,Accelerators=true,AdvancedAuditing=true,ExperimentalCriticalPodAnnotation=true,TaintBasedEvictions=true --v=2"
'>/etc/kubernetes/kubelet

echo -ne '
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/proxy
ExecStart=/usr/bin/kube-proxy \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_MASTER \
    $KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-proxy.service

echo -ne '
KUBE_PROXY_ARGS=" --bind-address='$SERVER_IP' --hostname-override='$HOSTNAME' --cluster-cidr='$CLUSTER_CIDR' --logtostderr=true"
'>/etc/kubernetes/proxy

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf

systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status kube-proxy

systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet
