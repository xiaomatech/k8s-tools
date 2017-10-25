#!/usr/bin/env bash

#install intel daal / intel mkl
#http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12072/l_daal_2018.0.128.tgz
#http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12070/l_mkl_2018.0.128.tgz
#http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12106/l_python2_p_2018.0.022.tgz
#http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12106/l_python3_p_2018.0.022.tgz

if [ ! -d /opt/intel/daal ] ; then
    rm -rf /opt/intel/daal
    wget http://assets.example.com/intel/l_daal_2018.0.128.tgz -O /tmp/l_daal_2018.0.128.tgz
    cd /tmp
    tar -zxvf /tmp/l_daal_2018.0.128.tgz
    cd /tmp/l_daal_2018.0.128
    ./install.sh -s silent.cfg
    rm -rf /tmp/l_daal_*
fi

if [ ! -d /opt/intel/mkl ] ; then
    rm -rf /opt/intel/mkl
    wget http://assets.example.com/intel/l_mkl_2018.0.128.tgz -O /tmp/l_mkl_2018.0.128.tgz
    cd /tmp
    tar -zxvf /tmp/l_mkl_2018.0.128.tgz
    cd /tmp/l_mkl_2018.0.128
    ./install.sh -s silent.cfg
    rm -rf /tmp/l_mkl_*
fi

if [ ! -d /opt/intel/intelpython2 ] ; then
    rm -rf /opt/intel/intelpython2
    wget http://assets.example.com/intel/l_python2_p_2018.0.022.tgz -O /tmp/l_python2_p_2018.0.022.tgz
    cd /tmp
    tar -zxvf /tmp/l_python2_p_2018.0.022.tgz
    cd /tmp/l_python2_p_2018.0.022
    ./install.sh -s silent.cfg
    rm -rf /tmp/l_python2_*
fi

if [ ! -d /opt/intel/intelpython3 ] ; then
    rm -rf /opt/intel/intelpython3
    wget http://assets.example.com/intel/l_python3_p_2018.0.022.tgz -O /tmp/l_python3_p_2018.0.022.tgz
    cd /tmp
    tar -zxvf /tmp/l_python3_p_2018.0.022.tgz
    cd /tmp/l_python3_p_2018.0.022
    ./install.sh -s silent.cfg
    rm -rf /tmp/l_python3_*
fi