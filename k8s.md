本文档将介绍如何使用二进制包手动部署一个高可用的Kubernetes 集群

目的：
> 1 尽管可以使用kubeadm快速初始化一个Kubernetes集群，但是当前kubeadm还不能用于生产环境，kubeadm搭建的集群环境Master节点不是HA的，ETCD也没有进行集群化部署。

> 2 kubemini 也只是单节点的 kubernetes 工具

> 3 kops 目前只支持AWS，还没有对其他云进行支持

> 4 国人 开源的 kubekit 为离线安装kubernetes 集群做出了尝试，但是对于CA HA 方面处理的较少，同时也欠缺灵活定制能力

> 5 同时我们更希望运维、开发人员能通过step by step的部署方式来深入了解Kubernetes集群的配置关系，各组件的依赖关系、交互原理。以能够根据自己的需要决定Kubernetes的部署形态并快速的解决实际问题。

* 本文档采用了 TLS 双向认证、RBAC授权等严格的安全机制，需要从头开始部署，否则会出现大量的认证、授权失败问题。同时 TLS 也是一把双刃剑，在安全加密和负载效率之间如何取得平衡也是我们关心的问题，欢迎大家联系我们广泛交流。

## 集群设计理念

整体集群设计规划
```

                      ┌─────────────────────────────────────────────────────────────────────────┐                    
                      │                             10.138.232.140                              │                    
                      │                                 HAProxy                                 │                    
                      └──▲─────────────────────────────────▲────────────────────────────────▲───┘                    
                         │                                 │                                │                        
                         │        ┌────────────────────────┴────────────────────────┐       │                        
                         │        │                  10.138.48.164                  │       │                        
                         │        │┌──────────────┐┌──────────────┐┌──────────────┐ │       │                        
                         │        ││     ETCD     ││  kubernetes  ││  kubernetes  │ │       │                        
                         │        ││              ││    master    ││     node     │ │       │                        
                         │        │└──────────────┘└──────────────┘└──────────────┘ │       │                        
                         │        └─────────────────────────────────────────────────┘       │                        
┌────────────────────────┴────────────────────────┐               ┌─────────────────────────┴───────────────────────┐
│                 10.138.232.252                  │               │                  10.138.24.24                   │
│┌──────────────┐┌──────────────┐┌──────────────┐ │               │┌──────────────┐┌──────────────┐┌──────────────┐ │
││     ETCD     ││  kubernetes  ││  kubernetes  │ │               ││     ETCD     ││  kubernetes  ││  kubernetes  │ │
││              ││    master    ││     node     │ │               ││              ││    master    ││     node     │ │
│└──────────────┘└──────────────┘└──────────────┘ │               │└──────────────┘└──────────────┘└──────────────┘ │
└─────────────────────────────────────────────────┘               └─────────────────────────────────────────────────┘

```
在整个集群的搭建上我们规划采用四台HOST主机，具体如下

* Host-00: 对外部访问Kubernetes集群(目前只Proxy kube-apiserver 访问)进行反向代理负载均衡。对于负载均衡集群本身的HA后续文章我们将单独讨论。
* Host-01: ETCD Server 、Kubernetes Master, Kubernetes  Node
* Host-02: ETCD Server 、Kubernetes Master, Kubernetes  Node
* Host-03: ETCD Server 、Kubernetes Master, Kubernetes  Node

> Kubernetes Master: kube-apiserver, kube-controller-manager, kube-scheduler
> Kubernetes Node: kubelet, kube-proxy, Docker, Flannel or Calico

IP地址规划如下:
* Host-00: 10.138.232.140
* Host-01: 10.138.48.164
* Host-02: 10.138.232.252
* Host-03: 10.138.24.24

Host name地址规划如下:
* Host-00: node10
* Host-01: node00
* Host-02: node01
* Host-03: node02
请务必修改对应的host文件，否则会导致部署失败

### 1.1 系统环境
* cfssl CA证书命令行工具
* Kubernetes 1.7.4
* Docker 17.04.0-ce
* Etcd 3.2.6
* Calico & CNI 网络
* TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
* RBAC 授权
* kubelet TLS BootStrapping
* kubedns、dashboard、heapster (influxdb、grafana)、EFK (elasticsearch、fluentd、kibana) 插件
在实际部署当中，可以根据需要将不同的服务部署在更多的Host里面。

规划以下集群 相关配置：
```
# TLS Bootstrapping 使用的 Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="dec0ac166ff2dbf8eab068ca47decaa4"

# 建议用 未用的网段 来定义服务网段和 Pod 网段 (需要进一步细化 服务网段、POD网段、外部访问之间的关系)

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用 IP:Port 可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达 (网络插件 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
NODE_PORT_RANGE="8400-9000"

# etcd 集群服务地址列表 (配置ETCD集群、ETCD自身的gRPC代理ETCD集群外部一律通过gRPC-Proxy访问)
# ETCD_ENDPOINTS="https://10.138.48.164:23790,https://10.138.232.252:23790,https://10.138.24.24:23790"


# kubernetes 网络配置前缀
NETWORK_PLUGIN_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (预分配，一般是 SERVICE_CIDR 中第一个IP)
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"
# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."
```

### CA 必要工具安装
> cfssl
安装CFSSL
```
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64  /usr/local/cfssl/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/cfssl/cfssljson

wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl-certinfo_linux-amd64
sudo mv cfssl-certinfo_linux-amd64 /usr/local/cfssl/cfssl-certinfo

export PATH=/usr/local/cfssl:$PATH
```

可以创建config文件和csr文件 查看基本结构
```
mkdir ca
cd ca
cfssl print-defaults config > config.json
cfssl print-defaults csr > csr.json
```

### CA 证书规划

我们对整个Kubernetes集群创建一套完全独立的证书进行TLS验证，
* 证书的规划直接和整个集群的各种服务紧密结合我们将根据不同服务来划分证书的生成方案
* Kubernetes 1.6以后已经采用RBAC模型来管理系统角色权限，在生成 Kubernetes 证书时我们将依赖Kubernetes RBAC模型来讨论
```
          ┌──────────────────┐          
          │ Cluster Root CA  │          
          └───┬─────────┬────┘          
              │         │               
┌─────────────▼────┐┌───▼──────────────┐
│     ETCD CA      ││  Kubernetes CA   │
└──────────────────┘└──────────────────┘

```
* 整个集群，我们设计一个 Cluster Root CA 根证书来作为整个集群所有子证书的签发依据
* Cluster Root CA 直接签发 ETCD 和 Kubernetes 相关的所有证书
* 尝试 通过 Cluster Root CA 签发多级证书，但是没有成功

>注意，Kubernetes 集群很多组件严重依赖ETCD 都需要使用ETCD Client CA来进行ETCD 访问

生成脚本如下:
生成Cluster Root CA

```
cat > ../ca/cluster-root-ca-csr.json <<EOF
{
  "CN": "cluster-root-ca",
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
EOF

cfssl gencert -initca ../ca/cluster-root-ca-csr.json | cfssljson -bare ../ca/cluster-root-ca
```

ETCD CA 体系

```
                   ┌────────────────────┐                 
                   │       ETCD01       │                 
                   │ 10.138.48.164:2379 │                 
                   └─▲────────────────▲─┘                 
                 ┌───┴──┐         ┌───┴──┐                
                 │ peer │         │ peer │                
                 └───┬──┘         └───┬──┘                
┌────────────────────▼┐              ┌▼──────────────────┐
│       ETCD02        │   ┌──────┐   │      ETCD03       │
│ 10.138.232.252:2379 ◀───┤ peer ├───▶ 10.138.24.24:2379 │
│                     │   └──────┘   │                   │
└─────────────────────┘              └───────────────────┘

```
> 在三台host主机上部署ETCD集群，ETCD需要三个Server节点之间进行Peer通信。我们首先为ETCD server和 peer 分配CA

