#!/usr/bin/env bash

export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

wget https://dl.eff.org/certbot-auto -O /usr/sbin/certbot-auto
chmod a+x /usr/sbin/certbot-auto

#把同一个域名的多个站点，生成到一个证书里面
/usr/sbin/certbot-auto certonly --email user@example.com  --agree-tos --no-eff-email --webroot \
-w /data/www/study.example.com/dist/ -d study.example.com \
-w /data/www/study-api.example.com/public/api/ -d study-api.example.com \
-w /data/www/study-api.example.com/public/sapi/ -d study-teacher-api.example.com \
-w /data/www/study-teacher.example.com/dist/ -d study-teacher.example.com \
-w /data/www/study-admin.example.com/dist/ -d study-admin.example.com \
-w /data/www/study-api.example.com/public/adminapi/ -d study-admin-api.example.com \
-w /data/www/www.example.com/dist/ -d www.example.com \
-w /data/www/api.example.com/public/api -d api.example.com

#默认情况下，let's encripty 会把pem文件生成到/etc/letsencript/live/domain下面

#配置 certbot 自动更新证书
/usr/sbin/certbot-auto renew --quite --post-hook "/etc/init.d/nginx reload"
