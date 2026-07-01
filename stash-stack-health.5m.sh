#!/usr/bin/env bash
# <xbar.title>Stash Stack Health</xbar.title>
# <xbar.version>v1.3.0</xbar.version>
# <xbar.author>AaronIsMeUx</xbar.author>
# <xbar.author.github>AaronIsMeUx</xbar.author.github>
# <xbar.desc>Menubar health monitor for a Mac-hosted Stash + Arr media automation stack. Checks Stash, Stashy (remote access), Whisparr, Prowlarr, FlareSolverr, qBittorrent, Homarr, Glances, Docker, and your media drive. Fully configurable.</xbar.desc>
# <xbar.dependencies>bash,curl,docker</xbar.dependencies>
# <xbar.abouturl>https://github.com/AaronIsMeUx/stash-stack-health</xbar.abouturl>
# <swiftbar.hideAbout>false</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>false</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>false</swiftbar.hideDisablePlugin>

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
CHECK_FLARESOLVERR="${CHECK_FLARESOLVERR:-true}"
CHECK_QBITTORRENT="${CHECK_QBITTORRENT:-true}"
CHECK_HOMARR="${CHECK_HOMARR:-true}"
CHECK_GLANCES="${CHECK_GLANCES:-true}"
CHECK_DOCKER="${CHECK_DOCKER:-true}"
CHECK_MEDIA_DRIVE="${CHECK_MEDIA_DRIVE:-false}"

STASH_PORT="${STASH_PORT:-9999}"
STASHARR_PORT="${STASHARR_PORT:-3000}"
WHISPARR_PORT="${WHISPARR_PORT:-6969}"
PROWLARR_PORT="${PROWLARR_PORT:-9696}"
FLARESOLVERR_PORT="${FLARESOLVERR_PORT:-8191}"
QBITTORRENT_PORT="${QBITTORRENT_PORT:-8080}"
HOMARR_PORT="${HOMARR_PORT:-7575}"
GLANCES_PORT="${GLANCES_PORT:-61208}"

MEDIA_DRIVE_PATH="${MEDIA_DRIVE_PATH:-}"

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

# --- Run enabled checks ---
results=()

[ "$CHECK_STASH"        = "true" ] && { check_http "http://localhost:${STASH_PORT}"        && results+=("Stash|up")        || results+=("Stash|down"); }
[ "$CHECK_STASHY"       = "true" ] && { check_http "http://${STASHY_HOST}:${STASH_PORT}"    && results+=("Stashy (remote)|up") || results+=("Stashy (remote)|down"); }
[ "$CHECK_STASHARR"     = "true" ] && { check_http "http://localhost:${STASHARR_PORT}"      && results+=("Stasharr|up")     || results+=("Stasharr|down"); }
[ "$CHECK_WHISPARR"     = "true" ] && { check_http "http://localhost:${WHISPARR_PORT}/ping" && results+=("Whisparr|up")     || results+=("Whisparr|down"); }
[ "$CHECK_PROWLARR"     = "true" ] && { check_http "http://localhost:${PROWLARR_PORT}/ping" && results+=("Prowlarr|up")     || results+=("Prowlarr|down"); }
[ "$CHECK_FLARESOLVERR" = "true" ] && { check_http "http://localhost:${FLARESOLVERR_PORT}/health" && results+=("FlareSolverr|up") || results+=("FlareSolverr|down"); }
[ "$CHECK_QBITTORRENT"  = "true" ] && { check_http "http://localhost:${QBITTORRENT_PORT}"  && results+=("qBittorrent|up")  || results+=("qBittorrent|down"); }
[ "$CHECK_HOMARR"       = "true" ] && { check_http "http://localhost:${HOMARR_PORT}"        && results+=("Homarr|up")       || results+=("Homarr|down"); }
[ "$CHECK_GLANCES"      = "true" ] && { check_http "http://localhost:${GLANCES_PORT}"       && results+=("Glances|up")      || results+=("Glances|down"); }
[ "$CHECK_DOCKER"       = "true" ] && { check_docker                                        && results+=("Docker|up")       || results+=("Docker|down"); }
[ "$CHECK_MEDIA_DRIVE"  = "true" ] && { check_drive                                         && results+=("Media drive|up")  || results+=("Media drive|down"); }

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
    [ "$status" = "up" ] && echo "$name ✓ | color=green" || echo "$name ✗ | color=red"
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
  echo "Stash Stack Health v1.3.0 | color=gray size=11"

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
  printf "%-15s %s\n" "SERVICE" "STATUS"
  printf "%-15s %s\n" "-------" "------"
  for r in "${results[@]}"; do
    name="${r%|*}"; status="${r#*|}"
    [ "$status" = "up" ] && printf "%-15s \033[32m✓ up\033[0m\n" "$name" || printf "%-15s \033[31m✗ down\033[0m\n" "$name"
  done
  printf "\n"
fi
