#!/usr/bin/env bash
# Measures the launch request for a generated large text file.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${BRISKEDIT_APP_PATH:-dist/BriskEdit.app}"
SIZE_MB="${BRISKEDIT_BENCHMARK_SIZE_MB:-100}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH does not exist; run ./script/build_and_run.sh build-only first" >&2
  exit 1
fi

BENCH_DIR="$(mktemp -d)"
trap 'rm -rf "$BENCH_DIR"' EXIT
BENCH_FILE="$BENCH_DIR/large-file.txt"

dd if=/dev/zero of="$BENCH_FILE" bs=1m count="$SIZE_MB" 2>/dev/null
tr '\0' 'x' < "$BENCH_FILE" > "$BENCH_FILE.tmp"
mv "$BENCH_FILE.tmp" "$BENCH_FILE"

echo "Opening ${SIZE_MB} MiB file with $APP_PATH"
/usr/bin/time -p /usr/bin/open -n -a "$APP_PATH" "$BENCH_FILE"

# Keep the generated file alive long enough for Launch Services to deliver the
# open event and for the app to read it asynchronously.
sleep "${BRISKEDIT_BENCHMARK_SETTLE_SECONDS:-5}"
