#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/CodexAuthBar.xcodeproj"
SCHEME="CodexAuthBar"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/CodexAuthBar.app"
BINARY="$APP/Contents/MacOS/CodexAuthBar"

pkill -x CodexAuthBar >/dev/null 2>&1 || true

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

open_app() {
  /usr/bin/open -n "$APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "CodexAuthBar"'
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.mesteriis.CodexAuthBar"'
    ;;
  --verify|verify)
    VERIFY_HOME="$ROOT_DIR/build/verify-home"
    mkdir -p "$VERIFY_HOME"
    /usr/bin/open -n --env CODEX_HOME="$VERIFY_HOME" "$APP"
    sleep 2
    pgrep -x CodexAuthBar >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
