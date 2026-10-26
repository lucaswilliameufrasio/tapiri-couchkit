#!/bin/bash
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
# uso: ./apply.sh [disable|enable]   (defina STICK=ip:5555)
A="adb -s ${STICK:?defina STICK=ip:5555}"; cd "$(dirname "$0")"
if [ "${1:-disable}" = enable ]; then
  while read p; do $A shell pm enable "$p"; done < debloat-list.txt
  $A shell 'settings put global window_animation_scale 1; settings put global transition_animation_scale 1; settings put global animator_duration_scale 1'
else
  while read p; do $A shell pm disable-user --user 0 "$p"; done < debloat-list.txt
  $A shell 'settings put global window_animation_scale 0.5; settings put global transition_animation_scale 0.5; settings put global animator_duration_scale 0.5'
fi
