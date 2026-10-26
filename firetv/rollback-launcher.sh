#!/bin/bash
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
# Restaura o launcher original da Amazon
adb -s ${STICK:?defina STICK=ip:5555} shell pm enable com.amazon.tv.launcher
adb -s ${STICK:?defina STICK=ip:5555} shell input keyevent KEYCODE_HOME
