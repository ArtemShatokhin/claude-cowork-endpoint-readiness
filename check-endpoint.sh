#!/usr/bin/env bash
# This script is part of the open-source claude-cowork-endpoint-readiness toolkit.
# Read it, fork it, audit it. MIT licensed.
# check-endpoint.sh - read-only preflight for a machine that will act as the
# Claude Cowork desktop bridge. No sudo, no writes, no data leaves the machine.
#
# Usage:  ./check-endpoint.sh [--json] [--no-network]
# Exit:   0 all documented requirements met, 1 a documented requirement failed,
#         2 unsupported platform (Cowork's desktop bridge is macOS or Windows).
#
# Requirement sources (fetched 2026-10-21):
#   support.claude.com/en/articles/13345190-get-started-with-claude-cowork
#   support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork
set -u

JSON=0
NETWORK=1
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --no-network) NETWORK=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

FAILED=0
ROWS=()

record() { # record <status> <id> <detail>
  ROWS+=("$1|$2|$3")
  [ "$1" = "FAIL" ] && FAILED=1
  return 0
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

UNAME=$(uname -s 2>/dev/null || echo unknown)
OS_NAME=""
OS_VERSION=""
SUPPORTED=1

case "$UNAME" in
  Darwin)
    OS_NAME="macOS"
    OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS_NAME="Windows"
    OS_VERSION=$(cmd.exe /c ver 2>/dev/null | tr -d '\r' || echo "unknown")
    ;;
  Linux)
    OS_NAME="Linux"
    OS_VERSION=$(uname -r)
    SUPPORTED=0
    ;;
  *)
    OS_NAME="$UNAME"
    OS_VERSION="unknown"
    SUPPORTED=0
    ;;
esac

if [ "$SUPPORTED" -eq 0 ]; then
  record FAIL platform "$OS_NAME $OS_VERSION is not a Cowork desktop-bridge platform (Anthropic ships the bridge in the Claude Desktop app for macOS and Windows only)"
  if [ "$JSON" -eq 1 ]; then
    printf '{"platform":"%s","supported":false,"checks":[]}\n' "$(json_escape "$OS_NAME")"
  else
    echo "UNSUPPORTED: $OS_NAME $OS_VERSION"
    echo "Cowork's desktop bridge runs in the Claude Desktop app for macOS or Windows."
  fi
  exit 2
fi

record PASS platform "$OS_NAME $OS_VERSION"

# 1. Claude Desktop app installed (documented: the app must be installed, open
#    and connected for local file access, browser use and computer use).
APP_PATH=""
APP_VERSION=""
if [ "$OS_NAME" = "macOS" ]; then
  if [ -d "/Applications/Claude.app" ]; then
    APP_PATH="/Applications/Claude.app"
  elif [ -d "$HOME/Applications/Claude.app" ]; then
    APP_PATH="$HOME/Applications/Claude.app"
  fi
  if [ -n "$APP_PATH" ]; then
    APP_VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)
  fi
else
  for candidate in "/c/Users/$USER/AppData/Local/Programs/Claude/Claude.exe" \
                   "/c/Program Files/Claude/Claude.exe" \
                   "/c/Program Files (x86)/Claude/Claude.exe"; do
    if [ -f "$candidate" ]; then APP_PATH="$candidate"; break; fi
  done
  if [ -n "$APP_PATH" ]; then
    APP_VERSION=$(powershell.exe -NoProfile -Command "(Get-Item '$APP_PATH').VersionInfo.ProductVersion" 2>/dev/null | tr -d '\r' || echo unknown)
  fi
fi

if [ -n "$APP_PATH" ]; then
  record PASS app_installed "Claude Desktop found at $APP_PATH (version $APP_VERSION). Anthropic ships Cowork only inside the latest build: update before a rollout."
else
  record FAIL app_installed "Claude Desktop not found in the standard install locations. Cowork has no browser-only path to local files, the browser or computer use."
fi

# 2. App process running (documented: the app must be open and connected while
#    a task needs the machine).
RUNNING=0
if [ "$OS_NAME" = "macOS" ]; then
  pgrep -x Claude >/dev/null 2>&1 && RUNNING=1
else
  tasklist.exe 2>/dev/null | grep -qi "Claude.exe" && RUNNING=1
fi
if [ "$RUNNING" -eq 1 ]; then
  record PASS app_running "Claude Desktop is running. 'Connected' cannot be read locally - confirm the session shows the machine in Settings > Cowork."
else
  record WARN app_running "Claude Desktop is not running. Start it before a task that needs a local file, the browser or computer use."
fi

