#!/bin/bash
# Empaqueta Capri como app de macOS en build/Capri.app.
#
# macOS solo concede micrófono, reconocimiento de voz y accesibilidad a una app con Info.plist y firma;
# lanzado como binario suelto, los permisos se atribuirían a la terminal.
#
# Uso:  tools/empaquetar.sh [--abrir]
# Firma con el certificado "Capri Dev" si existe en el llavero (firma estable: los permisos se
# conservan entre compilaciones); si no, firma ad-hoc (macOS volverá a pedir accesibilidad tras cada build).
set -euo pipefail

cd "$(dirname "$0")/.."
APP=build/Capri.app
IDENTITY="Capri Dev"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/Capri" "$APP/Contents/MacOS/Capri"
cp -R "$BIN/Capri_Capri.bundle" "$APP/Contents/Resources/"
plutil -lint -s "$APP/Contents/Info.plist"

# Sin -v: un certificado autofirmado no figura como "válido" (no lo emite una autoridad), pero firma igual.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Firmada con \"$IDENTITY\""
else
    codesign --force --deep --sign - "$APP"
    echo "Firmada ad-hoc (no hay certificado \"$IDENTITY\" en el llavero)"
fi
codesign --verify --strict "$APP"
echo "Lista: $APP"

if [[ "${1:-}" == "--abrir" ]]; then
    pkill -x Capri 2>/dev/null || true
    sleep 0.5
    open "$APP"
fi
