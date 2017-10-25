#!/usr/bin/env bash

#install cuda
#wget --no-check-certificate http://developer2.download.nvidia.com/compute/cuda/9.0/secure/Prod/local_installers/cuda-repo-rhel7-9-0-local-9.0.176-1.x86_64.rpm
#sudo rpm -ivh cuda-repo-rhel7-9-0-local-9.0.176-1.x86_64.rpm
#mv /var/cuda-repo-9-0-local/*.rpm /data/yum/7/cuda/
#rm -rf /var/cuda-repo-9-0-local
#yum remove -y cuda-repo-rhel7-9-0-local
#cd /data/yum && sudo createrepo 7
sudo yum install kernel-devel-`uname -r` kernel-headers-`uname -r` cuda

#install cudnn
#https://developer.nvidia.com/rdp/cudnn-download
wget http://assets.example.com/cuda/cudnn-9.0-linux-x64-v7.tgz -O /tmp/cudnn-9.0-linux-x64-v7.tgz
cd /tmp && tar -xzvf cudnn-9.0-linux-x64-v7.tgz
sudo cp cuda/include/cudnn.h /usr/local/cuda/include
sudo cp cuda/lib64/libcudnn* /usr/local/cuda/lib64
sudo chmod a+r /usr/local/cuda/include/cudnn.h
rm -rf /tmp/cuda* /tmp/cudnn*


