#!/usr/bin/env bash
# <xbar.title>Stash Stack Health</xbar.title>
# <xbar.version>v1.9.0</xbar.version>
# <xbar.author>AaronIsMeUx</xbar.author>
# <xbar.author.github>AaronIsMeUx</xbar.author.github>
# <xbar.desc>Menubar health monitor for a Mac-hosted Stash + Arr media automation stack. Checks Stash, Stashy (remote access), Whisparr, Radarr, Sonarr, Jellyseerr, Jellyfin, Prowlarr, Prowlarr indexer auth/health, FlareSolverr, qBittorrent, Homarr, Glances, Docker, your media drive, boot disk headroom, backup drive temperature, and Time Machine backup freshness. Fully configurable.</xbar.desc>
# <xbar.dependencies>bash,curl,docker</xbar.dependencies>
# <xbar.abouturl>https://github.com/AaronIsMeUx/stash-stack-health</xbar.abouturl>
# <swiftbar.hideAbout>false</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>false</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
HOMARR_LAUNCHER="${HOMARR_LAUNCHER:-$HOME/projects/homarr-launcher/homarr-launcher.10s.sh}"

# --- Load user config (copy config.example.sh to ~/.config/stash-stack-health/config.sh) ---
CONFIG_FILE="$HOME/.config/stash-stack-health/config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# --- Defaults (override any of these in your config.sh) ---
CHECK_STASH="${CHECK_STASH:-true}"
CHECK_STASHY="${CHECK_STASHY:-true}"
CHECK_STASHARR="${CHECK_STASHARR:-true}"
CHECK_WHISPARR="${CHECK_WHISPARR:-true}"
CHECK_RADARR="${CHECK_RADARR:-true}"
CHECK_SONARR="${CHECK_SONARR:-true}"
CHECK_JELLYSEERR="${CHECK_JELLYSEERR:-true}"
CHECK_BOOT_DISK="${CHECK_BOOT_DISK:-true}"
CHECK_DRIVE_TEMP="${CHECK_DRIVE_TEMP:-true}"
CHECK_JELLYFIN="${CHECK_JELLYFIN:-true}"
CHECK_PROWLARR="${CHECK_PROWLARR:-true}"
CHECK_PROWLARR_INDEXERS="${CHECK_PROWLARR_INDEXERS:-true}"
CHECK_FLARESOLVERR="${CHECK_FLARESOLVERR:-true}"
CHECK_QBITTORRENT="${CHECK_QBITTORRENT:-true}"
CHECK_HOMARR="${CHECK_HOMARR:-true}"
CHECK_GLANCES="${CHECK_GLANCES:-true}"
CHECK_DOCKER="${CHECK_DOCKER:-true}"
CHECK_MEDIA_DRIVE="${CHECK_MEDIA_DRIVE:-false}"
CHECK_TIMEMACHINE="${CHECK_TIMEMACHINE:-true}"
# Optional extras - default OFF so a fresh clone never reports a service you do not run.
CHECK_QUI="${CHECK_QUI:-false}"
CHECK_SEEDBOX="${CHECK_SEEDBOX:-false}"
CHECK_JOBS="${CHECK_JOBS:-false}"

STASH_PORT="${STASH_PORT:-9999}"
STASHARR_PORT="${STASHARR_PORT:-3000}"
WHISPARR_PORT="${WHISPARR_PORT:-6969}"
RADARR_PORT="${RADARR_PORT:-7878}"
SONARR_PORT="${SONARR_PORT:-8989}"
JELLYSEERR_PORT="${JELLYSEERR_PORT:-5055}"
# boot disk: warn below this many GB free. macOS keeps its swap file here,
# so running it to zero can stall or halt the machine.
BOOT_DISK_MIN_GB="${BOOT_DISK_MIN_GB:-60}"
# Backup drive temperature ceiling. Enterprise drives are commonly rated
# 10-40 C recommended / 60 C absolute, but many USB enclosures run them
# hotter than that, so 45 C is a practical amber line rather than 40.
DRIVE_TEMP_WARN_C="${DRIVE_TEMP_WARN_C:-45}"
SMARTCTL_BIN="${SMARTCTL_BIN:-/opt/homebrew/bin/smartctl}"
# Which devices to read. Matched against `smartctl --scan` output, so set this
# to whatever your USB/Thunderbolt enclosure calls itself.
DRIVE_TEMP_MATCH="${DRIVE_TEMP_MATCH:-acasis}"
JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"
QUI_PORT="${QUI_PORT:-7476}"
SEEDBOX_PORT="${SEEDBOX_PORT:-29963}"
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
STASHY_HOST="${STASHY_HOST:-192.168.1.50}"

