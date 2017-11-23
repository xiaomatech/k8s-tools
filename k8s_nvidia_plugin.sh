#!/usr/bin/env bash

wget http://yum.meizu.mz/k8s/k8s-device-plugin -O /usr/sbin/k8s-device-plugin
chmod a+x /usr/bin/k8s-device-plugin

nohup /usr/bin/k8s-device-plugin &