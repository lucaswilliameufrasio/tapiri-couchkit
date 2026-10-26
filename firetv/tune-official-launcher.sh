#!/bin/bash
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
# uso: ./tune-official-launcher.sh [apply|revert]   (defina STICK=ip:5555)
A="adb -s ${STICK:?defina STICK=ip:5555}"
if [ "${1:-apply}" = revert ]; then V=(0 0 0 1 1 1 1 1 1)  # valores originais
else V=(1 1 1 0 0 0 0 0 0); fi
$A shell "settings put secure limit_ad_tracking ${V[0]}
settings put secure non_amz_limit_ad_tracking ${V[1]}
settings put secure amz_limit_ad_tracking ${V[2]}
settings put secure advertisingIdApp:interestBasedAds:value $([ ${V[3]} = 0 ] && echo 0 || echo 1)
settings put secure USAGE_METRICS_UPLOAD_ENABLED ${V[3]}
settings put secure usage_metrics_marketing_enabled ${V[4]}
settings put secure settingsApp:appUsageData:value ${V[5]}
settings put secure settingsApp:deviceUsageData:value ${V[6]}
settings put secure screensaver_enabled ${V[7]}"
if [ "${1:-apply}" = apply ]; then
  $A shell pm trim-caches 999G
  for p in com.amazon.tv.launcher com.amazon.tv.settings.v2; do $A shell cmd package compile -m speed -f $p; done
fi
