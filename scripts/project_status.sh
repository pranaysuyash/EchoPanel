#!/bin/bash
# EchoPanel project status checker

set -euo pipefail

echo "=========================================="
echo "  EchoPanel — Project Status"
echo "=========================================="
echo ""

if [ ! -f "docs/WORKLOG_TICKETS.md" ]; then
  echo "❌ Missing docs/WORKLOG_TICKETS.md"
  echo "   Run from repo root."
  exit 1
fi

DONE_COUNT=$((0 + $( (grep -E "^Status: \\*\\*DONE\\*\\* ✅$" docs/WORKLOG_TICKETS.md 2>/dev/null || true) | wc -l | tr -d ' ' )))
IN_PROGRESS_COUNT=$((0 + $( (grep -E "^Status: \\*\\*IN_PROGRESS\\*\\* 🟡$" docs/WORKLOG_TICKETS.md 2>/dev/null || true) | wc -l | tr -d ' ' )))
OPEN_COUNT=$((0 + $( (grep -E "^Status: \\*\\*OPEN\\*\\* 🔵$" docs/WORKLOG_TICKETS.md 2>/dev/null || true) | wc -l | tr -d ' ' )))
BLOCKED_COUNT=$((0 + $( (grep -E "^Status: \\*\\*BLOCKED\\*\\* 🔴$" docs/WORKLOG_TICKETS.md 2>/dev/null || true) | wc -l | tr -d ' ' )))

echo "📋 TICKETS:"
echo "✅ DONE:        $DONE_COUNT"
echo "🟡 IN_PROGRESS: $IN_PROGRESS_COUNT"
echo "🔵 OPEN:        $OPEN_COUNT"
echo "🔴 BLOCKED:     $BLOCKED_COUNT"
echo ""

echo "📌 OPEN TICKETS:"
echo "----------------"
if [ "$OPEN_COUNT" -gt "0" ]; then
  grep -n "^Status: \\*\\*OPEN\\*\\* 🔵$" docs/WORKLOG_TICKETS.md 2>/dev/null | while read -r line; do
    linenum=$(echo "$line" | cut -d: -f1)
    head -n "$linenum" docs/WORKLOG_TICKETS.md | tail -n 12 | grep -E "^### TCK-" | tail -1 | sed 's/^### /  - /'
  done
else
  echo "  (None)"
fi
echo ""

echo "🔄 IN PROGRESS:"
echo "--------------"
if [ "$IN_PROGRESS_COUNT" -gt "0" ]; then
  grep -n "^Status: \\*\\*IN_PROGRESS\\*\\* 🟡$" docs/WORKLOG_TICKETS.md 2>/dev/null | while read -r line; do
    linenum=$(echo "$line" | cut -d: -f1)
    head -n "$linenum" docs/WORKLOG_TICKETS.md | tail -n 12 | grep -E "^### TCK-" | tail -1 | sed 's/^### /  - /'
  done
else
  echo "  (None)"
fi
echo ""

echo "📦 SURFACES:"
echo "------------"
[ -d "macapp" ] && echo "✅ macapp/" || echo "❌ macapp/"
[ -d "server" ] && echo "✅ server/" || echo "❌ server/"
[ -d "landing" ] && echo "✅ landing/" || echo "❌ landing/"
echo ""

echo "📚 PROCESS ARTIFACTS:"
echo "---------------------"
[ -f "AGENTS.md" ] && echo "✅ AGENTS.md" || echo "❌ AGENTS.md"
[ -d "prompts" ] && echo "✅ prompts/" || echo "❌ prompts/"
[ -f "prompts/README.md" ] && echo "✅ prompts/README.md" || echo "❌ prompts/README.md"
[ -d "docs/audit" ] && echo "✅ docs/audit/" || echo "❌ docs/audit/"
[ -f "docs/CLAIMS.md" ] && echo "✅ docs/CLAIMS.md" || echo "❌ docs/CLAIMS.md"
echo ""

echo "=========================================="
echo "  Tip:"
echo "=========================================="
echo "Start work by creating a ticket in docs/WORKLOG_TICKETS.md and selecting a prompt from prompts/README.md."
echo ""