STASHDB_URL="${STASHDB_URL:-https://stashdb.org}"
OPEN_SHORTCUTS="${OPEN_SHORTCUTS:-true}"

STATE_FILE="/tmp/stash-stack-health-status.txt"
MODE="${1:-human}"

# --- Check functions ---
# --- boot disk headroom -------------------------------------------------
# Returns free GB on the data volume. macOS swap lives here; if it fills,
# the machine halts. Cheap to check, so it runs every cycle.
boot_disk_free_gb() {
  df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}'
}

# --- backup drive temperature -------------------------------------------
# WHY ONCE AN HOUR: many USB bridges report "CHECK POWER MODE not implemented",
# which means smartctl cannot check whether a drive is parked without waking
# it. At a 5 minute cadence that would add ~12 spin-ups an hour. Cached hourly.
# Silent when the enclosure is powered off - that is normal, not a fault.
drive_temp_max_c() {
  local cache="$HOME/.config/claude-jobs/drive-temp.cache"
  mkdir -p "$(dirname "$cache")"
  if [ -f "$cache" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 3600 ] && { cat "$cache"; return 0; }
  fi
  [ -x "$SMARTCTL_BIN" ] || { echo ""; return 0; }
  local devs hottest=""
  devs=$("$SMARTCTL_BIN" --scan 2>/dev/null | grep -i "$DRIVE_TEMP_MATCH" | sed 's/ -d ata.*//')
  [ -z "$devs" ] && { echo "" > "$cache"; echo ""; return 0; }
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    local t
    t=$("$SMARTCTL_BIN" -d ata -A "$d" 2>/dev/null | awk '/Temperature_Celsius/{print $10; exit}')
    [ -n "$t" ] && { [ -z "$hottest" ] && hottest="$t" || { [ "$t" -gt "$hottest" ] && hottest="$t"; }; }
  done <<< "$devs"
  echo "$hottest" > "$cache"
  echo "$hottest"
}

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

# --- Long-running supervised jobs ---
JOBS_DETAIL=""
# Aaron 2026-08-28: long jobs kept dying unattended and he only found out by asking.
# Surfaces a dead or stalled job in the menu bar in real time. Needs no credentials.
check_jobs() {
  local jr out bad run
  jr="${JOBRUNNER_PATH:-$HOME/Claude Projects/tools/jobrunner/jobrunner.py}"
  [ -f "$jr" ] || { JOBS_DETAIL="jobrunner not installed"; return 2; }
  out=$(/usr/bin/python3 "$jr" list 2>/dev/null) || { JOBS_DETAIL="jobrunner error"; return 2; }
  if [ -z "$out" ] || [ "$out" = "no jobs registered" ]; then
    JOBS_DETAIL="none registered"; return 0
  fi
  bad=$(printf "%s\n" "$out" | awk 'NR>1 && ($3=="failed" || ($3=="running" && $NF=="no"))' | wc -l | tr -d ' ')
  run=$(printf "%s\n" "$out" | awk 'NR>1 && $3=="running" && $NF=="yes"' | wc -l | tr -d ' ')
  if [ "${bad:-0}" -gt 0 ]; then JOBS_DETAIL="${bad} job(s) NOT running"; return 1; fi
  JOBS_DETAIL="${run} running"
  return 0
}

# --- Seedbox qBittorrent, reached over a persistent SSH tunnel ---
# Proves the whole chain in one check: tunnel up, credentials valid, client responding.
# A bare port check is not enough - the tunnel can be up while qBittorrent is dead,
# and qBittorrent answers 403 to an unauthenticated request, which looks like failure.
SEEDBOX_DETAIL=""
check_seedbox() {
  local ck code n
  ck=$(mktemp) || return 2
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 -c "$ck" \
         -H "Referer: http://localhost:${SEEDBOX_PORT}" \
         --data-urlencode "username=${SEEDBOX_USER}" \
         --data-urlencode "password=${SEEDBOX_PASS}" \
         "http://localhost:${SEEDBOX_PORT}/api/v2/auth/login" 2>/dev/null || echo "000")
  if [ "$code" != "200" ] && [ "$code" != "204" ]; then
    rm -f "$ck"
    if [ "$code" = "000" ]; then SEEDBOX_DETAIL="SSH tunnel down"
    else SEEDBOX_DETAIL="auth failed (HTTP $code)"; fi
    return 1
  fi
  n=$(curl -s --max-time 15 -b "$ck" "http://localhost:${SEEDBOX_PORT}/api/v2/torrents/info" 2>/dev/null \
      | grep -o '"hash"' | wc -l | tr -d ' ')
  rm -f "$ck"
  SEEDBOX_DETAIL="${n} torrents"
  return 0
}

