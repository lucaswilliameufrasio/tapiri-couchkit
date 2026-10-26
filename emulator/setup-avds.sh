#!/bin/bash
# Baixa imagens Android TV (API 25 = Fire Stick; API 36 = mais recente) e cria os AVDs.
set -e
SDK=$HOME/Android/Sdk; SM=$SDK/cmdline-tools/latest/bin/sdkmanager; AM=$SDK/cmdline-tools/latest/bin/avdmanager
yes | $SM --licenses >/dev/null 2>&1 || true
$SM "system-images;android-25;android-tv;x86" "system-images;android-36;android-tv;x86_64"
echo no | $AM create avd -f -n tv25 -k "system-images;android-25;android-tv;x86" -d tv_1080p
echo no | $AM create avd -f -n tv36 -k "system-images;android-36;android-tv;x86_64" -d tv_1080p
echo "AVDs prontos: tv25, tv36"
