#!/usr/bin/env bash

id etcd >& /dev/null
if [ $? -ne 0 ]
then
   groupadd etcd
    useradd etcd -g etcd -s /sbin/nologin
fi

SERVER_IP=`/sbin/ifconfig  | grep 'inet'| grep -v '127.0.0.1' |head -n1 |tr -s ' '|cut -d ' ' -f3 | cut -d: -f2`
HOSTNAME=`hostname -f`

sudo mkdir -p /etc/kubernetes/ssl /etc/etcd /data/etcd
sudo chown -R etcd:etcd /etc/etcd /data/etcd

if [ ! -f /usr/bin/etcd ] ; then
    wget http://assets.example.com/k8s/etcd -O /usr/bin/etcd
    chmod a+x /usr/bin/etcd
    wget http://assets.example.com/k8s/etcdctl -O /usr/bin/etcdctl
    chmod a+x /usr/bin/etcdctl
fi

echo -ne 'ETCD_NAME=deeplearning
ETCD_DATA_DIR="/data/etcd"
ETCD_LISTEN_PEER_URLS="https://'$SERVER_IP':2380"
ETCD_LISTEN_CLIENT_URLS="https://'$SERVER_IP':2379"

#[cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://'$SERVER_IP':2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="https://'$SERVER_IP':2379"
ETCD_INITIAL_CLUSTER="deeplearning3=https://'$SERVER_IP':2380,deeplearning2=https://10.3.136.213:2380,deeplearning1=https://10.3.136.211:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
'>/etc/etcd/etcd.conf

echo -ne '[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/data/etcd
EnvironmentFile=-/etc/etcd/etcd.conf
User=etcd
ExecStart=/usr/bin/etcd \
    --name ${ETCD_NAME} \
    --data-dir ${ETCD_DATA_DIR} \
    --initial-advertise-peer-urls ${ETCD_INITIAL_ADVERTISE_PEER_URLS} \
    --listen-peer-urls ${ETCD_LISTEN_PEER_URLS} \
    --listen-client-urls ${ETCD_LISTEN_CLIENT_URLS},http://127.0.0.1:2379 \
    --advertise-client-urls ${ETCD_ADVERTISE_CLIENT_URLS} \
    --initial-cluster-token ${ETCD_INITIAL_CLUSTER_TOKEN} \
    --initial-cluster ${ETCD_INITIAL_CLUSTER} \
    --initial-cluster-state ${ETCD_INITIAL_CLUSTER_STATE} \
    --enable-v2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
'>/usr/lib/systemd/system/etcd.service

systemctl daemon-reload
systemctl enable etcd
systemctl start etcd