# --- Run enabled checks ---
results=()

[ "$CHECK_STASH"        = "true" ] && { check_http "http://localhost:${STASH_PORT}"        && results+=("Stash|up")        || results+=("Stash|down"); }
[ "$CHECK_STASHY"       = "true" ] && { check_http "http://${STASHY_HOST}:${STASH_PORT}"    && results+=("Stashy (remote)|up") || results+=("Stashy (remote)|down"); }
[ "$CHECK_STASHARR"     = "true" ] && { check_http "http://localhost:${STASHARR_PORT}"      && results+=("Stasharr|up")     || results+=("Stasharr|down"); }
[ "$CHECK_WHISPARR"     = "true" ] && { check_http "http://localhost:${WHISPARR_PORT}/ping" && results+=("Whisparr|up")     || results+=("Whisparr|down"); }
[ "$CHECK_RADARR"       = "true" ] && { check_http "http://localhost:${RADARR_PORT}/ping"   && results+=("Radarr|up")       || results+=("Radarr|down"); }
[ "$CHECK_SONARR"       = "true" ] && { check_http "http://localhost:${SONARR_PORT}/ping"   && results+=("Sonarr|up")       || results+=("Sonarr|down"); }
# Jellyseerr redirects / to the setup or login page, so probe the API instead
[ "$CHECK_JELLYSEERR"   = "true" ] && { check_http "http://localhost:${JELLYSEERR_PORT}/api/v1/status" && results+=("Jellyseerr|up") || results+=("Jellyseerr|down"); }
[ "$CHECK_JELLYFIN"     = "true" ] && { check_http "http://localhost:${JELLYFIN_PORT}/System/Info/Public" && results+=("Jellyfin|up") || results+=("Jellyfin|down"); }
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
BOOTDISK_DETAIL=""
if [ "$CHECK_BOOT_DISK" = "true" ]; then
  _bd=$(boot_disk_free_gb)
  if [ -z "$_bd" ]; then
    BOOTDISK_DETAIL="could not read"; results+=("Boot disk|unknown")
  elif [ "$_bd" -lt "$BOOT_DISK_MIN_GB" ]; then
    BOOTDISK_DETAIL="${_bd} GB free - macOS swap lives here"; results+=("Boot disk|down")
  else
    BOOTDISK_DETAIL="${_bd} GB free"; results+=("Boot disk|up")
  fi
fi
DRIVETEMP_DETAIL=""
if [ "$CHECK_DRIVE_TEMP" = "true" ]; then
  _dt=$(drive_temp_max_c)
  if [ -z "$_dt" ]; then
    :   # enclosure powered off, or smartctl missing - not a fault, stay silent
  elif [ "$_dt" -ge "$DRIVE_TEMP_WARN_C" ]; then
    DRIVETEMP_DETAIL="${_dt} C - above ${DRIVE_TEMP_WARN_C} C, check the fan"; results+=("Backup drives|down")
  else
    DRIVETEMP_DETAIL="hottest ${_dt} C"; results+=("Backup drives|up")
  fi
fi
[ "$CHECK_QUI"          = "true" ] && { check_http "http://localhost:${QUI_PORT}"           && results+=("qui|up")          || results+=("qui|down"); }
if [ "$CHECK_JOBS" = "true" ]; then
    check_jobs; rc=$?
    case $rc in
      0) results+=("Long jobs|up") ;;
      1) results+=("Long jobs|down") ;;
      *) results+=("Long jobs|unknown") ;;
    esac
  fi
  if [ "$CHECK_SEEDBOX" = "true" ]; then
  check_seedbox; rc=$?
  case $rc in
    0) results+=("Seedbox|up") ;;
    1) results+=("Seedbox|down") ;;
    *) results+=("Seedbox|unknown") ;;
  esac
