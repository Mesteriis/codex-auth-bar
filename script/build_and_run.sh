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
    VERIFY_PID=""
    cleanup_verify() {
      if [[ -n "$VERIFY_PID" ]] && kill -0 "$VERIFY_PID" 2>/dev/null; then
        kill "$VERIFY_PID" 2>/dev/null || true
        for _ in {1..40}; do
          kill -0 "$VERIFY_PID" 2>/dev/null || return 0
          sleep 0.1
        done
      fi
      return 0
    }
    trap cleanup_verify EXIT INT TERM
    /usr/bin/open -n --env CODEX_HOME="$VERIFY_HOME" "$APP"
    for _ in {1..50}; do
      VERIFY_PID="$(pgrep -f "^${BINARY}$" | head -n 1 || true)"
      [[ -n "$VERIFY_PID" ]] && break
      sleep 0.1
    done
    [[ -n "$VERIFY_PID" ]]
    kill -0 "$VERIFY_PID"
    cleanup_verify
    ! kill -0 "$VERIFY_PID" 2>/dev/null
    trap - EXIT INT TERM
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
