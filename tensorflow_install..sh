#!/usr/bin/env bash

if [ ! -f /dev/nvidiactl ] ; then
    pip install tensorflow
elif:
    pip install tensorflow-gpu
fi