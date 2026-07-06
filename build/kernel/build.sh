#!/bin/sh

O=`dirname $0`
O="`(cd \"$O\" ; O=\`pwd\`; echo \"$O\")`"
echo " O = $O"
export O

(cd "$O/../../src/kernel"
make O="$O" $*
)

