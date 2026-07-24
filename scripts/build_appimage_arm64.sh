#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly IMAGE_NAME="dnd-sheet-archive-flutter-arm64:3.41.9"
readonly OAUTH_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dnd_sheet_archive/google_oauth.env"
readonly TOOL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dnd_sheet_archive/appimage-tools"
readonly QEMU_RUNNER="$TOOL_CACHE/qemu-aarch64-static"

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker è necessario per creare la AppImage ARM64.\n' >&2
  exit 1
fi

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
export GOOGLE_WEB_CLIENT_ID GOOGLE_DESKTOP_CLIENT_ID GOOGLE_DESKTOP_CLIENT_SECRET

if ! docker run --rm --platform linux/arm64 alpine:3.22 true \
  >/dev/null 2>&1; then
  printf 'Abilito l\x27emulazione Docker ARM64 tramite QEMU/binfmt...\n'
  docker run --privileged --rm tonistiigi/binfmt:latest --install arm64
fi

mkdir -p "$TOOL_CACHE"
if [[ ! -x "$QEMU_RUNNER" ]]; then
  printf 'Preparo il runner QEMU ARM64 statico...\n'
  qemu_container=$(docker create tonistiigi/binfmt:latest)
  if ! docker cp "$qemu_container:/usr/bin/qemu-aarch64" "$QEMU_RUNNER"; then
    docker rm -f "$qemu_container" >/dev/null
    exit 1
  fi
  docker rm "$qemu_container" >/dev/null
  chmod +x "$QEMU_RUNNER"
fi

docker build \
  --platform linux/arm64 \
  --file "$PROJECT_DIR/packaging/linux/Dockerfile.arm64" \
  --tag "$IMAGE_NAME" \
  "$PROJECT_DIR/packaging/linux"

container_status=0
docker run --rm \
  --platform linux/arm64 \
  --env GOOGLE_WEB_CLIENT_ID \
  --env GOOGLE_DESKTOP_CLIENT_ID \
  --env GOOGLE_DESKTOP_CLIENT_SECRET \
  --env "HOST_UID=$(id -u)" \
  --env "HOST_GID=$(id -g)" \
  --env APPIMAGE_TOOL_RUNNER=/usr/local/bin/qemu-aarch64 \
  --volume "$PROJECT_DIR:/workspace" \
  --volume "$TOOL_CACHE:/root/.cache/dnd_sheet_archive/appimage-tools" \
  --volume "$QEMU_RUNNER:/usr/local/bin/qemu-aarch64:ro" \
  --workdir /workspace \
  "$IMAGE_NAME" \
  bash -lc '
    build_status=0
    # package_config.json contains absolute SDK/cache paths and cannot be
    # shared between the x86 host and the ARM64 build container.
    rm -rf .dart_tool linux/flutter/ephemeral/.plugin_symlinks
    flutter pub get || build_status=$?
    if [[ "$build_status" -eq 0 ]]; then
      ./scripts/build_appimage.sh "$@" || build_status=$?
    fi
    chown -R "$HOST_UID:$HOST_GID" build dist .dart_tool
    if [[ -e .flutter-plugins-dependencies ]]; then
      chown "$HOST_UID:$HOST_GID" .flutter-plugins-dependencies
    fi
    exit "$build_status"
  ' bash "$@" || container_status=$?

# Restore host-specific package paths after the container wrote its ARM64
# package_config.json into the shared workspace.
plugin_links="$PROJECT_DIR/linux/flutter/ephemeral/.plugin_symlinks"
if [[ -d "$plugin_links" ]]; then
  mv -- "$plugin_links" "${plugin_links}.stale.$$"
fi
rm -rf "$PROJECT_DIR/.dart_tool"
(
  cd "$PROJECT_DIR"
  flutter pub get
)

exit "$container_status"
