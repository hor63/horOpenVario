#!/bin/bash

#    This file is part of horOpenVario
#    Copyright (C) 2017-2021  Kai Horstmann <horstmannkai@hotmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

read_input() {
  echo "Choose the display which you are going to connect to the board:
    1: HDMI monitor. Default Cubieboard HW configuration. (default)
    2: 5.7\" Chefree (Texim)
    3: 5.7\" Chefree (Texim) on DS2
    4: 7\" Chefree (Texim)
    5: 7\" Chefree (Texim) on DS2
    6: 7\" Pixel QI
    q: Quit. Do not change the display configuration.
 "
  read x
  if test -z "$x"
  then
    x=1
  fi
}

x=$1

if test -z "$x"
then
  read_input
fi

INPUT_VALID=0

while test $INPUT_VALID = 0
do

    INPUT_VALID=1

    case $x in
    1)
        DTB_FILE=sun7i-a20-cubieboard2.dtb
        ;;
    2)
        DTB_FILE=openvario-57-lvds.dtb
        ;;
    3)
        DTB_FILE=openvario-57-lvds-DS2.dtb
        ;;
    4)
        DTB_FILE=openvario-7-CH070.dtb
        ;;
    5)
        DTB_FILE=openvario-7-CH070-DS2.dtb
        ;;
    6)
        DTB_FILE=openvario-7-PQ070.dtb
        ;;
    q)
        echo "Quitting without change."
        echo "Bye."
        exit 0
        ;;
    *)
        echo "Invalid input \"$x\""
        echo "Please try again.
         "
        INPUT_VALID=0
        read_input
        ;;
    esac

    if test $INPUT_VALID = 1
    then
        pushd /boot > /dev/null || exit 1
        rm -f openvario.dtb
        echo "Linking /boot/$DTB_FILE to /boot/openvario.dtb"
        echo "  as the new device tree"
        ln -s $DTB_FILE openvario.dtb
        popd > /dev/null
    fi

done # while test $INPUT_VALID = 0