```
┌───────────────────────────────────────────────────────────┐    
│                       Cluster Root CA                     │    
└──────┬──────────────────────┬───────────────────────┬─────┘    
       │                      │                       │          
       │                      │                       │          
┌─────────▼──────────┐ ┌─────────▼──────────┐ ┌──────────▼─────────┐
│   ETCD Server CA   │ │   ETCD Server CA   │ │   ETCD Server CA   │
│   10.138.48.164    │ │   10.138.232.252   │ │    10.138.24.24    │
└────────────────────┘ └────────────────────┘ └────────────────────┘
```
首先通过ETCD Root CA为三个ETCD Server 分配 CA，此CA用于向ETCD Client提供ETCD Server合法性的认证


通过ETCD Root CA为ETCD 之间的Peer分配CA，此CA用于ETCD 各member之间进行提供合法性认证

```
           ┌─────────────────────────────────────────────┐          
           │                Cluster Root CA              │          
           └────┬────────────────┬─────────────────┬─────┘          
┌───────────────▼────┐ ┌─────────▼──────────┐ ┌────▼───────────────┐
│    ETCD Peer CA    │ │    ETCD Peer CA    │ │    ETCD Peer CA    │
│   10.138.48.164    │ │   10.138.232.252   │ │    10.138.24.24    │
└────────────────────┘ └────────────────────┘ └────────────────────┘
```

通过ETCD Root CA签发 ETCD Client Parent CA，通过ETCD Client Parent CA，签发所有的ETCD client CA提供 ETCD Server 验证 Client 端合法性认证
```
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐   
   │                                   Cluster Root CA                                          │   
   └─────┬───────────────────┬───────────────────┬───────────────────┬───────────────────┬──────┘   
┌────────▼─────────┐┌────────▼─────────┐┌────────▼─────────┐┌────────▼─────────┐┌────────▼─────────┐
│     Flannel      ││      Calico      ││    Kubernetes    ││     KubeDNS      ││  Other General   │
│  ETCD Client CA  ││  ETCD Client CA  ││  ETCD Client CA  ││  ETCD Client CA  ││  ETCD Client CA  │
└──────────────────┘└──────────────────┘└──────────────────┘└──────────────────┘└──────────────────┘

```
ETCD Server Peer Client CA生成脚本如下:

* ETCD  CA config json生成脚本
```
cat > ../ca/etcd-ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF
```

* ETCD Server CA 生成脚本
```
cat > ../ca/etcd-server-00-ca.json <<EOF
{
    "CN": "etcd-server-00",
    "hosts": ["10.138.48.164"],
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
EOF

cat > ../ca/etcd-server-01-ca.json <<EOF
{
    "CN": "etcd-server-01",
    "hosts": ["10.138.232.252"],
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
EOF

cat > ../ca/etcd-server-02-ca.json <<EOF
{
    "CN": "etcd-server-02",
    "hosts": ["10.138.24.24"],
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=server ../ca/etcd-server-00-ca.json \
    | cfssljson -bare ../ca/etcd-server-00-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=server ../ca/etcd-server-01-ca.json \
    | cfssljson -bare ../ca/etcd-server-01-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=server ../ca/etcd-server-02-ca.json \
    | cfssljson -bare ../ca/etcd-server-02-ca

```

* ETCD Peer CA 生成脚本
```
cat > ../ca/etcd-peer-00-ca.json <<EOF
{
    "CN": "etcd-peer-00",
    "hosts": ["10.138.48.164"],
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
EOF

cat > ../ca/etcd-peer-01-ca.json <<EOF
{
    "CN": "etcd-peer-01",
    "hosts": ["10.138.232.252"],
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
EOF

cat > ../ca/etcd-peer-02-ca.json <<EOF
{
    "CN": "etcd-peer-02",
    "hosts": ["10.138.24.24"],
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=peer ../ca/etcd-peer-00-ca.json \
    | cfssljson -bare ../ca/etcd-peer-00-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=peer ../ca/etcd-peer-01-ca.json \
    | cfssljson -bare ../ca/etcd-peer-01-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=peer ../ca/etcd-peer-02-ca.json \
    | cfssljson -bare ../ca/etcd-peer-02-ca

```


* ETCD Client CA 生成脚本
```
cat > ../ca/etcd-client-calico-ca.json <<EOF
{
    "CN": "etcd-client-calico",
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=client ../ca/etcd-client-calico-ca.json \
    | cfssljson -bare ../ca/etcd-client-calico-ca

cat > ../ca/etcd-client-kubernetes-ca.json <<EOF
{
    "CN": "etcd-client-kubernetes",
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=client ../ca/etcd-client-kubernetes-ca.json \
    | cfssljson -bare ../ca/etcd-client-kubernetes-ca

cat > ../ca/etcd-client-kubedns-ca.json <<EOF
{
    "CN": "etcd-client-kubedns",
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=client ../ca/etcd-client-kubedns-ca.json \
    | cfssljson -bare ../ca/etcd-client-kubedns-ca

cat > ../ca/etcd-client-other-general-ca.json <<EOF
{
    "CN": "etcd-client-other-general",
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/etcd-ca-config.json \
    -profile=client ../ca/etcd-client-other-general-ca.json \
    | cfssljson -bare ../ca/etcd-client-other-general-ca
```

### 生成 Kubernetes 相关证书

#### 生成 Kubernetes kube-apiserver 证书
```
        ┌─────────────────────────────────────────────┐       
        │             Cluster Root CA                 │       
        └─────┬───────────────┬────────────────┬──────┘       
              │               │                │              
┌─────────────▼────┐ ┌────────▼─────────┐ ┌────▼─────────────┐
│ Kube-apiserve CA │ │ Kube-apiserve CA │ │ Kube-apiserve CA │
│  10.138.48.164   │ │  10.138.232.252  │ │   10.138.24.24   │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```
通过Kubernetes Root CA为 Kubernetes 的所有 Kube-apiserve 生成生成证书

生成脚本如下:
```
cat > ../ca/kube-apiserver-ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "kube-apiserver": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            }
        }
    }
}
EOF

cat > ../ca/kube-apiserver-00-ca.json <<EOF
{
    "CN": "kube-apiserver-00",
    "hosts": [
    "10.138.48.164",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "10.138.232.140",
    "10.254.0.1"
    ],
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
EOF

cat > ../ca/kube-apiserver-01-ca.json <<EOF
{
    "CN": "kube-apiserver-01",
    "hosts": [
    "10.138.232.252",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "10.138.232.140",
    "10.254.0.1"],
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
EOF

cat > ../ca/kube-apiserver-02-ca.json <<EOF
{
    "CN": "kube-apiserver-02",
    "hosts": [
    "10.138.24.24",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "10.138.232.140",
    "10.254.0.1"],
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
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/cluster-root-ca-config.json \
    -profile=kube-apiserver ../ca/kube-apiserver-00-ca.json \
    | cfssljson -bare ../ca/kube-apiserver-00-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kube-apiserver-ca-config.json \
    -profile=kube-apiserver ../ca/kube-apiserver-01-ca.json \
    | cfssljson -bare ../ca/kube-apiserver-01-ca

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kube-apiserver-ca-config.json \
    -profile=kube-apiserver ../ca/kube-apiserver-02-ca.json \
    | cfssljson -bare ../ca/kube-apiserver-02-ca

```
> "10.138.232.140" 为HAProxy IP


