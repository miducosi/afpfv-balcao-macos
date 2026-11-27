#!/usr/bin/env bash
# Compila a versão Release (universal) em build/Release/BalcaoVindimas.app.
#   scripts/build-release.sh                 # assinatura automática (equipa do Xcode)
#   SIGN=adhoc scripts/build-release.sh      # sem conta Apple (só para este Mac)
# Os valores do ambiente vêm de Config/Secrets.xcconfig.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Config/Secrets.xcconfig ] || { echo "Falta Config/Secrets.xcconfig (ver Secrets.example.xcconfig)." >&2; exit 1; }
EXTRA=()
[ "${SIGN:-}" = adhoc ] && EXTRA=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
xcodebuild -project BalcaoVindimas.xcodeproj -scheme BalcaoVindimas -configuration Release \
  -derivedDataPath build/DerivedData ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${EXTRA[@]}" build | tail -3
rm -rf build/Release && mkdir -p build/Release
cp -R build/DerivedData/Build/Products/Release/BalcaoVindimas.app build/Release/
echo "✓ build/Release/BalcaoVindimas.app"
