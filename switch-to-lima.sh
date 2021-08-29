#!/bin/bash

apt-get remove arm-mali-400-fbdev-blob

cat mesa-dev-packages.txt | xargs apt-get install -y

echo lima > /etc/modules-load.d/mali.conf
echo "blacklist mali" > /etc/modprobe.d/blacklist-mali.conf
