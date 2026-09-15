#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
/usr/bin/python3 install.py
printf '\n按回车关闭窗口。'
read -r
