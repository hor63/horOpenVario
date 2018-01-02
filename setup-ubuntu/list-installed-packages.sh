#!/bin/sh

apt list --installed 2>/dev/null | fgrep "[installed]" | sed -e "s/\\([^\\/]*\\)\\/.*/\\1/" | sort | uniq