# 3. Sleep state (documented: the desktop must be active and the computer awake).
if [ "$OS_NAME" = "macOS" ]; then
  SLEEP_LINE=$(pmset -g custom 2>/dev/null | awk '/System sleep|sleep/{print; exit}')
  if pmset -g custom 2>/dev/null | grep -Eq '^[[:space:]]*sleep[[:space:]]+0'; then
    record PASS sleep "System sleep is disabled ($(echo "$SLEEP_LINE" | tr -s ' '))."
  else
    record WARN sleep "System sleep is enabled; a sleeping machine cannot answer Cowork. Consider a policy for rollout machines (caffeinate, or a managed power profile)."
  fi
  if pmset -g custom 2>/dev/null | grep -Eq '^[[:space:]]*disksleep[[:space:]]+[1-9]'; then
    record WARN disk_sleep "Disk sleep is enabled; long tasks that touch local files can outlive a sleeping disk."
  fi
else
  STANDBY=$(powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>/dev/null | tr -d '\r' | awk -F': ' '/Current AC Power Setting Index/{print $2}')
  if [ "${STANDBY:-0x1}" = "0x00000000" ]; then
    record PASS sleep "Standby is disabled on AC power."
  else
    record WARN sleep "Standby is enabled on AC power (${STANDBY:-unknown}); a sleeping machine cannot answer Cowork."
  fi
fi

# 4. Disk headroom. Not an Anthropic requirement: report only.
if [ "$OS_NAME" = "macOS" ]; then
  FREE_GB=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
else
  FREE_GB=$(df -g /c 2>/dev/null | awk 'NR==2{print $4}')
fi
record INFO disk_free "${FREE_GB:-unknown} GB free on the system volume. Not an Anthropic requirement, but Cowork writes deliverables to the machine through the app."

# 5. Managed-device state (affects who can grant the app file and browser access).
if [ "$OS_NAME" = "macOS" ]; then
  if profiles status -type enrollment 2>/dev/null | grep -qi "enrolled via DEP: Yes\|MDM enrollment: Yes"; then
    record WARN management "This Mac is MDM-enrolled: Full Disk Access, Screen Recording and the built-in browser may be granted only by policy. Get the profile approved before the pilot."
  else
    record PASS management "No MDM enrollment reported."
  fi
fi

# 6. Egress. Documented: Cowork respects the machine's network egress permissions,
#    and corporate proxies/MITM break the app's connection.
if [ "$NETWORK" -eq 1 ]; then
  for host in claude.ai api.anthropic.com claude.com; do
    if curl -sS -o /dev/null --max-time 8 "https://$host/" 2>/dev/null; then
      record PASS "egress_$host" "HTTPS to $host works from this machine."
    else
      record FAIL "egress_$host" "HTTPS to $host failed. A machine behind an egress allowlist or a TLS-inspecting proxy will not stay connected."
    fi
  done
else
  record INFO egress "Network checks skipped (--no-network)."
fi

# 7. Proxy configuration. Report only, so a failed egress check has a cause.
PROXY_VARS=$(env | grep -Ei '^(https?_proxy|no_proxy)=' | tr '\n' ' ')
if [ "$OS_NAME" = "macOS" ]; then
  PROXY_SYS=$(scutil --proxy 2>/dev/null | grep -E "HTTPSEnable|HTTPSProxy|HTTPSPort" | tr -s ' ' | tr '\n' ' ')
else
  PROXY_SYS=$(netsh.exe winhttp show proxy 2>/dev/null | tr -d '\r' | tail -n 2 | tr '\n' ' ')
fi
record INFO proxy "env: ${PROXY_VARS:-none} | system: ${PROXY_SYS:-none}"

# Report.
if [ "$JSON" -eq 1 ]; then
  printf '{"platform":"%s","os_version":"%s","app_version":"%s","failed":%d,"checks":[' \
    "$(json_escape "$OS_NAME")" "$(json_escape "$OS_VERSION")" "$(json_escape "$APP_VERSION")" "$FAILED"
  first=1
  for row in "${ROWS[@]}"; do
    IFS='|' read -r status id detail <<EOF
$row
EOF
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"id":"%s","status":"%s","detail":"%s"}' "$(json_escape "$id")" "$status" "$(json_escape "$detail")"
  done
  printf ']}\n'
else
  echo "Cowork endpoint readiness - $OS_NAME $OS_VERSION"
  echo "------------------------------------------------------------"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r status id detail <<EOF
$row
EOF
    printf '%-4s %-14s %s\n' "$status" "$id" "$detail"
  done
  echo "------------------------------------------------------------"
  if [ "$FAILED" -eq 1 ]; then
    echo "RESULT: not ready (a documented requirement failed)."
  else
    echo "RESULT: ready for a pilot, subject to the manual steps in checklist.md."
  fi
fi

exit "$FAILED"
