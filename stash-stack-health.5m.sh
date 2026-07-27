#!/usr/bin/env bash
# <xbar.title>Stash Stack Health</xbar.title>
# <xbar.version>v1.5.0</xbar.version>
# <xbar.author>AaronIsMeUx</xbar.author>
# <xbar.author.github>AaronIsMeUx</xbar.author.github>
# <xbar.desc>Menubar health monitor for a Mac-hosted Stash + Arr media automation stack. Checks Stash, Stashy (remote access), Whisparr, Prowlarr, Prowlarr indexer auth/health, FlareSolverr, qBittorrent, Homarr, Glances, Docker, your media drive, and Time Machine backup freshness. Fully configurable.</xbar.desc>
# <xbar.dependencies>bash,curl,docker</xbar.dependencies>
# <xbar.abouturl>https://github.com/AaronIsMeUx/stash-stack-health</xbar.abouturl>
# <swiftbar.hideAbout>false</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>false</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# --- Load user config (copy config.example.sh to ~/.config/stash-stack-health/config.sh) ---
CONFIG_FILE="$HOME/.config/stash-stack-health/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# --- Defaults (override any of these in your config.sh) ---
CHECK_STASH="${CHECK_STASH:-true}"
CHECK_STASHY="${CHECK_STASHY:-true}"
CHECK_STASHARR="${CHECK_STASHARR:-true}"
CHECK_WHISPARR="${CHECK_WHISPARR:-true}"
CHECK_PROWLARR="${CHECK_PROWLARR:-true}"
CHECK_PROWLARR_INDEXERS="${CHECK_PROWLARR_INDEXERS:-true}"
CHECK_FLARESOLVERR="${CHECK_FLARESOLVERR:-true}"
CHECK_QBITTORRENT="${CHECK_QBITTORRENT:-true}"
CHECK_HOMARR="${CHECK_HOMARR:-true}"
CHECK_GLANCES="${CHECK_GLANCES:-true}"
CHECK_DOCKER="${CHECK_DOCKER:-true}"
CHECK_MEDIA_DRIVE="${CHECK_MEDIA_DRIVE:-false}"
CHECK_TIMEMACHINE="${CHECK_TIMEMACHINE:-true}"

STASH_PORT="${STASH_PORT:-9999}"
STASHARR_PORT="${STASHARR_PORT:-3000}"
WHISPARR_PORT="${WHISPARR_PORT:-6969}"
PROWLARR_PORT="${PROWLARR_PORT:-9696}"
FLARESOLVERR_PORT="${FLARESOLVERR_PORT:-8191}"
QBITTORRENT_PORT="${QBITTORRENT_PORT:-8080}"
HOMARR_PORT="${HOMARR_PORT:-7575}"
GLANCES_PORT="${GLANCES_PORT:-61208}"

MEDIA_DRIVE_PATH="${MEDIA_DRIVE_PATH:-}"

# Time Machine freshness. Reads the last-backup date from the TM preferences plist
# (no Full Disk Access needed) and — importantly — NEVER touches the backup drive,
# because tmutil/ls hang for minutes on a dropped destination. WARN hours = yellow,
# MAX hours = red alarm (fires a notification). Aaron backs up daily, so >48h = flag.
TIMEMACHINE_WARN_HOURS="${TIMEMACHINE_WARN_HOURS:-24}"
TIMEMACHINE_MAX_HOURS="${TIMEMACHINE_MAX_HOURS:-48}"

# Prowlarr indexer check: Prowlarr's port can answer fine while every indexer is
# dead (expired tracker cookie/session), leaving the stack silently unable to
# search. This asks Prowlarr's own health API whether any indexers are failing.
# API key: set it here, or leave empty to auto-read from the Docker container.
PROWLARR_API_KEY="${PROWLARR_API_KEY:-}"
PROWLARR_CONTAINER="${PROWLARR_CONTAINER:-prowlarr}"

# Stashy (iPhone app) reachability: verifies Stash answers OFF localhost (i.e. the
# phone can actually connect). Set to your Mac's LAN IP (home WiFi) or Tailscale IP
# (remote). Uses STASH_PORT. This catches Stash being bound to 127.0.0.1 only.
STASHY_HOST="${STASHY_HOST:-192.168.68.62}"

STASHDB_URL="${STASHDB_URL:-https://stashdb.org}"
OPEN_SHORTCUTS="${OPEN_SHORTCUTS:-true}"

