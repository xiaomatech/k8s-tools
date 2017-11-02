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

if [ ! -f /usr/bin/kubectl ] ; then
    wget http://assets.example.com/k8s/kubectl -O /usr/bin/kubectl
    chmod a+x /usr/bin/kubectl
fi


if [ ! -f /usr/bin/etcdctl ] ; then
    wget http://assets.example.com/k8s/etcdctl -O /usr/bin/etcdctl
    chmod a+x /usr/bin/etcdctl
fi


if [ ! -f /usr/bin/helm ] ; then
    wget http://assets.example.com/k8s/helm -O /usr/bin/helm
    chmod a+x /usr/bin/helm
fi