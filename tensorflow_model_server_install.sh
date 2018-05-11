#!/usr/bin/env bash

bazel_version=0.9.0
wget https://github.com/bazelbuild/bazel/releases/download/$bazel_version/bazel-$bazel_version-installer-linux-x86_64.sh -O bazel-$bazel_version-installer-linux-x86_64.sh
bash ./bazel-$bazel_version-installer-linux-x86_64.sh
source /usr/local/lib/bazel/bin/bazel-complete.bash
export PATH="$PATH:/usr/local/lib/bazel/bin"
yum install -y freetype-devel libcurl-devel gcc-c++ libpng-devel python-devel python-pip numpy zip libzip-devel bzip2-devel jemalloc
git clone --recursive  https://github.com/tensorflow/serving
cd serving
cd tensorflow
./configure
cd ..
bazel build -c opt --config=mkl --copt=-msse4.1 --copt=-msse4.2 --copt=-mavx --copt=-mavx2 --copt=-mfma --copt=-mfpmath=both --copt=-O3 tensorflow_serving/...

ll bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server


# rpm -ivh https://copr-be.cloud.fedoraproject.org/results/croberts/bazel/epel-7-x86_64/00745932-bazel/bazel-0.11.1-1.el7.centos.x86_64.rpm

# rpm -ivh https://copr-be.cloud.fedoraproject.org/results/croberts/tensorflow-model-server/epel-7-x86_64/00751750-tensorflow-model-server/tensorflow-model-server-1.6.0-2.el7.centos.x86_64.rpm
