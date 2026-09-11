#!/usr/bin/env bash
# Build the Sparkle ZIP + appcast for the current BRISKEDIT_VERSION.
#
# Inputs (env):
#   BRISKEDIT_VERSION                 required
#   BRISKEDIT_BUILD                   optional for stable/beta (version-derived),
#                                     required for nightly
#   BRISKEDIT_UPDATE_CHANNEL          optional, "stable" (default), "beta" or "nightly"
#   BRISKEDIT_SPARKLE_PRIVATE_KEY     required for signing
#   BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX required, e.g. https://github.com/jx-grxf/BriskEdit/releases/download/v0.1.0
#   BRISKEDIT_RELEASE_NOTES_FILE      optional, defaults to RELEASE_NOTES.md; its
#                                     topmost section becomes the update summary
#
# Output (zip name from script/release_artifacts.sh):
#   dist/sparkle/BriskEdit-<version>.zip, or BriskEdit-Nightly-<build>.zip
#   dist/sparkle/appcast.xml
set -euo pipefail

cd "$(dirname "$0")/.."

: "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
: "${BRISKEDIT_SPARKLE_PRIVATE_KEY:?BRISKEDIT_SPARKLE_PRIVATE_KEY is required}"
: "${BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX:?BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX is required}"

CHANNEL="${BRISKEDIT_UPDATE_CHANNEL:-stable}"
if [[ "$CHANNEL" == "nightly" ]]; then
  BUILD="${BRISKEDIT_BUILD:?nightly builds require BRISKEDIT_BUILD}"
  [[ "$BUILD" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "error: nightly build must be a single integer below 10000" >&2; exit 1; }
else
  BUILD="${BRISKEDIT_BUILD:-$(./script/release_build_number.sh "$BRISKEDIT_VERSION")}"
fi
[[ "$BUILD" =~ ^[1-9][0-9]{0,3}(\.[0-9]{1,2}){0,2}$ ]] || { echo "error: Sparkle build must be a numeric CFBundleVersion" >&2; exit 1; }
APP_NAME="$(./script/release_artifacts.sh app-name)"
APP_BUNDLE="$(./script/release_artifacts.sh app-bundle)"
ZIP_NAME="$(./script/release_artifacts.sh zip)"
NOTES_FILE="${BRISKEDIT_RELEASE_NOTES_FILE:-RELEASE_NOTES.md}"

if [[ ! -d "dist/$APP_BUNDLE" ]]; then
  echo "error: dist/$APP_BUNDLE not found — run script/package_dmg.sh first" >&2
  exit 1
fi

INFO="dist/$APP_BUNDLE/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" == "$BRISKEDIT_VERSION" ]] || { echo "error: bundle version differs from appcast version" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")" == "$BUILD" ]] || { echo "error: bundle build differs from appcast build" >&2; exit 1; }
MINIMUM_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
[[ "$MINIMUM_SYSTEM" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "error: invalid minimum system version" >&2; exit 1; }
./script/verify_release_metadata.sh

mkdir -p dist/sparkle
ZIP="dist/sparkle/$ZIP_NAME"
rm -f "$ZIP"

# Sparkle expects a flat zip with the app bundle at the root.
(cd dist && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "sparkle/$ZIP_NAME")

# Locate Sparkle's EdDSA sign_update binary. It ships as an SPM binary artifact
# (.../SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update). The legacy
# old_dsa_scripts/sign_update next to it produces DSA, not EdDSA — exclude it.
DERIVED_DATA="${BRISKEDIT_DERIVED_DATA:-$PWD/.build/release-derived-data}"

find_sign_update() {
  local root sign
  for root in \
    "$DERIVED_DATA/SourcePackages/artifacts" \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    "$HOME/Library/Caches/org.swift.swiftpm"; do
    [[ -d "$root" ]] || continue
    sign="$(find "$root" -type f -name sign_update 2>/dev/null | grep -v old_dsa_scripts | head -n 1 || true)"
    if [[ -n "$sign" ]]; then
      printf '%s' "$sign"
      return 0
    fi
  done
  return 1
}

SIGN_UPDATE="$(find_sign_update || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle EdDSA sign_update binary not found — run script/package_dmg.sh first so SPM resolves Sparkle" >&2
  exit 1
fi

KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$BRISKEDIT_SPARKLE_PRIVATE_KEY" > "$KEY_FILE"

# sign_update prints e.g.: sparkle:edSignature="…" length="12345"
# Extract just the signature so we don't emit a duplicate length attribute below.
SIGNATURE_LINE="$("$SIGN_UPDATE" "$ZIP" -f "$KEY_FILE")"
ED_SIGNATURE="$(printf '%s' "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIGNATURE" ]]; then
  echo "error: could not parse edSignature from sign_update output: $SIGNATURE_LINE" >&2
  exit 1
fi
LENGTH="$(stat -f%z "$ZIP")"
PUBDATE="$(LC_ALL=en_US date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DOWNLOAD_URL="${BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX%/}/$ZIP_NAME"

# Build a concise HTML release-notes summary for the Sparkle update dialog from
# the topmost (current) version section of the notes file — headings + bullet
# highlights only, so the prompt stays short. Embedded inline as <description>;
# the enclosure's edSignature still covers only the ZIP, so this needs no signing.
DESCRIPTION_HTML=""
if [[ -f "$NOTES_FILE" ]]; then
  DESCRIPTION_HTML="$(perl -0777 -ne '
    if (/^##[ ].*?\n(.*?)(?=^##[ ]|\z)/ms) {
      my $body = $1; my @out; my $inlist = 0;
      for my $line (split /\n/, $body) {
        if ($line =~ /^###\s+(.+?)\s*$/) {
          my $h = $1; next if $h =~ /^Compatibility/i;
          push @out, "</ul>" if $inlist; $inlist = 0;
          $h =~ s/&/&amp;/g; $h =~ s/</&lt;/g; $h =~ s/>/&gt;/g;
          push @out, "<h4>$h</h4>";
        } elsif ($line =~ /^[-*]\s+(.+?)\s*$/) {
          my $t = $1;
          # Keep only the bold lead-in as a concise highlight; this also avoids
          # truncation from soft-wrapped bullet continuation lines.
          $t = $1 if $t =~ /^\*\*(.+?)\*\*/;
          $t =~ s/\s*[.:]\s*$//;
          $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g;
          $t =~ s/`(.+?)`/<code>$1<\/code>/g;
          push @out, "<ul>" unless $inlist; $inlist = 1;
          push @out, "<li>$t</li>";
        }
      }
      push @out, "</ul>" if $inlist;
      print join("", @out);
    }
  ' "$NOTES_FILE")"
fi
DESCRIPTION_BLOCK=""
if [[ -n "$DESCRIPTION_HTML" ]]; then
  DESCRIPTION_BLOCK="      <description><![CDATA[${DESCRIPTION_HTML}]]></description>"
fi

# Sparkle best practice: only PRE-RELEASE builds carry a channel tag. Stable
# builds go on the *default* channel (no tag), which every client — including
# users opted into the beta channel — always sees. That's what lets beta testers
# roll forward onto a newer stable release automatically. Nightly items carry
# "nightly" even though only the nightly app reads that feed, so a release build
# pointed at it by mistake would still see nothing.
CHANNEL_BLOCK=""
if [[ "$CHANNEL" != "stable" ]]; then
  CHANNEL_BLOCK="      <sparkle:channel>${CHANNEL}</sparkle:channel>"
fi

cat > dist/sparkle/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BriskEdit</title>
    <link>https://github.com/jx-grxf/BriskEdit</link>
    <description>BriskEdit ${CHANNEL} update feed</description>
    <language>en</language>
    <item>
      <title>${APP_NAME} ${BRISKEDIT_VERSION}</title>
${DESCRIPTION_BLOCK}
${CHANNEL_BLOCK}
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${BRISKEDIT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM}</sparkle:minimumSystemVersion>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

echo "Wrote $ZIP"
echo "Wrote dist/sparkle/appcast.xml"
