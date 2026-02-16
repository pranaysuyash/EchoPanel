#!/usr/bin/env bash
set -euo pipefail

print_header() {
  echo "[permissions-verify] $1"
}

print_header "This is a manual verification checklist for denied permissions."
print_header "Target: EchoPanel macOS app"

echo ""
echo "Checklist:"
echo "  1) Quit EchoPanel (menu bar → Quit)"
echo "  2) Open System Settings → Privacy & Security"
echo "  3) Screen Recording → toggle OFF for EchoPanel"
echo "  4) Microphone → toggle OFF for EchoPanel"
echo "  5) Launch EchoPanel"
echo "  6) Attempt to start a session"
echo "  7) Confirm:"
echo "     - App does NOT crash"
echo "     - User-facing guidance appears (permission prompt or inline error)"
echo "     - Session does not start without permissions"
echo "     - App remains responsive"
echo ""

if pgrep -f "MeetingListenerApp" >/dev/null 2>&1; then
  print_header "EchoPanel appears to be running. Quit it before step 1."
fi

read -r -p "Type 'yes' once you completed the checklist: " confirm
if [[ "${confirm}" != "yes" ]]; then
  print_header "Verification not confirmed."
  exit 2
fi

print_header "Denied-permissions verification confirmed (manual)."
