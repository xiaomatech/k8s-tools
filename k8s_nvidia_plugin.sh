#!/usr/bin/env bash

wget http://yum.meizu.mz/k8s/k8s-device-plugin -O /usr/bin/k8s-device-plugin
chmod a+x /usr/bin/k8s-device-plugin


mkdir /var/lib/kubelet/device-plugins
chown -R kube:kube /var/lib/kubelet

nohup /usr/bin/k8s-device-plugin &