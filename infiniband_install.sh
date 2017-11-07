#!/usr/bin/env bash

yum install -y rdma libibverbs libmlx5 libmlx4 infinipath-psm librdmacm-utils librdmacm ibacm infiniband-diags libibverbs-utils opensm

systemctl enable rdma