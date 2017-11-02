#!/usr/bin/env bash

if [ ! -f /usr/bin/cfssl ] ; then
    wget http://yum.meizu.mz/k8s/cfssl -O /usr/bin/cfssl
    chmod a+x /usr/bin/cfssl
fi


if [ ! -f /usr/bin/cfssl-certinfo ] ; then
    wget http://yum.meizu.mz/k8s/cfssl-certinfo -O /usr/bin/cfssl-certinfo
    chmod a+x /usr/bin/cfssl-certinfo
fi


if [ ! -f /usr/bin/cfssljson ] ; then
    wget http://yum.meizu.mz/k8s/cfssljson -O /usr/bin/cfssljson
    chmod a+x /usr/bin/cfssljson
fi