#!/bin/bash

yum update -y --nogpgcheck
yum install https://centos7.iuscommunity.org/ius-release.rpm -y --nogpgcheck
yum install epel-release rpm-build yum-utils python35u python35u-devel python35u-pip -y --nogpgcheck
pip3.5 install --upgrade pip