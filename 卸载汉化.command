#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
/usr/bin/python3 install.py --uninstall
printf '\n按回车关闭窗口。'
read -r
