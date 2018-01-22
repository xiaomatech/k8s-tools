#!/usr/bin/env bash

wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz -O /tmp/ta-lib-0.4.0-src.tar.gz
cd /tmp && tar -zxvf ta-lib-0.4.0-src.tar.gz
cd ta-lib && ./configure --prefix=/usr && make && make install
