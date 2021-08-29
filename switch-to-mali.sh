#!/bin/bash

cat mesa-dev-packages.txt | xargs apt-get remove -y

apt-get autoremove -y
    
dpkg -i mali-deb-R8P1.deb

echo mali > /etc/modules-load.d/mali.conf
echo "blacklist lima" > /etc/modprobe.d/blacklist-mali.conf
