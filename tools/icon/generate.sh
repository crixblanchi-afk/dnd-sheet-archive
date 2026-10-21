#!/usr/bin/env bash
# Rigenera le icone Android e quelle per il Play Store dagli SVG di questa
# cartella. Servono rsvg-convert e ImageMagick 7 (magick).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
res="$here/../../android/app/src/main/res"
store="$here/../../packaging/play-store"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

render() { rsvg-convert -w "$2" -h "$2" "$here/$1" -o "$3"; }

# densità:lato del livello adattivo (108 dp):lato dell'icona classica (48 dp)
for entry in mdpi:108:48 hdpi:162:72 xhdpi:216:96 xxhdpi:324:144 xxxhdpi:432:192; do
  IFS=: read -r density layer legacy <<<"$entry"
  dir="$res/mipmap-$density"
  mkdir -p "$dir"
  render background.svg "$layer" "$dir/ic_launcher_background.png"
  render foreground.svg "$layer" "$dir/ic_launcher_foreground.png"
  # Versione monocromatica per le icone a tema di Android 13+.
  render monochrome.svg "$layer" "$dir/ic_launcher_monochrome.png"

  # Icona classica per Android 7: primo piano ingrandito su un quadrato
  # arrotondato, come farebbe il launcher con la versione adattiva.
  big=$((legacy * 108 / 72))
  render background.svg "$big" "$tmp/bg.png"
  render foreground.svg "$big" "$tmp/fg.png"
  radius=$((legacy / 6))
  magick "$tmp/bg.png" "$tmp/fg.png" -composite -gravity center \
    -crop "${legacy}x${legacy}+0+0" +repage \
    \( -size "${legacy}x${legacy}" xc:none -fill white \
       -draw "roundrectangle 0,0,$((legacy - 1)),$((legacy - 1)),$radius,$radius" \) \
    -compose DstIn -composite "$dir/ic_launcher.png"
done

# Icona dello Store: 512×512 a tutto campo, Play applica da sé la maschera.
mkdir -p "$store"
render background.svg 700 "$tmp/bg.png"
render foreground.svg 700 "$tmp/fg.png"
magick "$tmp/bg.png" "$tmp/fg.png" -composite -gravity center \
  -crop 512x512+0+0 +repage -alpha off "$store/icon-512.png"

# Feature graphic 1024×500.
render foreground.svg 560 "$tmp/fg.png"
magick -size 1024x500 radial-gradient:'#9b2b2b-#4a1014' \
  \( "$tmp/fg.png" -crop 400x400+80+80 +repage \) -gravity west \
  -geometry +40+0 -composite \
  -font DejaVu-Serif-Bold -fill '#f4e7c9' -pointsize 54 -gravity west \
  -annotate +450-36 'Sheet Archive 5e' \
  -font DejaVu-Serif -fill '#f6cf6e' -pointsize 28 \
  -annotate +454+36 'Schede personaggio, sempre con te' \
  -alpha off "$store/feature-graphic.png"
