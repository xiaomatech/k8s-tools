#!/usr/bin/env bash

echo -ne '

Welcome to AutoTrade !

'>/etc/motd

rm -rf /usr/sbin/aliyun*

chkconfig --del agentwatch

yum install -y epel-release

rpm -ivh https://centos7.iuscommunity.org/ius-release.rpm

yum install -y python36u python36u-devel python36u-pip python36u-lxml python36u-gunicorn python36u-redis python36u-tools

hostnamectl set-hostname autotrade

yum remove -y postfix ius-release iwl*-firmware wpa_supplicant

sed -i 's|#!/usr/bin/python|#! /usr/bin/python2.7|g' /usr/bin/yum
sed -i 's|#! /usr/bin/python|#!/usr/bin/python2.7|g' /usr/libexec/urlgrabber-ext-down
sed -i 's|#Port 22|Port 16120|g' /etc/ssh/sshd_config
sed -i 's|#   Port 22|Port 16120|g' /etc/ssh/ssh_config


rm -rf /usr/bin/python && ln -s /usr/bin/python3.6 /usr/bin/python

rm -rf /usr/bin/pip && ln -s /usr/bin/pip3.6 /usr/bin/pip


curl -s https://raw.githubusercontent.com/xiaomatech/tools/master/talib.sh | bash -s --

echo -ne 'asn1crypto
algocoin
amqp
aniso8601
asn1crypto
attrs
autobahn
Automat
beautifulsoup4
billiard
bleach
cachetools
celery
certifi
cffi
chardet
click
coinmarketcap
constantly
cryptography
dateparser
ecdsa
enum34
Events
Flask
Flask-Cache
Flask-Caching
Flask-Celery-Helper
Flask-OAuthlib
Flask-RESTful
Flask-SQLAlchemy
Flask-SQLAlchemy-Cache
future
gevent
greenlet
grequests
gunicorn
html5lib
hyperlink
idna
incremental
itchat
itsdangerous
Jinja2
Keras
kombu
lxml
Markdown
MarkupSafe
msgpack-python
numpy
oauthlib
pandas
patsy
pip
protobuf
pyasn1
pyasn1-modules
pycoin
pycparser
pymongo
PyMySQL
pyOpenSSL
pypng
PyQRCode
python-binance
python-binance-api
python-dateutil
pytz
PyYAML
redis
regex
requests
requests-cache
requests-oauthlib
ruamel.yaml
scikit-keras
scikit-learn
scikit2pmml
scipy
service-identity
setuptools
simplejson
six
SQLAlchemy
statsmodels
TA-Lib
tache
tensorflow
tensorflow-tensorboard
tushare
Twisted
txaio
tzlocal
urllib3
vine
vnpy
websocket-client
Werkzeug
wheel
wxpy
yapf
zope.interface
'> /tmp/pip.txt

pip install -r /tmp/pip.txt
