#!/usr/bin/env bash

sudo mkdir -p /etc/kubernetes/ca /etc/kubernetes/ssl

if [ ! -f /etc/kubernetes/environment.sh ] ; then
    wget http://assets.example.com/k8s/environment.sh -O /etc/kubernetes/environment.sh
    source /etc/kubernetes/environment.sh
fi

# TLS Bootstrapping 使用的 Token
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
cat > /etc/kubernetes/token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

export BOOTSTRAP_TOKEN=$(cat /etc/kubernetes/token.csv)

cd /etc/kubernetes

# 创建 kubelet bootstrapping kubeconfig 文件

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig


#创建 kube-proxy kubeconfig 文件

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

echo -ne '''{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/admin-csr.json

echo -ne '''{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
'''>/etc/kubernetes/ca/ca-config.json


echo -ne '''{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/ca-csr.json

echo -ne '''{
  "CN": "etcd",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/etcd-csr.json

echo -ne '''{
  "CN": "harbor",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/harbor-csr.json


echo -ne '''{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/kube-proxy-csr.json


echo -ne '''{
  "CN": "kubernetes",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/kubernetes-csr.json

echo -ne '''{
  "CN": "registry",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
'''>/etc/kubernetes/ca/registry-csr.json

cd /etc/kubernetes/ssl

cfssl gencert -initca /etc/kubernetes/ca/ca-csr.json | cfssljson -bare ca

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes /etc/kubernetes/ca/kubernetes-csr.json | cfssljson -bare kubernetes

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes /etc/kubernetes/ca/admin-csr.json | cfssljson -bare admin

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes  /etc/kubernetes/ca/kube-proxy-csr.json | cfssljson -bare kube-proxy

tar -czvf ca.tar.gz ssl bootstrap.kubeconfig kube-proxy.kubeconfig token.csv

#upload ca.tar.gz to http://assets.example.com/k8s