#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly APP_NAME="Dnd_Sheet_Archive"
readonly BINARY_NAME="dnd_sheet_archive"
readonly DESKTOP_ID="dnd-sheet-archive"
readonly OAUTH_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dnd_sheet_archive/google_oauth.env"

case "$(uname -m)" in
  x86_64 | amd64)
    readonly APPIMAGE_ARCH="x86_64"
    readonly FLUTTER_ARCH="x64"
    ;;
  aarch64 | arm64)
    readonly APPIMAGE_ARCH="aarch64"
    readonly FLUTTER_ARCH="arm64"
    ;;
  *)
    printf 'Architettura AppImage non supportata: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

readonly TOOL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dnd_sheet_archive/appimage-tools"
readonly STAGING_DIR="$PROJECT_DIR/build/appimage"
readonly APPDIR="$STAGING_DIR/$APP_NAME.AppDir"
readonly PAYLOAD_DIR="$APPDIR/usr/lib/$BINARY_NAME"
readonly FLUTTER_BUNDLE="$PROJECT_DIR/build/linux/$FLUTTER_ARCH/release/bundle"
readonly DIST_DIR="${APPIMAGE_DIST_DIR:-$PROJECT_DIR/dist}"
readonly VERSION="$(awk '$1 == "version:" { print $2; exit }' "$PROJECT_DIR/pubspec.yaml")"
readonly OUTPUT="$DIST_DIR/$APP_NAME-$VERSION-$APPIMAGE_ARCH.AppImage"

download_tool() {
  local url=$1
  local destination=$2
  if [[ ! -s "$destination" ]]; then
    mkdir -p "$(dirname -- "$destination")"
    printf 'Scarico %s...\n' "$(basename -- "$destination")"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 --silent --show-error "$url" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
      wget -q "$url" -O "$destination"
    else
      printf 'Serve curl o wget per scaricare gli strumenti AppImage.\n' >&2
      exit 1
    fi
  fi
  chmod +x "$destination"
}

run_appimage_tool() {
  if [[ -n "${APPIMAGE_TOOL_RUNNER:-}" ]]; then
    local executable=$1
    shift
    # The AppImage runtime drops its first application argument under QEMU.
    "$APPIMAGE_TOOL_RUNNER" "$executable" __qemu_placeholder__ "$@"
  else
    "$@"
  fi
}

linuxdeploy_bin=${LINUXDEPLOY:-}
if [[ -z "$linuxdeploy_bin" ]]; then
  linuxdeploy_bin=$(command -v linuxdeploy || true)
fi
if [[ -z "$linuxdeploy_bin" ]]; then
  linuxdeploy_bin="$TOOL_CACHE/linuxdeploy-$APPIMAGE_ARCH.AppImage"
  download_tool \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$APPIMAGE_ARCH.AppImage" \
    "$linuxdeploy_bin"
fi

appimagetool_bin=${APPIMAGETOOL:-}
if [[ -z "$appimagetool_bin" ]]; then
  appimagetool_bin=$(command -v appimagetool || true)
fi
if [[ -z "$appimagetool_bin" ]]; then
  appimagetool_bin="$TOOL_CACHE/appimagetool-$APPIMAGE_ARCH.AppImage"
  download_tool \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$APPIMAGE_ARCH.AppImage" \
    "$appimagetool_bin"
fi

cd "$PROJECT_DIR"

if [[ -f "$OAUTH_CONFIG" ]]; then
  # This user-owned file must only contain shell-style KEY=VALUE assignments.
  # shellcheck source=/dev/null
  source "$OAUTH_CONFIG"
fi
if [[ -z "${GOOGLE_WEB_CLIENT_ID:-}" ||
      -z "${GOOGLE_DESKTOP_CLIENT_ID:-}" ||
      -z "${GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]]; then
  printf '%s\n' \
    'Impossibile creare una AppImage: manca la configurazione OAuth Google.' \
    "Definisci GOOGLE_WEB_CLIENT_ID, GOOGLE_DESKTOP_CLIENT_ID e" \
    "GOOGLE_DESKTOP_CLIENT_SECRET in $OAUTH_CONFIG o nell'ambiente." >&2
  exit 1
fi

flutter build linux --release \
  --dart-define="GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID" \
  --dart-define="GOOGLE_DESKTOP_CLIENT_ID=$GOOGLE_DESKTOP_CLIENT_ID" \
  --dart-define="GOOGLE_DESKTOP_CLIENT_SECRET=$GOOGLE_DESKTOP_CLIENT_SECRET" \
  "$@"

rm -rf "$APPDIR"
mkdir -p \
  "$PAYLOAD_DIR" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps" \
  "$DIST_DIR"

cp -a "$FLUTTER_BUNDLE/." "$PAYLOAD_DIR/"
cp "$PROJECT_DIR/packaging/linux/AppRun" "$APPDIR/AppRun"
cp "$PROJECT_DIR/packaging/linux/$DESKTOP_ID.desktop" \
  "$APPDIR/$DESKTOP_ID.desktop"
cp "$PROJECT_DIR/packaging/linux/$DESKTOP_ID.desktop" \
  "$APPDIR/usr/share/applications/$DESKTOP_ID.desktop"
cp "$PROJECT_DIR/web/icons/Icon-512.png" "$APPDIR/$DESKTOP_ID.png"
cp "$PROJECT_DIR/web/icons/Icon-512.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/$DESKTOP_ID.png"
ln -s "$DESKTOP_ID.png" "$APPDIR/.DirIcon"
chmod +x "$APPDIR/AppRun" "$PAYLOAD_DIR/$BINARY_NAME"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APPDIR/$DESKTOP_ID.desktop"
fi

NO_STRIP=1 APPIMAGE_EXTRACT_AND_RUN=1 run_appimage_tool "$linuxdeploy_bin" \
  --appdir "$APPDIR" \
  --executable "$PAYLOAD_DIR/$BINARY_NAME"

rm -f "$OUTPUT"
ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 \
  run_appimage_tool "$appimagetool_bin" \
  "$APPDIR" "$OUTPUT"
chmod +x "$OUTPUT"

printf '\nAppImage creata:\n%s\n' "$OUTPUT"
