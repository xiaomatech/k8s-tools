#!/usr/bin/env bash

if [ ! -f /usr/bin/helm ] ; then
    wget http://assets.example.com/k8s/helm -O /usr/bin/helm
    chmod a+x /usr/bin/helm
fi

kubectl apply -f helm-admin.yaml

helm init

helm search nginx