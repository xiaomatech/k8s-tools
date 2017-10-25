#!/usr/bin/env bash
#修改hostname
hostnamectl set-hostname web1.example.com

#查看当前系统都安装有哪些内核版本
grep "^menuentry" /boot/grub2/grub.cfg | cut -d "'" -f2

#查看当前的内核启动版本
grub2-editenv list

#修改内核启动顺序
grub2-set-default 1