STATE_FILE="/tmp/stash-stack-health-status.txt"
MODE="${1:-human}"

# --- Check functions ---
check_http() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$1" 2>/dev/null || echo "000")
  [[ "$code" =~ ^[23] ]]
}

check_docker() { docker info >/dev/null 2>&1; }

check_drive() {
  [ -n "$MEDIA_DRIVE_PATH" ] && [ -d "$MEDIA_DRIVE_PATH" ]
}

# Time Machine backup freshness. Reads SnapshotDates from the TM plist — fast, no
# Full Disk Access, and crucially never touches the (possibly dropped) backup drive.
# Sets TM_DETAIL. Returns 0 = fresh (<=WARN), 3 = getting stale (WARN..MAX),
# 1 = STALE past MAX (the alarm), 2 = can't tell (no history / unparseable).
TM_DETAIL=""
check_timemachine() {
  local plist="/Library/Preferences/com.apple.TimeMachine.plist"
  local newest epoch now age_h result failnote
  # CRITICAL: read only SnapshotDates (SUCCESSFUL backups). The plist also holds
  # AttemptDates (every try, including failures) — counting those would show green
  # off a FAILED backup. Isolate the SnapshotDates block, then take the most recent
  # (all dates are UTC, so a lexical sort is chronological).
  newest=$(defaults read "$plist" Destinations 2>/dev/null \
    | awk '/SnapshotDates =/{f=1;next} /\);/{f=0} f' \
    | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]{8} [+-][0-9]{4}' | sort | tail -1)
  # RESULT of the most recent attempt: 0 = succeeded, non-zero = failed.
  result=$(defaults read "$plist" Destinations 2>/dev/null \
    | grep -oE 'RESULT = [0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ -z "$newest" ]; then
    TM_DETAIL="no successful backup on record"
    return 1
  fi
  epoch=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$newest" +%s 2>/dev/null)
  if [ -z "$epoch" ]; then
    TM_DETAIL="couldn't parse last-backup date"
    return 2
  fi
  now=$(date +%s)
  age_h=$(( (now - epoch) / 3600 ))
  failnote=""
  [ -n "$result" ] && [ "$result" != "0" ] && failnote=" — last attempt FAILED (err $result)"
  if [ "$age_h" -gt "$TIMEMACHINE_MAX_HOURS" ]; then
    TM_DETAIL="last good backup ${age_h}h ago — STALE (>${TIMEMACHINE_MAX_HOURS}h)${failnote}"; return 1
  elif [ "$age_h" -gt "$TIMEMACHINE_WARN_HOURS" ] || [ -n "$failnote" ]; then
    TM_DETAIL="last good backup ${age_h}h ago${failnote}"; return 3
  else
    TM_DETAIL="last good backup ${age_h}h ago"; return 0
  fi
}

# Sets INDEXER_DETAIL. Returns 0 = all indexers OK, 1 = one or more failing,
# 2 = can't tell (no API key / no answer) — reported as unknown, never as down,
# so a missing key doesn't masquerade as an outage.
INDEXER_DETAIL=""
check_prowlarr_indexers() {
  local key="$PROWLARR_API_KEY" resp
  if [ -z "$key" ] && command -v docker >/dev/null 2>&1; then
    key=$(docker exec "$PROWLARR_CONTAINER" cat /config/config.xml 2>/dev/null \
          | grep -oE '<ApiKey>[^<]+' | sed 's/<ApiKey>//')
  fi
  if [ -z "$key" ]; then
    INDEXER_DETAIL="no API key — set PROWLARR_API_KEY in config.sh"
    return 2
  fi

  resp=$(curl -s --max-time 8 "http://localhost:${PROWLARR_PORT}/api/v1/health" \
         -H "X-Api-Key: $key" 2>/dev/null)
  if [ -z "$resp" ]; then
    INDEXER_DETAIL="Prowlarr health API not answering"
    return 2
  fi

  # Prowlarr raises IndexerStatusCheck / IndexerLongTermStatusCheck when trackers
  # reject it. Match only those — ignore unrelated notices like "update available".
  INDEXER_DETAIL=$(printf '%s' "$resp" \
    | grep -oE '"message":"[^"]*[Ii]ndexers[^"]*navailable[^"]*"' \
    | sed 's/"message":"//; s/"$//' | head -2)

  if [ -n "$INDEXER_DETAIL" ]; then
    return 1
  fi
  INDEXER_DETAIL="all indexers responding"
  return 0
}

# --- Run enabled checks ---
results=()

[ "$CHECK_STASH"        = "true" ] && { check_http "http://localhost:${STASH_PORT}"        && results+=("Stash|up")        || results+=("Stash|down"); }
[ "$CHECK_STASHY"       = "true" ] && { check_http "http://${STASHY_HOST}:${STASH_PORT}"    && results+=("Stashy (remote)|up") || results+=("Stashy (remote)|down"); }
[ "$CHECK_STASHARR"     = "true" ] && { check_http "http://localhost:${STASHARR_PORT}"      && results+=("Stasharr|up")     || results+=("Stasharr|down"); }
[ "$CHECK_WHISPARR"     = "true" ] && { check_http "http://localhost:${WHISPARR_PORT}/ping" && results+=("Whisparr|up")     || results+=("Whisparr|down"); }
[ "$CHECK_PROWLARR"     = "true" ] && { check_http "http://localhost:${PROWLARR_PORT}/ping" && results+=("Prowlarr|up")     || results+=("Prowlarr|down"); }
if [ "$CHECK_PROWLARR_INDEXERS" = "true" ]; then
  check_prowlarr_indexers; rc=$?
  case $rc in
    0) results+=("Prowlarr indexers|up") ;;
    1) results+=("Prowlarr indexers|down") ;;
    *) results+=("Prowlarr indexers|unknown") ;;
  esac
