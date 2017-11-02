#!/usr/bin/env bash

sudo mkdir -p /etc/kubernetes/ca /etc/kubernetes/ssl

echo -ne '{
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
'>/etc/kubernetes/ca/admin-csr.json

echo -ne '{
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
'>/etc/kubernetes/ca/ca-config.json


echo -ne '{
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
'>/etc/kubernetes/ca/ca-csr.json

echo -ne '{
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
'>/etc/kubernetes/ca/etcd-csr.json

echo -ne '{
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
'>/etc/kubernetes/ca/harbor-csr.json


echo -ne '{
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
'>/etc/kubernetes/ca/kube-proxy-csr.json


echo -ne '{
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
'>/etc/kubernetes/ca/kubernetes-csr.json

echo -ne '{
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
'>/etc/kubernetes/ca/registry-csr.json

cd /etc/kubernetes/ssl

cfssl gencert -initca /etc/kubernetes/ca/ca-csr.json | cfssljson -bare ca

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes /etc/kubernetes/ca/kubernetes-csr.json | cfssljson -bare kubernetes

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes /etc/kubernetes/ca/admin-csr.json | cfssljson -bare admin

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/kubernetes/ca/ca-config.json -profile=kubernetes  /etc/kubernetes/ca/kube-proxy-csr.json | cfssljson -bare kube-proxy