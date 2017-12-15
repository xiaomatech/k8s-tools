#!/usr/bin/env bash

sudo mkdir -p /etc/cni/net.d /etc/kubernetes /etc/kubernetes/ssl /var/log/kube

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

if [ ! -f /usr/bin/kube-scheduler ] ; then
    wget http://assets.example.com/k8s/kube-scheduler -O /usr/bin/kube-scheduler
    chmod a+x /usr/bin/kube-scheduler
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

echo '
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/scheduler
User=kube
ExecStart=/usr/bin/kube-scheduler \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBE_MASTER \
    $KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/kube-scheduler.service

echo -ne '
KUBE_SCHEDULER_ARGS=" --address='$SERVER_IP' --feature-gates=AllAlpha=true,Accelerators=true,AdvancedAuditing=true,ExperimentalCriticalPodAnnotation=true,TaintBasedEvictions=true,PodPriority=true"
'>/etc/kubernetes/scheduler

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf

chown -R kube:kube /etc/kubernetes /var/log/kube

systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
systemctl status kube-scheduler