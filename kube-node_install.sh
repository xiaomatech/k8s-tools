#!/usr/bin/env bash

sudo mkdir -p /etc/cni/net.d /etc/kubernetes /etc/kubernetes/ssl /etc/kubernetes/manifests /var/log/kube

if [ ! -f /etc/kubernetes/environment.sh ] ; then
    wget http://assets.example.com/k8s/environment.sh -O /etc/kubernetes/environment.sh
fi

source /etc/kubernetes/environment.sh

if [ ! -f /etc/kubernetes/token.csv ] ; then
    wget http://assets.example.com/k8s/ca.tar.gz -O /tmp/ca.tar.gz
    sudo tar -zxvf /tmp/ca.tar.gz -C /etc/kubernetes/
    rm -rf /tmp/ca.tar.gz
fi

id kube >& /dev/null
if [ $? -ne 0 ]
then
   groupadd kube
   useradd -g kube kube -s /sbin/nologin
fi

SERVER_IP=`/sbin/ifconfig  | grep 'inet'| grep -v '127.0.0.1' |head -n1 |tr -s ' '|cut -d ' ' -f3 | cut -d: -f2`
HOSTNAME=`hostname -f`

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
KUBE_LOGTOSTDERR="--logtostderr=false --log-dir=/var/log/kube"
KUBE_LOG_LEVEL="--v=4"
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
KUBELET_POD_INFRA_CONTAINER="--pod-infra-container-image=registry.example.com/kube/pause-amd64:3.0"
KUBELET_ARGS="--pod-manifest-path=/etc/kubernetes/manifests --runtime-cgroups=/systemd/system.slice --cgroup-driver=systemd --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig --kubeconfig=/etc/kubernetes/kubelet.kubeconfig --require-kubeconfig --cert-dir=/etc/kubernetes/ssl --cluster-dns='$CLUSTER_DNS_SVC_IP' --cluster-domain='$CLUSTER_DNS_DOMAIN' --serialize-image-pulls=false --register-node=true --logtostderr=true --feature-gates=AllAlpha=true,Accelerators=true,AdvancedAuditing=true,ExperimentalCriticalPodAnnotation=true,TaintBasedEvictions=true,PodPriority=true  "
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
KUBE_PROXY_ARGS="--kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig --bind-address='$SERVER_IP' --hostname-override='$HOSTNAME' --cluster-cidr='$CLUSTER_CIDR' --logtostderr=true --feature-gates=AllAlpha=true"
'>/etc/kubernetes/proxy

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf


if [ ! -f /etc/kubernetes/token.csv ];then
    wget http://yum.meizu.mz/k8s/ssl/token.csv -O /etc/kubernetes/token.csv
fi

if [ ! -f /etc/kubernetes/bootstrap.kubeconfig ];then
    wget http://yum.meizu.mz/k8s/ssl/bootstrap.kubeconfig -O /etc/kubernetes/bootstrap.kubeconfig
fi

if [ ! -f /etc/kubernetes/kube-proxy.kubeconfig ];then
    wget http://yum.meizu.mz/k8s/ssl/kube-proxy.kubeconfig -O /etc/kubernetes/kube-proxy.kubeconfig
fi

chown -R kube:kube /etc/kubernetes /var/log/kube

systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status kube-proxy

systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet
