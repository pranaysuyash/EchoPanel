#!/usr/bin/env bash
set -euo pipefail

# Test offline behavior using hosts file manipulation
# This is safer than disabling Wi-Fi as it only affects specific endpoints

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/tmp/hosts.backup.$(date +%s)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
  echo -e "${YELLOW}[offline-test]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[offline-test]${NC} $1"
}

print_error() {
  echo -e "${RED}[offline-test]${NC} $1"
}

# Cloud ASR endpoints to block
BLOCKED_ENDPOINTS=(
  "api.openai.com"
  "api.deepgram.com"
  "api.assemblyai.com"
  "api.groq.com"
  "api.speechmatics.com"
)

cleanup() {
  print_header "Cleaning up..."
  if [ -f "$BACKUP_FILE" ]; then
    sudo cp "$BACKUP_FILE" "$HOSTS_FILE"
    rm "$BACKUP_FILE"
    print_success "Restored original hosts file"
  fi
  
  # Flush DNS cache
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true
}

trap cleanup EXIT

print_header "Offline Testing via hosts file"
echo "This script will temporarily block cloud ASR endpoints using /etc/hosts"
echo ""

# Check if running as root (needed for hosts file)
if [ "$EUID" -ne 0 ]; then 
  print_error "This script requires sudo to modify /etc/hosts"
  echo "Run with: sudo $0"
  exit 1
fi

# Backup hosts file
cp "$HOSTS_FILE" "$BACKUP_FILE"
print_success "Backed up hosts file to $BACKUP_FILE"

# Add blocking entries
print_header "Blocking cloud ASR endpoints..."
echo "" >> "$HOSTS_FILE"
echo "# EchoPanel offline test - temporary block" >> "$HOSTS_FILE"
for endpoint in "${BLOCKED_ENDPOINTS[@]}"; do
  echo "127.0.0.1 $endpoint" >> "$HOSTS_FILE"
  print_success "  Blocked: $endpoint"
done

# Flush DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

print_header ""
print_success "Cloud endpoints blocked!"
echo ""
echo "Test checklist:"
echo "  [ ] Start EchoPanel app"
echo "  [ ] Start a recording with MLX backend (should work normally)"
echo "  [ ] Switch to cloud backend (should show graceful error)"
echo "  [ ] Verify error message is user-friendly"
echo "  [ ] Verify app doesn't crash"
echo ""
echo "Press Ctrl+C when done testing to restore hosts file"

# Wait for interrupt
while true; do
  sleep 1
done
