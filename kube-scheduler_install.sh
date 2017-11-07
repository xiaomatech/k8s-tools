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
KUBE_LOGTOSTDERR="--logtostderr=true"
KUBE_LOG_LEVEL="--v=0"
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
KUBE_SCHEDULER_ARGS=" --leader-elect=true --address='$SERVER_IP' --feature-gates=AllAlpha=true,Accelerators=true,AdvancedAuditing=true,ExperimentalCriticalPodAnnotation=true,TaintBasedEvictions=true,PodPriority=true"
'>/etc/kubernetes/scheduler

echo -ne '[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
'>/etc/systemd/system.conf.d/kubernetes-accounting.conf

echo -ne 'd /var/run/kubernetes 0755 kube kube -
'>/usr/lib/tmpfiles.d/kubernetes.conf


systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
systemctl status kube-scheduler