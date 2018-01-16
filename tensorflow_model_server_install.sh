#!/usr/bin/env bash

bazel_version=0.9.0
wget https://github.com/bazelbuild/bazel/releases/download/$bazel_version/bazel-$bazel_version-installer-linux-x86_64.sh -O bazel-$bazel_version-installer-linux-x86_64.sh
bash ./bazel-$bazel_version-installer-linux-x86_64.sh
source /usr/local/lib/bazel/bin/bazel-complete.bash
export PATH="$PATH:/usr/local/lib/bazel/bin"
yum install -y freetype-devel libcurl-devel gcc-c++ libpng-devel python-devel python-pip numpy zip libzip-devel bzip2-devel
git clone --recursive  https://github.com/tensorflow/serving
cd serving
cd tensorflow
./configure
cd ..
bazel build -c opt --copt=-msse4.1 --copt=-msse4.2 --copt=-mavx --copt=-mavx2 --copt=-mfma --copt=-O3 tensorflow_serving/...

ll bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server