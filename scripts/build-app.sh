#!/bin/zsh
# Gera dist/WindFree.app (Release, arm64 + x86_64) assinado localmente (ad-hoc) e um .zip.
# Para distribuir a outras pessoas é preciso assinar com Developer ID e notarizar (ver README).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

DERIVED="build/Release"
DIST="dist"
APP="$DIST/WindFree.app"

echo "→ Testes do pacote compartilhado"
swift test --package-path Packages/WindFreeKit --quiet

echo "→ Compilando (Release)"
xcodebuild -project WindFree.xcodeproj -scheme WindFree -configuration Release \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

rm -rf "$DIST"
mkdir -p "$DIST"
ditto "$DERIVED/Build/Products/Release/WindFree.app" "$APP"

echo "→ Assinando (ad-hoc, hardened runtime, sandbox)"
codesign --force --options runtime --timestamp=none \
  --entitlements Apps/macOS/WindFree.entitlements --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"

ditto -c -k --keepParent "$APP" "$DIST/WindFree.zip"

echo "✓ $APP"
echo "  Arquiteturas: $(lipo -archs "$APP/Contents/MacOS/WindFree")"
echo "  Tamanho: $(du -sh "$APP" | cut -f1)"
echo "  Abra pelo Finder ou copie para /Applications."
