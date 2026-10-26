#!/bin/bash
# uso: ./build.sh <app>  -> gera out/<app>.apk (apps: phonebro firehome stickhub phonecast stickclock homecam)
set -euo pipefail
cd "$(dirname "$0")"
APP=$1; BT=$HOME/Android/Sdk/build-tools/36.0.0; JAR=$HOME/Android/Sdk/platforms/android-34/android.jar
OUT=out/$APP; rm -rf "$OUT"; mkdir -p "$OUT/res" "$OUT/cls"
[ -f debug.keystore ] || keytool -genkeypair -keystore debug.keystore -storepass android -keypass android -alias k -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=lucas" >/dev/null 2>&1
$BT/aapt2 compile --dir $APP/res -o "$OUT/res.zip"
LINK=(link -o "$OUT/base.apk" -I $JAR --manifest $APP/AndroidManifest.xml --min-sdk-version 22 --target-sdk-version 34 "$OUT/res.zip")
[ -d $APP/assets ] && LINK+=(-A $APP/assets)
$BT/aapt2 "${LINK[@]}"
CP=$JAR:lib/zxing-core.jar
EXTRA=(); [ $APP = homecam ] && EXTRA=(lib/media3/*.jar) && CP=$CP:$(printf "%s:" lib/media3/*.jar)
javac --release 8 -Xlint:-options -cp $CP -d "$OUT/cls" $(find $APP/src -name '*.java')
LIBS=(lib/zxing-core.jar "${EXTRA[@]}")
$BT/d8 --min-api 22 --lib $JAR --output "$OUT" $(find "$OUT/cls" -name '*.class') "${LIBS[@]}"
cp "$OUT/base.apk" "$OUT/un.apk"; (cd "$OUT" && zip -q -j un.apk classes.dex)
$BT/zipalign -f 4 "$OUT/un.apk" "$OUT/al.apk"
$BT/apksigner sign --ks debug.keystore --ks-pass pass:android --out out/$APP.apk "$OUT/al.apk"
echo built out/$APP.apk
