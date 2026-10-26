#!/bin/bash
# baixa as libs de terceiros (Apache-2.0) usadas pelo build: zxing e media3 (so o HomeCam)
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p lib/media3; cd lib
M=https://repo1.maven.org/maven2; G=https://dl.google.com/android/maven2/androidx/media3; V=1.3.1
[ -f zxing-core.jar ] || curl -fsSLo zxing-core.jar $M/com/google/zxing/core/3.5.3/core-3.5.3.jar
cd media3
for m in media3-common media3-exoplayer media3-exoplayer-hls media3-exoplayer-rtsp media3-datasource media3-decoder media3-extractor media3-container media3-database; do
  [ -f $m-$V.jar ] && continue
  curl -fsSLo $m.aar $G/$m/$V/$m-$V.aar; unzip -qo $m.aar classes.jar -d t; mv t/classes.jar $m-$V.jar; rm -rf t $m.aar
done
[ -f guava.jar ] || curl -fsSLo guava.jar $M/com/google/guava/guava/32.1.3-android/guava-32.1.3-android.jar
[ -f failureaccess.jar ] || curl -fsSLo failureaccess.jar $M/com/google/guava/failureaccess/1.0.2/failureaccess-1.0.2.jar
[ -f annotation.jar ] || curl -fsSLo annotation.jar https://dl.google.com/android/maven2/androidx/annotation/annotation-jvm/1.8.0/annotation-jvm-1.8.0.jar
echo ok
