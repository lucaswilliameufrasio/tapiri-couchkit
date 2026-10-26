#!/bin/bash
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
# uso: firetv/install-app.sh app.apk [outro.apk ...]   (defina STICK=ip:5555)
# Instala ou atualiza apps de fora da loja mantendo o ícone no launcher oficial da Amazon.
# Com "adb install -r" o Appstore da Amazon não atualiza o registro do app e o tile fica
# genérico ("cannot update entry for package"). Desinstalar com -k (mantém dados) e instalar
# de novo recria o registro, sem perder tokens, favoritos nem configurações.
set -euo pipefail
A="adb -s ${STICK:?defina STICK=ip:5555}"
AAPT2=$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
[ -n "$AAPT2" ] || { echo "aapt2 não encontrado (defina ANDROID_HOME)"; exit 1; }
for apk in "$@"; do
  pkg=$("$AAPT2" dump packagename "$apk")
  if $A shell pm list packages "$pkg" | grep -q "package:$pkg\$"; then
    $A shell pm uninstall -k "$pkg" >/dev/null
  fi
  echo "$pkg: $($A install "$apk" 2>&1 | tail -1)"
done
