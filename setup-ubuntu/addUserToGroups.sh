#!/bin/bash

who am i | while read i k m
do
sudo usermod -a -G input,video,dialout $i
done