fi
[ "$CHECK_FLARESOLVERR" = "true" ] && { check_http "http://localhost:${FLARESOLVERR_PORT}/health" && results+=("FlareSolverr|up") || results+=("FlareSolverr|down"); }
[ "$CHECK_QBITTORRENT"  = "true" ] && { check_http "http://localhost:${QBITTORRENT_PORT}"  && results+=("qBittorrent|up")  || results+=("qBittorrent|down"); }
[ "$CHECK_HOMARR"       = "true" ] && { check_http "http://localhost:${HOMARR_PORT}"        && results+=("Homarr|up")       || results+=("Homarr|down"); }
[ "$CHECK_GLANCES"      = "true" ] && { check_http "http://localhost:${GLANCES_PORT}"       && results+=("Glances|up")      || results+=("Glances|down"); }
[ "$CHECK_DOCKER"       = "true" ] && { check_docker                                        && results+=("Docker|up")       || results+=("Docker|down"); }
[ "$CHECK_MEDIA_DRIVE"  = "true" ] && { check_drive                                         && results+=("Media drive|up")  || results+=("Media drive|down"); }
if [ "$CHECK_TIMEMACHINE" = "true" ]; then
  check_timemachine; rc=$?
  case $rc in
    0) results+=("Time Machine|up") ;;
    3) results+=("Time Machine|warn") ;;
    1) results+=("Time Machine|down") ;;
    *) results+=("Time Machine|unknown") ;;
  esac
fi

# --- Compute overall status ---
down_count=0
down_names=""
for r in "${results[@]}"; do
  if [ "${r#*|}" = "down" ]; then
    down_count=$((down_count + 1))
    down_names="$down_names ${r%|*}"
  fi
done

if   [ "$down_count" -eq 0 ]; then overall="healthy";  icon="🟢"
elif [ "$down_count" -le 2 ]; then overall="degraded"; icon="🟡"
else                                overall="critical"; icon="🔴"
fi

