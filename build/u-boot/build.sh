#!/bin/sh

O=`dirname $0`
O="`(cd \"$O\" ; O=\`pwd\`; echo \"$O\")`"
echo " O = $O"
export O

(cd "$O/../../src/uboot-mainline"
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- O="$O" $*
)