fi
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
    if [ "$name" = "Boot disk" ] && [ -n "$BOOTDISK_DETAIL" ]; then
      echo "--$BOOTDISK_DETAIL | color=gray size=11"
    fi
    if [ "$name" = "Backup drives" ] && [ -n "$DRIVETEMP_DETAIL" ]; then
      echo "--$DRIVETEMP_DETAIL | color=gray size=11"
    fi
    if [ "$name" = "Long jobs" ] && [ -n "$JOBS_DETAIL" ]; then
      echo "--$JOBS_DETAIL | color=gray size=11"
    fi
    if [ "$name" = "Seedbox" ] && [ -n "$SEEDBOX_DETAIL" ]; then
      echo "--$SEEDBOX_DETAIL | color=gray size=11"
    fi
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
    [ "$CHECK_RADARR"   = "true" ] && echo "--Open Radarr | href=http://localhost:${RADARR_PORT}"
    [ "$CHECK_SONARR"   = "true" ] && echo "--Open Sonarr | href=http://localhost:${SONARR_PORT}"
    [ "$CHECK_JELLYSEERR" = "true" ] && echo "--Open Jellyseerr | href=http://localhost:${JELLYSEERR_PORT}"
    [ "$CHECK_JELLYFIN" = "true" ] && echo "--Open Jellyfin | href=http://localhost:${JELLYFIN_PORT}"
    [ "$CHECK_PROWLARR" = "true" ] && echo "--Open Prowlarr | href=http://localhost:${PROWLARR_PORT}"
    [ "$CHECK_QBITTORRENT" = "true" ] && echo "--Open qBittorrent | href=http://localhost:${QBITTORRENT_PORT}"
    [ "$CHECK_QUI"      = "true" ] && echo "--Open qui | href=http://localhost:${QUI_PORT}"
    [ "$CHECK_SEEDBOX"  = "true" ] && echo "--Open Seedbox | href=http://localhost:${SEEDBOX_PORT}"
    [ "$CHECK_HOMARR" = "true" ] && echo "--Open Homarr | href=http://localhost:${HOMARR_PORT}"
    # Homarr controls, folded in from the standalone launcher plugin so there is
    # only ONE menu bar icon. The launcher script still lives at the path below;
    # it is just no longer a SwiftBar plugin in its own right.
    if [ "$CHECK_HOMARR" = "true" ] && [ -x "$HOMARR_LAUNCHER" ]; then
      echo "--Restart Homarr | bash=\"$HOMARR_LAUNCHER\" param1=restart terminal=false refresh=true"
      echo "--Stop Homarr | bash=\"$HOMARR_LAUNCHER\" param1=stop terminal=false refresh=true"
    fi
    [ "$CHECK_GLANCES" = "true" ] && echo "--Open Glances | href=http://localhost:${GLANCES_PORT}"
    echo "---"
  fi

  [ "$CHECK_STASH"    = "true" ] && echo "Open Stash | href=http://localhost:${STASH_PORT}"
  [ "$CHECK_STASHARR" = "true" ] && echo "Open Stasharr | href=http://localhost:${STASHARR_PORT}/login"
  [ -n "$STASHDB_URL" ]          && echo "Open StashDB | href=${STASHDB_URL}"
  [ "$CHECK_WHISPARR" = "true" ] && echo "Open Whisparr | href=http://localhost:${WHISPARR_PORT}"
  [ "$CHECK_SONARR"   = "true" ] && echo "Open Sonarr | href=http://localhost:${SONARR_PORT}"
  [ "$CHECK_JELLYSEERR" = "true" ] && echo "Open Jellyseerr | href=http://localhost:${JELLYSEERR_PORT}"
  [ "$CHECK_RADARR"   = "true" ] && echo "Open Radarr | href=http://localhost:${RADARR_PORT}"
  [ "$CHECK_JELLYFIN" = "true" ] && echo "Open Jellyfin | href=http://localhost:${JELLYFIN_PORT}"
  [ "$CHECK_PROWLARR" = "true" ] && echo "Open Prowlarr | href=http://localhost:${PROWLARR_PORT}"
  [ "$CHECK_QBITTORRENT" = "true" ] && echo "Open qBittorrent | href=http://localhost:${QBITTORRENT_PORT}"
  [ "$CHECK_QUI"      = "true" ] && echo "Open qui | href=http://localhost:${QUI_PORT}"
  [ "$CHECK_SEEDBOX"  = "true" ] && echo "Open Seedbox | href=http://localhost:${SEEDBOX_PORT}"
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
    if [ "$name" = "Boot disk" ] && [ -n "$BOOTDISK_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$BOOTDISK_DETAIL"
    fi
    if [ "$name" = "Backup drives" ] && [ -n "$DRIVETEMP_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$DRIVETEMP_DETAIL"
    fi
    if [ "$name" = "Long jobs" ] && [ -n "$JOBS_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$JOBS_DETAIL"
    fi
    if [ "$name" = "Seedbox" ] && [ -n "$SEEDBOX_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$SEEDBOX_DETAIL"
    fi
    if [ "$name" = "Time Machine" ] && [ -n "$TM_DETAIL" ]; then
      printf "                   \033[90m%s\033[0m\n" "$TM_DETAIL"
    fi
  done
  printf "\n"
fi