# --- Output ---
if [ "$MODE" = "--swiftbar" ] || [ -n "$SWIFTBAR_VERSION" ]; then
  echo "$icon"
  echo "---"
  for r in "${results[@]}"; do
    name="${r%|*}"; status="${r#*|}"
    case "$status" in
      up)      echo "$name ✓ | color=green" ;;
      warn)    echo "$name ⚠ | color=orange" ;;
      unknown) echo "$name ? | color=gray" ;;
      *)       echo "$name ✗ | color=red" ;;
    esac
    # Surface which indexers are failing — "down" alone doesn't tell you what to fix.
    if [ "$name" = "Prowlarr indexers" ] && [ -n "$INDEXER_DETAIL" ] && [ "$status" != "up" ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && echo "--$line | color=gray size=11"
      done <<< "$INDEXER_DETAIL"
      echo "--Fix: refresh the tracker cookie in Prowlarr | href=http://localhost:${PROWLARR_PORT}/settings/indexers size=11"
    fi
    # Always show how fresh the last backup is; add a fix hint when it's stale.
    if [ "$name" = "Time Machine" ] && [ -n "$TM_DETAIL" ]; then
      echo "--$TM_DETAIL | color=gray size=11"
      [ "$status" != "up" ] && echo "--Fix: reconnect the backup drive, then run a backup | size=11"
    fi
  done
  echo "---"
  echo "Refresh | refresh=true"

  if [ "$OPEN_SHORTCUTS" = "true" ]; then
    echo "Quick Shortcuts | color=blue"
    [ "$CHECK_STASH"    = "true" ] && echo "--Open Stash | href=http://localhost:${STASH_PORT}"
    [ "$CHECK_STASHARR" = "true" ] && echo "--Open Stasharr | href=http://localhost:${STASHARR_PORT}/login"
    [ -n "$STASHDB_URL" ]          && echo "--Open StashDB | href=${STASHDB_URL}"
    [ "$CHECK_WHISPARR" = "true" ] && echo "--Open Whisparr | href=http://localhost:${WHISPARR_PORT}"
    [ "$CHECK_PROWLARR" = "true" ] && echo "--Open Prowlarr | href=http://localhost:${PROWLARR_PORT}"
    [ "$CHECK_QBITTORRENT" = "true" ] && echo "--Open qBittorrent | href=http://localhost:${QBITTORRENT_PORT}"
    [ "$CHECK_HOMARR" = "true" ] && echo "--Open Homarr | href=http://localhost:${HOMARR_PORT}"
    [ "$CHECK_GLANCES" = "true" ] && echo "--Open Glances | href=http://localhost:${GLANCES_PORT}"
    echo "---"
  fi

  [ "$CHECK_STASH"    = "true" ] && echo "Open Stash | href=http://localhost:${STASH_PORT}"
  [ "$CHECK_STASHARR" = "true" ] && echo "Open Stasharr | href=http://localhost:${STASHARR_PORT}/login"
  [ -n "$STASHDB_URL" ]          && echo "Open StashDB | href=${STASHDB_URL}"
  [ "$CHECK_WHISPARR" = "true" ] && echo "Open Whisparr | href=http://localhost:${WHISPARR_PORT}"
  [ "$CHECK_PROWLARR" = "true" ] && echo "Open Prowlarr | href=http://localhost:${PROWLARR_PORT}"
  [ "$CHECK_QBITTORRENT" = "true" ] && echo "Open qBittorrent | href=http://localhost:${QBITTORRENT_PORT}"
  [ "$CHECK_HOMARR" = "true" ] && echo "Open Homarr | href=http://localhost:${HOMARR_PORT}"
  [ "$CHECK_GLANCES" = "true" ] && echo "Open Glances | href=http://localhost:${GLANCES_PORT}"
  echo "---"
  echo "Stash Stack Health v1.5.0 | color=gray size=11"

  current="$overall|$down_count"
  prev=""
  [ -f "$STATE_FILE" ] && prev=$(cat "$STATE_FILE")
  if [ -n "$prev" ] && [ "$prev" != "$current" ]; then
    if [ "$overall" = "healthy" ]; then
      osascript -e 'display notification "All services healthy" with title "Stash Stack"'
    else
      osascript -e "display notification \"Down:${down_names}\" with title \"Stash Stack\" subtitle \"Status: ${overall}\""
    fi
  fi
  echo "$current" > "$STATE_FILE"
else
  printf "\n%s Stash Stack — %s\n\n" "$icon" "$overall"
  printf "%-18s %s\n" "SERVICE" "STATUS"
  printf "%-18s %s\n" "-------" "------"
  for r in "${results[@]}"; do
    name="${r%|*}"; status="${r#*|}"
    case "$status" in
      up)      printf "%-18s \033[32m✓ up\033[0m\n" "$name" ;;
      warn)    printf "%-18s \033[33m⚠ stale\033[0m\n" "$name" ;;
      unknown) printf "%-18s \033[90m? unknown\033[0m\n" "$name" ;;
      *)       printf "%-18s \033[31m✗ down\033[0m\n" "$name" ;;
    esac
    if [ "$name" = "Prowlarr indexers" ] && [ -n "$INDEXER_DETAIL" ] && [ "$status" != "up" ]; then
      printf "                   \033[90m%s\033[0m\n" "$INDEXER_DETAIL"
    fi
    if [ "$name" = "Time Machine" ] && [ -n "$TM_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$TM_DETAIL"
    fi
  done
  printf "\n"
fi
