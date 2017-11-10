#!/bin/sh

O=`dirname $0`
O="`(cd \"$O\" ; O=\`pwd\`; echo \"$O\")`"
echo " O = $O"
export O

(cd "$O/../../src/kernel"
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- O="$O" $*
)

