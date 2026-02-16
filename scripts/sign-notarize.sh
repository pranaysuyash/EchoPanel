#!/usr/bin/env bash
set -euo pipefail

# EchoPanel signing + notarization helper.
#
# Default mode is dry-run to avoid accidental signing on developer machines.
# Usage examples:
#   scripts/sign-notarize.sh --app dist/EchoPanel.app
#   scripts/sign-notarize.sh --run --app dist/EchoPanel.app
#   scripts/sign-notarize.sh --run --app dist/EchoPanel.app --dmg dist/EchoPanel-0.2.0.dmg
#
# Recommended: create a notarytool keychain profile once, then set ECHOPANEL_NOTARY_PROFILE.
#   xcrun notarytool store-credentials "EchoPanelNotary" --apple-id ... --team-id ... --password ...
#
# Env vars (optional):
#   ECHOPANEL_CODESIGN_IDENTITY  Developer ID Application: ...
#   ECHOPANEL_NOTARY_PROFILE     notarytool keychain profile name (recommended)
#   ECHOPANEL_APPLE_TEAM_ID      Team ID (only if not using profile)
#   ECHOPANEL_APPLE_ID           Apple ID (only if not using profile)
#   ECHOPANEL_APPLE_APP_PASSWORD App-specific password (only if not using profile)

RUN=0
APP_PATH=""
DMG_PATH=""
IDENTITY="${ECHOPANEL_CODESIGN_IDENTITY:-}"

die() {
  echo "[sign-notarize] error: $*" >&2
  exit 1
}

run_cmd() {
  if [[ "$RUN" -eq 1 ]]; then
    echo "[sign-notarize] + $*"
    "$@"
  else
    echo "[sign-notarize] (dry-run) $*"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  scripts/sign-notarize.sh [--run] --app <path-to-app> [--dmg <path-to-dmg>] [--identity <codesign-identity>]

Defaults:
  - Dry-run (prints commands). Use --run to execute.

Notarization auth:
  - Recommended: set ECHOPANEL_NOTARY_PROFILE (created via `xcrun notarytool store-credentials ...`)
  - Otherwise: set ECHOPANEL_APPLE_ID, ECHOPANEL_APPLE_TEAM_ID, ECHOPANEL_APPLE_APP_PASSWORD

Examples:
  scripts/sign-notarize.sh --app dist/EchoPanel.app
  scripts/sign-notarize.sh --run --app dist/EchoPanel.app --dmg dist/EchoPanel-0.2.0.dmg
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      RUN=1
      shift
      ;;
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --identity)
      IDENTITY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

command -v xcrun >/dev/null 2>&1 || die "xcrun not found (Xcode Command Line Tools required)."
command -v codesign >/dev/null 2>&1 || die "codesign not found."
command -v spctl >/dev/null 2>&1 || die "spctl not found."
command -v ditto >/dev/null 2>&1 || die "ditto not found."

[[ -n "$APP_PATH" ]] || die "--app is required (path to .app bundle)."
[[ -d "$APP_PATH" ]] || die "app not found: $APP_PATH"

if [[ -n "$DMG_PATH" && ! -f "$DMG_PATH" ]]; then
  die "dmg not found: $DMG_PATH"
fi

if [[ -z "$IDENTITY" ]]; then
  echo "[sign-notarize] No signing identity provided."
  echo "[sign-notarize] Set ECHOPANEL_CODESIGN_IDENTITY or pass --identity."
  echo "[sign-notarize] Available identities:"
  security find-identity -v -p codesigning || true
  die "missing codesign identity"
fi

APP_ZIP="$(mktemp -t echopanel-app.XXXXXX).zip"
cleanup() {
  rm -f "$APP_ZIP" || true
}
trap cleanup EXIT

echo "[sign-notarize] app: $APP_PATH"
if [[ -n "$DMG_PATH" ]]; then
  echo "[sign-notarize] dmg: $DMG_PATH"
fi
echo "[sign-notarize] identity: $IDENTITY"
echo "[sign-notarize] mode: $([[ "$RUN" -eq 1 ]] && echo run || echo dry-run)"

# 1) Sign the app (deep) with hardened runtime.
run_cmd codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"

# 2) Verify codesign.
run_cmd codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# 3) Zip for notarization (Apple prefers a zip for .app).
run_cmd ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

NOTARY_PROFILE="${ECHOPANEL_NOTARY_PROFILE:-}"
APPLE_ID="${ECHOPANEL_APPLE_ID:-}"
APPLE_TEAM_ID="${ECHOPANEL_APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD="${ECHOPANEL_APPLE_APP_PASSWORD:-}"

if [[ -n "$NOTARY_PROFILE" ]]; then
  run_cmd xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
  [[ -n "$APPLE_ID" ]] || die "missing notarization auth: set ECHOPANEL_NOTARY_PROFILE or ECHOPANEL_APPLE_ID"
  [[ -n "$APPLE_TEAM_ID" ]] || die "missing notarization auth: set ECHOPANEL_APPLE_TEAM_ID"
  [[ -n "$APPLE_APP_PASSWORD" ]] || die "missing notarization auth: set ECHOPANEL_APPLE_APP_PASSWORD"
  run_cmd xcrun notarytool submit "$APP_ZIP" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
fi

# 4) Staple the notarization ticket.
run_cmd xcrun stapler staple "$APP_PATH"

# 5) Gatekeeper assessment.
run_cmd spctl -a -vv "$APP_PATH"

# 6) Optional: sign + staple DMG (DMG notarization is separate; many teams notarize the app and distribute DMG).
if [[ -n "$DMG_PATH" ]]; then
  run_cmd codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  run_cmd codesign --verify --verbose=2 "$DMG_PATH"
  run_cmd spctl -a -vv "$DMG_PATH"
fi

echo "[sign-notarize] done"

