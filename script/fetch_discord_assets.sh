#!/usr/bin/env bash
# Generates the Discord Rich Presence art-asset PNGs (512x512) for BriskEdit.
# Brand logos are pulled from Devicon (MIT); formats without a real logo get a
# clean lettered tile. Output files are named exactly like the asset keys in
# SourceLanguage.discordAssetKey, so they upload 1:1 to the Discord portal.
#
# Usage: ./script/fetch_discord_assets.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="dist/discord-assets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

CDN="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons"

rasterize() { # svg-file  out-png
  inkscape "$1" --export-type=png --export-filename="$2" -w 512 -h 512 \
    >/dev/null 2>&1
}

# Devicon candidates per key (first one that downloads wins).
devicon() {
  case "$1" in
    c)          echo "c/c-original" ;;
    cpp)        echo "cplusplus/cplusplus-original" ;;
    css)        echo "css3/css3-original" ;;
    dart)       echo "dart/dart-original" ;;
    go)         echo "go/go-original-wordmark go/go-line" ;;
    html)       echo "html5/html5-original" ;;
    java)       echo "java/java-original" ;;
    javascript) echo "javascript/javascript-original" ;;
    kotlin)     echo "kotlin/kotlin-original" ;;
    less)       echo "less/less-plain-wordmark" ;;
    lua)        echo "lua/lua-original" ;;
    markdown)   echo "markdown/markdown-original" ;;
    perl)       echo "perl/perl-original" ;;
    php)        echo "php/php-original" ;;
    python)     echo "python/python-original" ;;
    ruby)       echo "ruby/ruby-original" ;;
    rust)       echo "rust/rust-original rust/rust-plain" ;;
    scss)       echo "sass/sass-original" ;;
    shell)      echo "bash/bash-original" ;;
    swift)      echo "swift/swift-original" ;;
    typescript) echo "typescript/typescript-original" ;;
    yaml)       echo "yaml/yaml-original" ;;
    *)          echo "" ;;
  esac
}

# Lettered-tile fallback label for keys with no good brand logo.
label() {
  case "$1" in
    json) echo "JSON" ;; sql) echo "SQL" ;; toml) echo "TOML" ;;
    xml)  echo "XML" ;;  text) echo "TXT" ;;
    yaml) echo "YAML" ;; ini) echo "INI" ;;
    *)    echo "$1" | tr '[:lower:]' '[:upper:]' | cut -c1-4 ;;
  esac
}

make_tile() { # key  out-png
  local lbl; lbl="$(label "$1")"
  local size=170
  case "${#lbl}" in 2) size=230 ;; 3) size=195 ;; 4) size=155 ;; esac
  cat > "$TMP/tile.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">
  <rect width="512" height="512" rx="96" fill="#2B2D31"/>
  <text x="256" y="276" font-family="Helvetica,Arial,sans-serif"
        font-size="$size" font-weight="700" fill="#FFFFFF"
        text-anchor="middle" dominant-baseline="central">$lbl</text>
</svg>
SVG
  rasterize "$TMP/tile.svg" "$2"
}

KEYS="c cpp css dart go html ini java javascript json kotlin less lua markdown \
perl php python ruby rust scss shell sql swift toml typescript xml yaml text"

echo "Generating Discord assets into $OUT …"
for key in $KEYS; do
  got=""
  for cand in $(devicon "$key"); do
    if curl -fsSL "$CDN/$cand.svg" -o "$TMP/$key.svg" 2>/dev/null; then
      if rasterize "$TMP/$key.svg" "$OUT/$key.png"; then got="devicon:$cand"; break; fi
    fi
  done
  if [ -z "$got" ]; then make_tile "$key" "$OUT/$key.png"; got="tile"; fi
  printf "  %-12s %s\n" "$key" "$got"
done

# BriskEdit large image: downscale the 1024px app logo to 512px.
LOGO="$(find Sources/BriskEdit/Resources/Assets.xcassets/AppIcon.appiconset \
  -iname '*1024x1024@1x.png' | head -1)"
if [ -n "$LOGO" ]; then
  sips -z 512 512 "$LOGO" --out "$OUT/briskedit.png" >/dev/null
  echo "  briskedit    app-logo"
fi

echo "Done. $(find "$OUT" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ') files in $OUT"