* Kube-apiserver 要通过HAProxy进行负载均衡，在每个 Kube-apiserver 的证书中需要包含 HAProxy 访问 Kube-apiserver。
* 这里我们没有考虑 proxy 本身的高可用，以及 proxy 的host 改变后，证书的处理问题
* CLUSTER_KUBERNETES_SVC_IP 是我们定义的 kubernetes 服务 IP (预分配，一般是 SERVICE_CIDR 中第一个IP)
* "kubernetes.default.svc.cluster.local" 等几个域名是 Kubernetes 集群内部使用的域名也要加入
* "10.254.0.1" 这个是和后面kube-apiserver 启动参数 '--service-cluster-ip-range' 紧密相关的ip地址通常是'--service-cluster-ip-range' 范围内的第一个ip地址。
* kubernetes.default.svc.cluster.local , service-cluster-ip-range, 等DNS和集群内部访问 kube-apiserver 相关的问题我们在后续文章中再讨论

#### 生成 Kubernetes RBAC 相关core component roles CA

* 在kubernetes 1.6 中 RBAC 已经被全面引入，kube-controller-manager, kube-scheduler, kubelet, kubeproxy 组件也都有其对应的RBAC角色。
* kube-controller-manager, kube-scheduler, kubelet, kubeproxy 组件在 RBAC 中属于 core component roles 。
* 在采用TLS方式进行 组件间通信认证方式时，在kubernetes 中 RBAC 与 CA 的创建紧密相关，RBAC会使用CA 中的 "CN" 对应用户以及角色, 使用"O" 对应所在Group
* kubernetes 中 RBAC 的 Roles and Role Bindings 以及 ClusterRole and ClusterRoleBinding 关系 不在本文的详细说明范围内
* kubernetes RBAC 请参考 [kubernetes RBAC Docs](https://kubernetes.io/docs/admin/authorization/rbac/)
* kubernetes authorization 请参考 [kubernetes authorization Docs](https://kubernetes.io/docs/admin/authorization/)
* kubernetes 1.7 开始将 kubelet 的 RBAC 准备迁移到 node authorization

生成脚本如下:

#### 生成 kube-controller-manager 的 CA 证书
```

               ┌────────────────────────────────────────────────────────────────┐            
               │                       Cluster Root CA                          │            
               └──────┬────────────────────────┬──────────────────────────┬─────┘            
 ┌────────────────────▼───────┐ ┌──────────────▼─────────────┐ ┌──────────▼─────────────────┐
 │ kube-controller-manager CA │ │ kube-controller-manager CA │ │ kube-controller-manager CA │
 │       10.138.48.164        │ │       10.138.232.252       │ │        10.138.24.24        │
 └────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘
```

* kube-controller-manager 的证书实际上是通过 CA 定义RBAC角色赋予组件(kube-controller-manager)对应权限
* kube-apiserver 将提取证书中"CN"作为客户端的用户名，这里是system:kube-controller-manager(系统预置)
* kube-apiserver 预定义的 RBAC Default ClusterRoleBindings 将 system:kube-controller-manager 用户与 system:kube-controller-manager 角色绑定。
* kubernetes RBAC 关于组建的Docs 参考: [kubernetes authorization Docs-Core Component Roles](https://kubernetes.io/docs/admin/authorization/rbac/#core-component-roles)


#### 生成 kube-scheduler 的 CA 证书
```
               ┌────────────────────────────────────────────────────────────────┐            
               │                       Cluster Root CA                          │            
               └──────┬────────────────────────┬──────────────────────────┬─────┘            
                      │                        │                          │                  
 ┌────────────────────▼───────┐ ┌──────────────▼─────────────┐ ┌──────────▼─────────────────┐
 │     kube-scheduler CA      │ │     kube-scheduler CA      │ │     kube-scheduler CA      │
 │       10.138.48.164        │ │       10.138.232.252       │ │        10.138.24.24        │
 └────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘
```
* kube-scheduler 的证书实际上是通过 CA 定义RBAC角色赋予组件(kube-scheduler)对应权限
* kube-apiserver 将提取证书中"CN"作为客户端的用户名，这里是system:kube-scheduler(系统预置)
* kube-apiserver 预定义的 RBAC Default ClusterRoleBindings 将 system:kube-scheduler 用户与 system:kube-scheduler 角色绑定。
* kubernetes RBAC 关于组建的Docs 参考: [kubernetes authorization Docs-Core Component Roles](https://kubernetes.io/docs/admin/authorization/rbac/#core-component-roles)

#### 生成 kubelet 的 CA 证书
```
               ┌────────────────────────────────────────────────────────────────┐            
               │                       Cluster Root CA                          │            
               └─────┬────────────────────────┬──────────────────────────┬──────┘            
                     │                        │                          │                   
┌────────────────────▼───────┐ ┌──────────────▼─────────────┐ ┌──────────▼─────────────────┐
│   kube-kubelet(node) CA    │ │   kube-kubelet(node) CA    │ │   kube-kubelet(node) CA    │
│       10.138.48.164        │ │       10.138.232.252       │ │        10.138.24.24        │
└────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘
```
* kubelet 的证书实际上是通过 CA 定义RBAC角色赋予组件(system:nodes)对应权限
* kube-apiserver 将提取证书中"CN"作为客户端的用户名，这里是system:node:<nodename>(系统预置)
* kube-apiserver 预定义的 RBAC 使用的 ClusterRoleBindings system:nodes 将用户 system:nodes 群组(注意 这里与其他的组件不同是group 不是 user)与 ClusterRole system:node 绑定。
* kubernetes RBAC 关于组建的Docs 参考: [kubernetes authorization Docs-Core Component Roles](https://kubernetes.io/docs/admin/authorization/rbac/#core-component-roles)
* Kubernetes 1.7 已经建议使用 Node authorizer 方式来进行来进行每个Node 节点的 kubelet 授权, 但目前此功能还没有尝试，在这里我们还是使用传统的system:node 方式进行配置
* Kubernetes 1.8 按照官方说法 将开始用Node authorizer 方式作为默认配置，我们会及时跟进
* kubernetes 1.7 Node authorizer 具体官方说明请参考  [kubernetes authorization Docs-Using Node Authorization](https://kubernetes.io/docs/admin/authorization/node/)


#### 生成 kubeproxy 的 CA 证书
```
               ┌────────────────────────────────────────────────────────────────┐            
               │                       Cluster Root CA                          │            
               └─────┬────────────────────────┬──────────────────────────┬──────┘            
┌────────────────────▼───────┐ ┌──────────────▼─────────────┐ ┌──────────▼─────────────────┐
│     kube-kubeproxy CA      │ │     kube-kubeproxy CA      │ │     kube-kubeproxy CA      │
│       10.138.48.164        │ │       10.138.232.252       │ │        10.138.24.24        │
└────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘
```

* kubeproxy 的证书实际上是通过 CA 定义RBAC角色赋予组件(system:kube-proxy)对应权限
* kube-apiserver 将提取证书中"CN"作为客户端的用户名，这里是system:kube-proxy(系统预置)
* kube-apiserver 预定义的 RBAC Default ClusterRoleBindings 将 system:kube-proxy 用户与 system:node-proxier 角色绑定。
* system:node-proxier具有kube-proxy组件访问ApiServer的相关权限。
* kubernetes RBAC 关于组建的Docs 参考: [kubernetes authorization Docs-Core Component Roles](https://kubernetes.io/docs/admin/authorization/rbac/#core-component-roles)

CN 指定该证书的 User为 system:kube-proxy。Kubernetes RBAC定义了ClusterRoleBinding将system:kube-proxy用户与system:node-proxier 角色绑定。system:node-proxier具有kube-proxy组件访问ApiServer的相关权限。


生成 RBAC core component roles 所需的证书:

* 配置 RBAC core component roles CA 对应 config json 文件
```
cat > ../ca/kubernetes-rbac-core-component-roles-ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "kube-controller-manager": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "kube-scheduler": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "kubelet-node": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "kube-proxy": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            }
        }
    }
}
EOF
```

* 配置 RBAC kube-controller-manager 对应 CA 文件
```
#---rbac-kube-controller-manager-00
cat > ../ca/kubernetes-rbac-kube-controller-manager-00-ca.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "hosts": [
        "10.138.48.164"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-controller-manager",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-controller-manager ../ca/kubernetes-rbac-kube-controller-manager-00-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-controller-manager-00-ca

#---rbac-kube-controller-manager-01
cat > ../ca/kubernetes-rbac-kube-controller-manager-01-ca.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "hosts": [
        "10.138.232.252"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-controller-manager",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-controller-manager ../ca/kubernetes-rbac-kube-controller-manager-01-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-controller-manager-01-ca

#---rbac-kube-controller-manager-02
cat > ../ca/kubernetes-rbac-kube-controller-manager-02-ca.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "hosts": [
        "10.138.24.24"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-controller-manager",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-controller-manager ../ca/kubernetes-rbac-kube-controller-manager-02-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-controller-manager-02-ca

```
* 配置 RBAC kube-scheduler 对应 CA 文件
```

cat > ../ca/kubernetes-rbac-kube-scheduler-00-ca.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
        "10.138.48.164"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-scheduler",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-scheduler ../ca/kubernetes-rbac-kube-scheduler-00-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-scheduler-00-ca


#---
cat > ../ca/kubernetes-rbac-kube-scheduler-01-ca.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
        "10.138.232.252"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-scheduler",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-scheduler ../ca/kubernetes-rbac-kube-scheduler-01-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-scheduler-01-ca
#---
cat > ../ca/kubernetes-rbac-kube-scheduler-02-ca.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
        "10.138.24.24"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-scheduler",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kube-scheduler ../ca/kubernetes-rbac-kube-scheduler-02-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-scheduler-02-ca

```
* 配置 RBAC kubelet 在不同 node 的对应 CA 文件
```
cat > ../ca/kubernetes-rbac-kubelet-node-00-ca.json <<EOF
{
    "CN": "system:node:node00",
    "hosts": [
        "10.138.48.164"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:nodes",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kubelet-node-00-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kubelet-node-00-ca
#---
cat > ../ca/kubernetes-rbac-kubelet-node-01-ca.json <<EOF
{
    "CN": "system:node:node01",
    "hosts": [
        "10.138.232.252"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:nodes",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kubelet-node-01-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kubelet-node-01-ca
#---
cat > ../ca/kubernetes-rbac-kubelet-node-02-ca.json <<EOF
{
    "CN": "system:node:node02",
    "hosts": [
        "10.138.24.24"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:nodes",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kubelet-node-02-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kubelet-node-02-ca

```
* 配置 RBAC kube-proxy 在不同 node 的对应 CA 文件
```


cat > ../ca/kubernetes-rbac-kube-proxy-00-ca.json <<EOF
{
    "CN": "system:kube-proxy",
    "hosts": [
        "10.138.48.164"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-proxy",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kube-proxy-00-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-proxy-00-ca
#---
cat > ../ca/kubernetes-rbac-kube-proxy-01-ca.json <<EOF
{
    "CN": "system:kube-proxy",
    "hosts": [
        "10.138.232.252"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-proxy",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kube-proxy-01-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-proxy-01-ca

#---
cat > ../ca/kubernetes-rbac-kube-proxy-02-ca.json <<EOF
{
    "CN": "system:kube-proxy",
    "hosts": [
        "10.138.24.24"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
          "C": "CN",
          "ST": "BeiJing",
          "L": "BeiJing",
          "O": "system:kube-proxy",
          "OU": "System"
        }
    ]
}
EOF

cfssl gencert \
    -ca=../ca/cluster-root-ca.pem \
    -ca-key=../ca/cluster-root-ca-key.pem \
    -config=../ca/kubernetes-rbac-core-component-roles-ca-config.json \
    -profile=kubelet-node ../ca/kubernetes-rbac-kube-proxy-02-ca.json \
    | cfssljson -bare ../ca/kubernetes-rbac-kube-proxy-02-ca
#---


```


### ETCD 部署方式规划
```
                       ┌────────────────────────────────────────────┐                       
                       │┌───────────┐┌────────────────┐┌───────────┐│                       
                       ││ETCD-getway││ETCD-gRPC-Proxy ││ETCD-Proxy ││                       
                       │└───────────┘└────────────────┘└───────────┘│                       
                       │              ┌──────────────┐              │                       
                       │              │    ETCD00    │              │                       
                       │              └──────────────┘              │                       
                       └────────────────────────────────────────────┘                       
┌────────────────────────────────────────────┐┌────────────────────────────────────────────┐
│┌───────────┐┌────────────────┐┌───────────┐││┌───────────┐┌────────────────┐┌───────────┐│
││ETCD-getway││ETCD-gRPC-Proxy ││ETCD-Proxy ││││ETCD-getway││ETCD-gRPC-Proxy ││ETCD-Proxy ││
│└───────────┘└────────────────┘└───────────┘││└───────────┘└────────────────┘└───────────┘│
│              ┌──────────────┐              ││              ┌──────────────┐              │
│              │    ETCD00    │              ││              │    ETCD00    │              │
│              └──────────────┘              ││              └──────────────┘              │
└────────────────────────────────────────────┘└────────────────────────────────────────────┘

```
ETCD的集群部署中为了提高HA能力，官方建议采用通过proxy的方式来进行，ETCDv3 提供了三种Proxy当接入方式:
* 1 ETCD-Proxy 是对原有v2(http/json)的支持，目前Flannel在v0.8.x 还没有对ETCDv3 进行支持，如果容器网络采用Flannel，则需要部署ETCD-Proxy。
* 2 ETCD-gateway  是一个ETCDv3开始提供的 TCP proxy。同时支持v2和v3协议，提供简单的循环策略进行ETCD集群的服务器节点访问。其他高级的加权处理等还没有实现
* 3 ETCD-gRPC-Proxy 这是现在官方最为推荐的Proxy方式。gRPC-Proxy是在gRPC层（L7）上运行的无状态的etcd反向代理。可以水平扩展，并且支持合并API请求等。gRPC-Proxy会在后端多个ETCD服务节点选择一个进行使用，该服务节点会收到gRPC-Proxy所有的服务请求。当gRPC-Proxy选择的节点失效后，会自动选择其他节点


### ETCD CA 布置规划

在部署ETCD集群时启用TLS机制，需要的和ETCD相关的证书如下：
* 每个ETCD 服务器节点都使用相同的Server TLS CA，不区分Server
* 每个ETCD 服务器节点都使用自己的Peer TLS CA，区分不同的Peer
* 其他组件访问 ETCD集群都使用通过ETCD root CA 签发的ETCD Client CA 表明自己的身份
* 需要验证ETCD-gateway ETCD-gRPC-Proxy ETCD-Proxy 是否可以不配置证书 通过Client CA 进行proxy 需要验证

所有其他支持ETCDv3的组件通过ETCD-gRPC-Proxy 访问
```
                   ┌─────────────────────────────────┐                 
                   │┌──────────────┐ ┌──────────────┐│                 
                   ││kube-apiserver│ │    Calico    ││                 
                   ││ ETCD V3 API  │ │ ETCD V3 API  ││                 
                   │└──────────────┘ └──────────────┘│                 
                   │┌──────────────┐ ┌──────────────┐│                 
                   ││   KubeDNS    │ │    Other     ││                 
                   ││ ETCD V3 API  │ │ ETCD V3 API  ││                 
                   │└──────────────┘ └──────────────┘│                 
                   └────────────────▲────────────────┘                 
           ┌────────────────────────┼───────────────────────┐          
┌──────────┴─────────┐   ┌──────────┴─────────┐  ┌──────────┴─────────┐
│┌──────────────────┐│   │┌──────────────────┐│  │┌──────────────────┐│
││ ETCD-gRPC-Proxy  ││   ││ ETCD-gRPC-Proxy  ││  ││ ETCD-gRPC-Proxy  ││
│└──────────────────┘│   │└──────────────────┘│  │└──────────────────┘│
│  ┌──────────────┐  │   │ ┌──────────────┐   │  │  ┌──────────────┐  │
│  │    ETCD00    │  │   │ │    ETCD00    │   │  │  │    ETCD00    │  │
│  └──────────────┘  │   │ └──────────────┘   │  │  └──────────────┘  │
└────────────────────┘   └────────────────────┘  └────────────────────┘

```

### 配置部署 ETCD 集群
规划ETCD 数据目录(etcd集群token 用于区分在同一台host上安装多套etcd 集群的情况,配合--name 配置)，ETCD集群数据持久化保存，目录混乱会不能正常启动。
/var/lib/etcd/[etcd集群token]/[etcd member name]

使用下面的配置启动ETCD。注意：请根据自己的IP和配置的ETCD name 来进行修改
```
cat > ./etcd-config-node00.yml <<EOF

# 当前 ETCD 节点 member 名称
name: 'etcd-00'

# 保存ETCD数据的文件位置，建议使用 (不重复的token)/(etcd member name) 作为路径后缀，避免数据保存混乱
data-dir: '/var/lib/etcd/dec0ac166ff2dbf8eab068ca47decaa4/etcd-00'

# ETCD 保存 wal 数据的文件位置
wal-dir: '/var/lib/etcd/dec0ac166ff2dbf8eab068ca47decaa4/etcd-00/wal-dir'

# 指定有多少事务（transaction）被提交时，触发截取快照保存到磁盘
snapshot-count: 10000

# leader 多久发送一次心跳到 followers。默认值是 100ms
heartbeat-interval: 100

# 重新投票的超时时间，如果 follow 在该时间间隔没有收到心跳包，会触发重新投票，默认为 1000 ms
election-timeout: 1000

# Raise alarms when backend size exceeds the given quota. 0 means use the
# default quota.
quota-backend-bytes: 0

# 和peer通信的地址，比如 http://ip:2380，如果有多个，使用逗号分隔。需要所有节点都能够访问，所以不要使用 localhost！
listen-peer-urls: https://10.138.48.164:2380

# 提供本ETCD节点监听客户端请求的URL列表，多个可以用逗号分开。
listen-client-urls: https://10.138.48.164:2379

# Maximum number of snapshot files to retain (0 is unlimited).
max-snapshots: 5

# Maximum number of wal files to retain (0 is unlimited).
max-wals: 5

# Comma-separated white list of origins for CORS (cross-origin resource sharing).
cors:

# List of this member's peer URLs to advertise to the rest of the cluster.
# The URLs needed to be a comma-separated list.
# 此ETCD member 所在集群的peer网址列表，以向集群的其余节点进行通告。多个URL以逗号分隔。
initial-advertise-peer-urls: https://10.138.48.164:2380

# 对外公告的该节点客户端监听地址，这个值会告诉集群中其他节点，广播给其他ETCD member、proxy成员的客户端URL的列表，多个URL以逗号分隔。请不要设置为localhost。
advertise-client-urls: https://10.138.48.164:2379

# 初始集群节点 member name & peer url 的对应关系描述
# 集群中所有节点的信息，格式为 node1=http://ip1:2380,node2=http://ip2:2380。注意：这里的 node1 是节点的 --name 指定的名字；后面的 ip1:2380 是 --initial-advertise-peer-urls 指定的值
initial-cluster: etcd-00=https://10.138.48.164:2380, etcd-01=https://10.138.232.252:2380, etcd-02=https://10.138.24.24:2380

# 引导etcd集群的初始集群令牌，防止网络环境中其他ETCD集群之间引导配置混乱。
# 创建集群的token，这个值每个集群保持唯一。这样的话，如果你要重新创建集群，即使配置和之前一样，也会再次生成新的集群和节点 uuid；否则会导致多个集群之间的冲突，造成未知的错误
initial-cluster-token: 'etcd-cluster-dec0ac166ff2dbf8eab068ca47decaa4'

# Initial cluster state ('new' or 'existing').
# 初始群集状态('new' or 'existing')，新建集群的时候，这个值为new；假如已经存在的集群，这个值为 existing
initial-cluster-state: 'new'

# Reject reconfiguration requests that would cause quorum loss.
strict-reconfig-check: false

# Accept etcd V2 client requests
enable-v2: true

# Enable runtime profiling data via HTTP server
enable-pprof: true

client-transport-security:


  # Path to the client server TLS cert file.
  # 配置TLS的客户端验证服务器的证书
  cert-file: ../ca/etcd-server-00-ca.pem

  # Path to the client server TLS key file.
  # 配置TLS的客户端验证服务器的证书Key
  key-file: ../ca/etcd-server-00-ca-key.pem

  # Enable client cert authentication.
  # 打开客户端证书验证,客户端证书必须是trusted-ca-file签署的相关可信证书
  client-cert-auth: true

  # Path to the client server TLS trusted CA key file.
  # 验证客户端证书的CA可信证书
  trusted-ca-file: ../ca/etcd-root-ca.pem

  # Client TLS using generated certificates
  auto-tls: false

peer-transport-security:

  # Path to the peer server TLS cert file.
  cert-file: ../ca/etcd-peer-00-ca.pem

  # Path to the peer server TLS key file.
  key-file: ../ca/etcd-peer-00-ca-key.pem

  # Enable peer client cert authentication.
  client-cert-auth: false

  # Path to the peer server TLS trusted CA key file.
  trusted-ca-file: ../ca/etcd-root-ca.pem

  # Peer TLS using generated certificates.
  auto-tls: false

# Enable debug-level logging for etcd.
debug: false

# Specify a particular log level for each etcd package (eg: 'etcdmain=CRITICAL,etcdserver=DEBUG'.
log-package-levels:

# Force to create a new one member cluster.
force-new-cluster: false

EOF

../bin/etcd/etcd --config-file ./etcd-config-node00.yml

```

>(补充验证ETCD gRPC proxy 环节)


## 配置Kubernetes Master HA

> 部署的Master节点集群由Node00, Node01, Node02 三个节点组成，每个节点上部署kube-apiserver,kube-controller-manager,kube-scheduler三个核心组件。 kube-apiserver的3个实例同时提供服务，在其前端部署一个高可用的负载均衡器作为kube-apiserver的地址。 kube-controller-manager和kube-scheduler也是各自3个实例，在同一时刻只能有1个实例工作，这个实例通过选举产生。

```
(下面这些在二进制准备和证书准备时 全部弄好)
将前面生成的 ca.pem, apiserver-key.pem, apiserver.pem, admin.pem, admin-key.pem, controller-manager.pem, controller-manager-key.pem, scheduler-key.pem, scheduler.pem拷贝到各个节点的/etc/kubernetes/pki目录下：

mkdir -p /etc/kubernetes/pki
cp {ca.pem,apiserver-key.pem,apiserver.pem,admin.pem, admin-key.pem, controller-manager.pem, controller-manager-key.pem,scheduler-key.pem, scheduler.pem} /etc/kubernetes/pki

将Kubernetes二进制包解压后kubernetes/server/bin中的kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet拷贝到各节点的/usr/local/bin目录中：

cp {kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} /usr/local/bin/
```

kube-apiserver 启动命令：
```
#cat > ./start-kube-apiserver.sh <<EOF

./bin/kubernetes/server/kube-apiserver \
--apiserver-count=3 \
--advertise-address=${INTERNAL_IP} \
--etcd-servers=${ETCD_ENDPOINTS} \
--etcd-cafile=/opt/ca/root-ca/root-ca.pem \
--etcd-certfile=/opt/ca/etcd-ca/etcd-client.pem \
--etcd-keyfile=/opt/ca/etcd-ca/etcd-client-key.pem \
--storage-backend=etcd3 \
--experimental-bootstrap-token-auth=true \
--token-auth-file=/opt/ca/bin/kubernetes/${kube_bootstrap_tokens_filename} \
--authorization-mode=RBAC \
--kubelet-https=true \
--service-cluster-ip-range=${SERVICE_CIDR} \
--service-node-port-range=${NODE_PORT_RANGE} \
--tls-cert-file=./kubernetes-ca/kubernetes-api-server.pem \
--tls-private-key-file=./kubernetes-ca/kubernetes-api-server-key.pem \
--client-ca-file=./root-ca/root-ca.pem \
--service-account-key-file=./root-ca/root-ca-key.pem \
--allow-privileged=true \
--enable-swagger-ui=true \
--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,ResourceQuota,DefaultTolerationSeconds \
--audit-log-maxage=30 \
--audit-log-maxbackup=3 \
--audit-log-maxsize=100 \
--audit-log-path=/var/log/kubernetes/audit.log \
--v=0

#EOF
```

> 补充使用HAProxy 来对kube-apiserver 进行负载均衡的配置

> 为 kube-controller-manager 和 kube-scheduler 准备作为client 与 kube-apiserver 进行通信使用的kube-config


* 配置 kube-controller-manager 访问 kube-apiserver 的配置文件
```
export KUBE_APISERVER_PROXY="https://10.138.232.140:19999"

../bin/kubernetes/client/kubectl config set-cluster kubernetes \
--certificate-authority="../ca/cluster-root-ca.pem" \
--client-certificate="../ca/kubernetes-rbac-kube-controller-manager-00-ca.pem" \
--client-key="../ca/kubernetes-rbac-kube-controller-manager-00-ca-key.pem" \
--server="${KUBE_APISERVER_PROXY}" \
--embed-certs=true \
--kubeconfig=controller-manager00.conf


# set-cluster
../bin/kubernetes/client/kubectl config set-cluster kubernetes \
--certificate-authority="../ca/cluster-root-ca.pem" \
--embed-certs=true \
--server=${KUBE_APISERVER_PROXY} \
--kubeconfig=controller-manager00.conf

# set-credentials
../bin/kubernetes/client/kubectl config set-credentials system:kube-controller-manager \
--client-certificate="../ca/kubernetes-rbac-kube-controller-manager-00-ca.pem" \
--client-key="../ca/kubernetes-rbac-kube-controller-manager-00-ca-key.pem" \
--embed-certs=true \
--kubeconfig=controller-manager00.conf

# set-context
../bin/kubernetes/client/kubectl config set-context system:kube-controller-manager@kubernetes \
--cluster=kubernetes \
--user=system:kube-controller-manager \
--kubeconfig=controller-manager00.conf


# set default context
../bin/kubernetes/client/kubectl config use-context system:kube-controller-manager@kubernetes --kubeconfig=controller-manager00.conf

```

* kube-controller-manager 的启动配置
```
../bin/kubernetes/server/kube-controller-manager \
--logtostderr=true \
--v=0 \
--master=${KUBE_APISERVER} \
--kubeconfig=./controller-manager00.conf \
--cluster-name=kubernetes \
--cluster-signing-cert-file=../ca/cluster-root-ca.pem \
--cluster-signing-key-file=../ca/cluster-root-ca-key.pem \
--service-account-private-key-file=../ca/cluster-root-ca-key.pem \
--root-ca-file=../ca/cluster-root-ca.pem \
--insecure-experimental-approve-all-kubelet-csrs-for-group=system:bootstrappers \
--use-service-account-credentials=true \
--service-cluster-ip-range=10.254.0.0/16 \
--cluster-cidr=172.30.0.0/16 \
--allocate-node-cidrs=true \
--leader-elect=true \
--controllers=*,bootstrapsigner,tokencleaner
```

* 配置 kube-scheduler 访问 kube-apiserver 的配置文件
```
export KUBE_APISERVER_PROXY="https://10.138.232.140:19999"

../bin/kubernetes/client/kubectl config set-cluster kubernetes \
--certificate-authority="../ca/cluster-root-ca.pem" \
--client-certificate="../ca/kubernetes-rbac-kube-scheduler-00-ca.pem" \
--client-key="../ca/kubernetes-rbac-kube-scheduler-00-ca-key.pem" \
--server="${KUBE_APISERVER_PROXY}" \
--embed-certs=true \
--kubeconfig=./scheduler00.conf


# set-cluster
../bin/kubernetes/client/kubectl config set-cluster kubernetes \
--certificate-authority="../ca/cluster-root-ca.pem" \
--embed-certs=true \
--server=${KUBE_APISERVER_PROXY} \
--kubeconfig=./scheduler00.conf

# set-credentials
../bin/kubernetes/client/kubectl config set-credentials system:kube-scheduler \
--client-certificate="../ca/kubernetes-rbac-kube-scheduler-00-ca.pem" \
--client-key="../ca/kubernetes-rbac-kube-scheduler-00-ca-key.pem" \
--embed-certs=true \
--kubeconfig=./scheduler00.conf

# set-context
../bin/kubernetes/client/kubectl config set-context system:kube-scheduler@kubernetes \
--cluster=kubernetes \
--user=system:kube-scheduler \
--kubeconfig=./scheduler00.conf


# set default context
../bin/kubernetes/client/kubectl \
config use-context system:kube-scheduler@kubernetes \
--kubeconfig=./scheduler00.conf

```

* kube-scheduler 的启动配置

```
../bin/kubernetes/server/kube-scheduler \
--logtostderr=true \
--v=0 \
--master=${kube_api_server_proxy} \
--kubeconfig=./scheduler00.conf \
--leader-elect=true
```

## 配置 Kubernetes Node 节点

### 配置CNI & kubelet
```
wget https://github.com/containernetworking/cni/releases/download/v0.5.2/cni-amd64-v0.5.2.tgz
tar xzf cni-amd64-v0.5.2.tgz
```
ls 可以看到如下文件
bridge  cnitool  dhcp  flannel  host-local  ipvlan  loopback  macvlan  noop  ptp  tuning

配置kubelet
```
<!-- # kube-apiserver haproxy IP
export KUBE_APISERVER_PROXY="https://10.138.232.140:19999"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"
# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."
export HOST_IP="10.138.48.164"

# set-cluster
../bin/kubernetes/client/kubectl config set-cluster kubernetes \
  --certificate-authority=../ca/cluster-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER_PROXY} \
  --kubeconfig=./kubelet00.conf

# set-credentials
../bin/kubernetes/client/kubectl config set-credentials system:node:node00 \
  --client-certificate=../ca/kubernetes-rbac-kubelet-node-00-ca.pem \
  --client-key=../ca/kubernetes-rbac-kubelet-node-00-ca-key.pem \
  --embed-certs=true \
  --kubeconfig=./kubelet00.conf

# set-context
../bin/kubernetes/client/kubectl config set-context system:node:node00@kubernetes \
  --cluster=kubernetes \
  --user=system:node:node00 \
  --kubeconfig=./kubelet00.conf

# set default context
../bin/kubernetes/client/kubectl config use-context system:node:node00@kubernetes --kubeconfig=./kubelet00.conf


../bin/kubernetes/server/kubelet \
--kubeconfig=./kubelet00.conf \
--address=${HOST_IP} \
--hostname-override=${NODE_IP} \
--pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0 \
--experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \

--cluster-dns=${CLUSTER_DNS_SVC_IP} \
--cluster-domain=${CLUSTER_DNS_DOMAIN} \
--require-kubeconfig=true \
--pod-manifest-path=./kubernetes-manifests \
--allow-privileged=true \
--authorization-mode=AlwaysAllow \
--network-plugin=cni \
--logtostderr=true \
--v=0 \ -->

#----------

# kube-apiserver haproxy IP
export KUBE_APISERVER_PROXY="https://10.138.232.140:19999"
export HOST_IP="10.138.48.164"
export BOOTSTRAP_TOKEN="dec0ac166ff2dbf8eab068ca47decaa4"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"
# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# set-cluster
../bin/kubernetes/client/kubectl config set-cluster kubernetes \
  --certificate-authority=../ca/cluster-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER_PROXY} \
  --kubeconfig=./kubelet00.conf

# set-credentials
../bin/kubernetes/client/kubectl config set-credentials system:node:node00 \
  --client-certificate=../ca/kubernetes-rbac-kubelet-node-00-ca.pem \
  --client-key=../ca/kubernetes-rbac-kubelet-node-00-ca-key.pem \
  --embed-certs=true \
  --kubeconfig=./kubelet00.conf

# set-context
../bin/kubernetes/client/kubectl config set-context system:node:node00@kubernetes \
  --cluster=kubernetes \
  --user=system:node:node00 \
  --kubeconfig=./kubelet00.conf

# set default context
../bin/kubernetes/client/kubectl config use-context system:node:node00@kubernetes --kubeconfig=./kubelet00.conf

# 配置集群
../bin/kubernetes/client/kubectl config set-cluster kubernetes \
  --certificate-authority=../ca/cluster-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER_PROXY} \
  --kubeconfig=./bootstrap.kubeconfig

# 配置客户端认证

../bin/kubernetes/client/kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=./bootstrap.kubeconfig


# 配置关联

../bin/kubernetes/client/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=./bootstrap.kubeconfig


# 配置默认关联
../bin/kubernetes/client/kubectl config use-context default --kubeconfig=./bootstrap.kubeconfig

# 启动kubelet
../bin/kubernetes/server/kubelet \
--api-servers==${KUBE_APISERVER_PROXY} \
--address=${HOST_IP} \
--hostname-override=${HOST_IP} \
--pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0 \
--experimental-bootstrap-kubeconfig=./bootstrap.kubeconfig \
--kubeconfig=./kubelet00.conf \
--require-kubeconfig=true \
--cert-dir=./kubelet-ca \
--cluster-dns=${CLUSTER_DNS_SVC_IP} \
--cluster-domain=${CLUSTER_DNS_DOMAIN} \
--pod-manifest-path=./kubernetes-manifests \
--hairpin-mode promiscuous-bridge \
--allow-privileged=true \
--authorization-mode=AlwaysAllow \
--serialize-image-pulls=false \
--network-plugin=cni \
--logtostderr=true \
--v=0 \

```

* --address 不能设置为 127.0.0.1，否则后续 Pods 访问 kubelet 的 API 接口时会失败，因为 Pods 访问的 127.0.0.1 指向自己而不是 kubelet；
* 如果设置了 --hostname-override 选项，则 kube-proxy 也需要设置该选项，否则会出现找不到 Node 的情况；
* --experimental-bootstrap-kubeconfig 指向 bootstrap kubeconfig 文件，kubelet 使用该文件中的用户名和 token 向 kube-apiserver 发送 TLS Bootstrapping 请求；
管理员通过了 CSR 请求后，kubelet 自动在 --cert-dir 目录创建证书和私钥文件(kubelet-client.crt 和 kubelet-client.key)，然后写入 --kubeconfig 文件(自动创建 --kubeconfig 指定的文件)；
* 建议在 --kubeconfig 配置文件中指定 kube-apiserver 地址，如果未指定 --api-servers 选项，则必须指定 --require-kubeconfig 选项后才从配置文件中读取 kue-apiserver 的地址，否则 kubelet 启动后将找不到 kube-apiserver (日志中提示未找到 API Server），kubectl get nodes 不会返回对应的 Node 信息;
* --cluster-dns 指定 kubedns 的 Service IP(可以先分配，后续创建 kubedns 服务时指定该 IP)，--cluster-domain 指定域名后缀，这两个参数同时指定后才会生效；
kubelet cAdvisor 默认在所有接口监听 4194 端口的请求，对于有外网的机器来说不安全，ExecStartPost 选项指定的 iptables 规则只允许内网机器访问 4194 端口；

```

/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
/sbin/iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 4194 -j ACCEPT
/sbin/iptables -A INPUT -s 192.168.0.0/16 -p tcp --dport 4194 -j ACCEPT
/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP

```

>  创建 kube-proxy kubeconfig 文件
```

# kube-apiserver haproxy IP
export KUBE_APISERVER_PROXY="https://10.138.232.140:19999"
export HOST_IP="10.138.48.164"
export BOOTSTRAP_TOKEN="dec0ac166ff2dbf8eab068ca47decaa4"

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用 IP:Port 可达
SERVICE_CIDR="10.254.0.0/16"
# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达 (网络插件 保证)
CLUSTER_CIDR="172.30.0.0/16"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"
# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# 配置集群

../bin/kubernetes/client/kubectl config set-cluster kubernetes \
  --certificate-authority=../ca/cluster-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER_PROXY} \
  --kubeconfig=./kube-proxy00.kubeconfig


# 配置客户端认证

../bin/kubernetes/client/kubectl config set-credentials kube-proxy \
  --client-certificate=../ca/kubernetes-rbac-kube-proxy-00-ca.pem \
  --client-key=../ca/kubernetes-rbac-kube-proxy-00-ca-key.pem \
  --embed-certs=true \
  --kubeconfig=./kube-proxy00.kubeconfig


# 配置关联

../bin/kubernetes/client/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=./kube-proxy00.kubeconfig



# 配置默认关联
../bin/kubernetes/client/kubectl config use-context default --kubeconfig=./kube-proxy00.kubeconfig

../bin/kubernetes/server/kube-proxy \
--bind-address=${HOST_IP} \
--hostname-override=${HOST_IP} \
--cluster-cidr=${SERVICE_CIDR} \
--kubeconfig=./kube-proxy00.kubeconfig \
--logtostderr=true \
--v=0

```

```
# 下载 yaml 文件
wget http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/hosted/calico.yaml
wget http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/rbac.yaml


#修改 calico.yaml 配置

配置etcd
etcd_endpoints: "https://10.6.0.140:2379,https://10.6.0.187:2379,https://10.6.0.188:2379"

#  calico到kubernetes的secrets寻找CA
etcd_ca: "/calico-secrets/etcd-ca"  
etcd_cert: "/calico-secrets/etcd-cert"
etcd_key: "/calico-secrets/etcd-key"  

#  calico 配置 base64 后的 etcd 访问 CA(括号里面是命令，实际粘贴base64 后的CA)
etcd-key: (cat ../ca/etcd-client-calico-ca-key.pem | base64 | tr -d '\n')
etcd-cert: (cat ../ca/etcd-client-calico-ca.pem | base64 | tr -d '\n')
etcd-ca: (cat ../ca/cluster-root-ca.pem | base64 | tr -d '\n')


#  以POD方式启动calico
../bin/kubernetes/client/kubectl \
--certificate-authority="../ca/cluster-root-ca.pem" \
--client-certificate="../ca/kube-apiserver-admin-ca.pem" \
--client-key="../ca/kube-apiserver-admin-ca-key.pem" \
--server="https://10.138.232.140:19999" \
apply -f calico.yaml

# 添加calico的RBAC信息到kubernetes
../bin/kubernetes/client/kubectl \
--certificate-authority="../ca/cluster-root-ca.pem" \
--client-certificate="../ca/kube-apiserver-admin-ca.pem" \
--client-key="../ca/kube-apiserver-admin-ca-key.pem" \
--server="https://10.138.232.140:19999" \
apply -f calico-rbac.yaml

#重新启动 kubelet

```

```
# 国外镜像 有墙
quay.io/calico/node:v1.3.0
quay.io/calico/cni:v1.9.1
quay.io/calico/kube-policy-controller:v0.6.0

如果在国内部署请下载后放到私有仓库，或者其他可访问容器仓库
```

#### 安装 Calicoctl
```
wget https://github.com/projectcalico/calicoctl/releases/download/v1.5.0/calicoctl
chmod +x calicoctl
mkdir /etc/calico

# 创建calicoctl访问ETCD的配置
cat > /etc/calico/calicoctl.cfg <<EOF
apiVersion: v1
kind: calicoApiConfig
metadata:
spec:
  datastoreType: "etcdv3"
  etcdEndpoints: "https://10.6.0.140:2379,https://10.6.0.187:2379,https://10.6.0.188:2379"
  etcdKeyFile: "/opt/kube-deploy/ca/etcd-client-calico-ca-key.pem"
  etcdCertFile: "/opt/kube-deploy/ca/etcd-client-calico-ca.pem"
  etcdCACertFile: "/opt/kube-deploy/ca/cluster-root-ca.pem"
EOF

# 检查calico 的状态
../bin/calico/calicoctl  node status
Calico process is running.

IPv4 BGP status
+----------------+-------------------+-------+----------+-------------+
|  PEER ADDRESS  |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+----------------+-------------------+-------+----------+-------------+
| 10.138.232.252 | node-to-node mesh | up    | 16:02:35 | Established |
| 10.138.24.24   | node-to-node mesh | up    | 16:02:36 | Established |
+----------------+-------------------+-------+----------+-------------+

IPv6 BGP status
No IPv6 peers found.

# 检查 calico 在 kube-system 的配置
../bin/kubernetes/client/kubectl \
--certificate-authority="../ca/cluster-root-ca.pem" \
--client-certificate="../ca/kube-apiserver-admin-ca.pem" \
--client-key="../ca/kube-apiserver-admin-ca-key.pem" \
--server="https://10.138.232.140:19999" \
get ds -n kube-system

```

#### 配置 CoreDNS

CoreDNS 和 KubeDNS 一样，采用 addons 方式来在kubernetes集群内部进行安装
下载 CoreDNS 配置YAML 和 部署脚本
```
wget https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/coredns.yaml.sed
wget https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/coredns-1.6.yaml.sed
wget https://raw.githubusercontent.com/coredns/deployment/master/kubernetes/deploy.sh
```
我们安装的是 kubernetes 1.6 以上的版本，所以使用coredns-1.6.yaml.sed，同时还需要对coredns-1.6.yaml.sed进行修改
```
找到 

kubernetes CLUSTER_DOMAIN {
  cidrs SERVICE_CIDR
}

修改为：
kubernetes CLUSTER_DOMAIN SERVICE_CIDR

这个地方 coredns 不能识别 cidrs 的写法。
```


执行下面的命令 部署coredns
```
./deploy.sh 10.254.0.0/16 cluster.local coredns-1.6.yaml.sed | kubectl apply -f -

kubectl delete --namespace=kube-system deployment kube-dns
```
删除原有 kube-dns 的 deployment 防止和coredns冲突。同时coredns会自己创建名为kube-dns的services


可以通过使用radial/busyboxplus:curl 来测试 DNS 是否已经可以访问

```
kubectl run curl --image=radial/busyboxplus:curl -i --tty

# nslookup kubernetes.default
Server:    10.254.0.2
Address 1: 10.254.0.2 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.254.0.1 kubernetes.default.svc.cluster.local

```


测试部署 kubernetes 官方的guestbook 来测试外网是否可以访问
https://github.com/kubernetes/examples/blob/master/guestbook-go/README.md
在没有对kubernetes进行LoadBalancer原生云支持的cloud上，建议直接使用externalIPs
externalIPs 可以是任意 Node 节点的外网IP
```
guestbook-service.json
{
   "kind":"Service",
   "apiVersion":"v1",
   "metadata":{
      "name":"guestbook",
      "labels":{
         "app":"guestbook"
      }
   },
   "spec":{
      "ports": [
         {
           "port":3000,
           "targetPort":"http-server"
         }
      ],
      "selector":{
         "app":"guestbook"
      },
      "externalIPs": [
        "165.227.12.13"
      ]
   }
}
```

在安装好kubernetes 集群 并配置好CNI网络以及DNS插件后可以使用 Sock Shop 来测试集群
```
git clone -b 0.0.12 https://github.com/microservices-demo/microservices-demo.git

vim ./microservices-demo/deploy/kubernetes/definitions/wholeWeaveDemo.yaml

```
找到front-end 的 Service 修改为externalIPs的方式
```
---
apiVersion: v1
kind: Service
metadata:
  name: front-end
  labels:
    name: front-end
spec:
  type: LoadBalancer
  ports:
  - port: 8888
    targetPort: 8079
  selector:
    name: front-end
  externalIPs:
  - 138.197.196.161
---
```
部署Sock Shop
```
/usr/local/bin/kubernetes.v1.7.8/kubectl \
--certificate-authority="/opt/kube-deploy/ca/cluster-root-ca.pem" \
--client-certificate="/opt/kube-deploy/ca/kube-admin-ca.pem" \
--client-key="/opt/kube-deploy/ca/kube-admin-ca-key.pem" \
--server="https://10.138.232.140:19999" \
create -f kubernetes/definitions/wholeWeaveDemo.yaml
```
查看Sock Shop 外部服务状态
```
/usr/local/bin/kubernetes.v1.7.8/kubectl \
--certificate-authority="/opt/kube-deploy/ca/cluster-root-ca.pem" \
--client-certificate="/opt/kube-deploy/ca/kube-admin-ca.pem" \
--client-key="/opt/kube-deploy/ca/kube-admin-ca-key.pem" \
--server="https://10.138.232.140:19999" \
describe service front-end
```