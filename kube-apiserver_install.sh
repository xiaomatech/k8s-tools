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

if [ ! -f /usr/bin/kube-apiserver ] ; then
    wget http://assets.example.com/k8s/kube-apiserver -O /usr/bin/kube-apiserver
    chmod a+x /usr/bin/kube-apiserver
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

echo -ne '[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
After=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/apiserver
User=kube
ExecStart=/usr/bin/kube-apiserver \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_ETCD_SERVERS \
    $KUBE_API_ADDRESS \
    $KUBE_API_PORT \
    $KUBE_ALLOW_PRIV \
    $KUBE_SERVICE_ADDRESSES \
    $KUBE_ADMISSION_CONTROL \
    $KUBE_API_ARGS
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-apiserver.service


echo -ne '
KUBE_LOGTOSTDERR="--logtostderr=true"
KUBE_LOG_LEVEL="--v=0"
KUBE_ALLOW_PRIV="--allow-privileged=true"
KUBE_MASTER="--master='$KUBE_APISERVER'"
'>/etc/kubernetes/config

echo -ne '
KUBE_API_PORT="--insecure-port=8080"
KUBE_API_ADDRESS="--advertise-address='$SERVER_IP' --bind-address='$SERVER_IP' --insecure-bind-address='$SERVER_IP'"
KUBE_ETCD_SERVERS="--etcd-servers='$ETCD_ENDPOINTS'"
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range='$SERVICE_CIDR' --service-node-port-range=8400-32767"
KUBE_ADMISSION_CONTROL="--admission-control=NamespaceLifecycle,DenyEscalatingExec,LimitRanger,ServiceAccount,ResourceQuota,PodSecurityPolicy,DefaultStorageClass"
KUBE_API_ARGS="--audit-log-maxage=30 --audit-log-maxbackup=3 --audit-log-maxsize=100 --audit-log-path=/var/log/audit.log --runtime-config=extensions/v1beta1=true,extensions/v1beta1/networkpolicies=true,rbac.authorization.k8s.io/v1beta1=true,extensions/v1beta1/podsecuritypolicy=true --feature-gates=AllAlpha=true,Accelerators=true,AdvancedAuditing=true,ExperimentalCriticalPodAnnotation=true,TaintBasedEvictions=true --v=2"
'>/etc/kubernetes/apiserver

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver
systemctl status kube-apiserver
