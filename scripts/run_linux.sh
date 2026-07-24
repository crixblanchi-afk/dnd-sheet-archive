#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dnd_sheet_archive"
readonly OAUTH_CONFIG="$CONFIG_DIR/google_oauth.env"
readonly PLUGIN_SYMLINKS_DIR="$PROJECT_DIR/linux/flutter/ephemeral/.plugin_symlinks"

if [[ -f "$OAUTH_CONFIG" ]]; then
  # This user-owned file must only contain shell-style KEY=VALUE assignments.
  # shellcheck source=/dev/null
  source "$OAUTH_CONFIG"
fi

if [[ -z "${GOOGLE_WEB_CLIENT_ID:-}" ||
      -z "${GOOGLE_DESKTOP_CLIENT_ID:-}" ||
      -z "${GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]]; then
  printf '%s\n' \
    'Manca la configurazione OAuth Google per Linux.' \
    "Definisci GOOGLE_WEB_CLIENT_ID, GOOGLE_DESKTOP_CLIENT_ID e" \
    "GOOGLE_DESKTOP_CLIENT_SECRET in $OAUTH_CONFIG o nell'ambiente." >&2
  exit 1
fi

cd "$PROJECT_DIR"

# Flutter's generated plugin links can survive a build run as another user
# (for example from a root-owned container) and keep pointing at that user's
# pub cache. Move the generated directory aside so Flutter can recreate it for
# the current user. Renaming works even when the directory itself is not
# writable, as long as its generated parent belongs to the current user.
stale_plugin_links=false
if [[ -d "$PLUGIN_SYMLINKS_DIR" ]]; then
  if [[ ! -w "$PLUGIN_SYMLINKS_DIR" ]]; then
    stale_plugin_links=true
  else
    shopt -s nullglob
    for link in "$PLUGIN_SYMLINKS_DIR"/*; do
      if [[ -L "$link" && ! -e "$link" ]]; then
        stale_plugin_links=true
        break
      fi
    done
    shopt -u nullglob
  fi
fi

if [[ "$stale_plugin_links" == true ]]; then
  stale_dir="${PLUGIN_SYMLINKS_DIR}.stale.$$"
  printf 'Rigenerazione dei collegamenti Flutter obsoleti...\n' >&2
  mv -- "$PLUGIN_SYMLINKS_DIR" "$stale_dir"
fi

exec flutter run -d linux \
  --dart-define="GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID" \
  --dart-define="GOOGLE_DESKTOP_CLIENT_ID=$GOOGLE_DESKTOP_CLIENT_ID" \
  --dart-define="GOOGLE_DESKTOP_CLIENT_SECRET=$GOOGLE_DESKTOP_CLIENT_SECRET" \
  "$@"
