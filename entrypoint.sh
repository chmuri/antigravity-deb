#!/usr/bin/env bash
# entrypoint.sh - Main entrypoint for the Antigravity deb builder and repository daemon
set -euo pipefail

ARCH="${ARCH:-amd64}"
PRODUCT="${PRODUCT:-all}"
BUILD_MODE="${BUILD_MODE:-all}"
CHECK_INTERVAL="${CHECK_INTERVAL:-3600}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
HTTP_PORT="${HTTP_PORT:-8080}"

mkdir -p "$OUTPUT_DIR"

do_check() {
  echo "[INFO] Checking Antigravity versions (arch=$ARCH, product=$PRODUCT, mode=$BUILD_MODE)..."
  python3 /scripts/discover_versions.py --arch "$ARCH" --product "$PRODUCT" --mode "$BUILD_MODE" --output-dir "$OUTPUT_DIR"
}

do_build() {
  local mode="${1:-$BUILD_MODE}"
  echo "[INFO] Running build cycle (mode=$mode, arch=$ARCH, product=$PRODUCT)..."

  # Query versions in JSON format
  local json_res
  json_res="$(python3 /scripts/discover_versions.py --arch "$ARCH" --product "$PRODUCT" --mode "$mode" --output-dir "$OUTPUT_DIR" --json)"

  local build_count=0
  # Parse JSON with python and build each pending version
  while IFS='|' read -r prod ver url; do
    [ -n "$prod" ] || continue
    [ -n "$ver" ] || continue
    [ -n "$url" ] || continue

    echo "[INFO] >>> Building $prod v$ver from $url..."
    if /scripts/build_deb.sh "$prod" "$ver" "$url" "$ARCH" "$OUTPUT_DIR"; then
      build_count=$((build_count + 1))
    else
      echo "[ERROR] Failed building $prod v$ver" >&2
    fi
  done < <(python3 -c "
import json, sys
data = json.loads('''$json_res''')
for prod, items in data.get('products', {}).items():
    for it in items:
        if it.get('needs_build'):
            print(f\"{it['product']}|{it['version']}|{it['url']}\")
")

  if [ "$build_count" -gt 0 ]; then
    echo "[INFO] Built $build_count new packages. Updating APT repository metadata..."
    /scripts/update_repo.sh "$OUTPUT_DIR"
  else
    echo "[INFO] All target packages are already built and up-to-date."
    # Ensure index exists even if no new packages were built this run
    if [ ! -f "$OUTPUT_DIR/Packages.gz" ]; then
      /scripts/update_repo.sh "$OUTPUT_DIR"
    fi
  fi
}

do_watch() {
  echo "=========================================================="
  echo " Antigravity Deb Repository Watcher & Builder Started"
  echo " Target Architecture: $ARCH"
  echo " Target Products:     $PRODUCT"
  echo " Build Mode:          $BUILD_MODE"
  echo " Check Interval:      ${CHECK_INTERVAL}s"
  echo " Output Directory:    $OUTPUT_DIR"
  echo "=========================================================="

  while true; do
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting repository sync check..."
    do_build "$BUILD_MODE" || echo "[WARN] Build iteration encountered errors; retrying next cycle."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cycle finished. Sleeping for ${CHECK_INTERVAL}s..."
    sleep "$CHECK_INTERVAL" &
    wait $!
  done
}

do_serve() {
  echo "[INFO] Starting HTTP server for APT repository on port $HTTP_PORT..."
  do_watch &
  WATCH_PID=$!

  trap 'kill -TERM $WATCH_PID 2>/dev/null || true; exit 0' SIGTERM SIGINT

  python3 -m http.server "$HTTP_PORT" -d "$OUTPUT_DIR" &
  HTTP_PID=$!

  wait $HTTP_PID
}

ACTION="${1:-watch}"

case "$ACTION" in
  check)
    do_check
    ;;
  build)
    do_build "${2:-$BUILD_MODE}"
    ;;
  build-all)
    do_build "all"
    ;;
  build-latest)
    do_build "latest"
    ;;
  watch)
    do_watch
    ;;
  serve)
    do_serve
    ;;
  *)
    # If custom command was passed (e.g. bash), execute it
    exec "$@"
    ;;
esac
