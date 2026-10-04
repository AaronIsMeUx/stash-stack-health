# extra-checks.sh - sourced by stash-stack-health.5m.sh (v1.10.0).
# FUNCTIONAL checks for failures that look "up" to a simple ping. Each appends to results[]
# ("Name|up/warn/down/unknown") and to EXTRA_DETAILS[] ("Name|detail line") for the menu.
# None of them read disk SMART, so they never wake sleeping drives.
# The four qBittorrent checks are ON by default. The three setup-specific checks (5-7) are OFF
# until you enable and configure them in config.sh.
CHECK_QBIT_NET="${CHECK_QBIT_NET:-true}"
CHECK_QBIT_FDS="${CHECK_QBIT_FDS:-true}"
CHECK_QBIT_TRACKERS="${CHECK_QBIT_TRACKERS:-true}"
CHECK_QBIT_STUCK="${CHECK_QBIT_STUCK:-true}"
CHECK_CABLE_GATEWAY="${CHECK_CABLE_GATEWAY:-false}"
CHECK_STASH_PLUGIN_PATCH="${CHECK_STASH_PLUGIN_PATCH:-false}"
CHECK_SEEDBOX_SPACE="${CHECK_SEEDBOX_SPACE:-false}"
MAXFILES_MIN="${MAXFILES_MIN:-65536}"
SEEDBOX_PLAN_TB="${SEEDBOX_PLAN_TB:-}"
SEEDBOX_MIN_FREE_GB="${SEEDBOX_MIN_FREE_GB:-150}"
STUCK_MINUTES="${STUCK_MINUTES:-60}"
CABLE_GATEWAY_URL="${CABLE_GATEWAY_URL:-}"
CABLE_GATEWAY_FIX="${CABLE_GATEWAY_FIX:-restart the proxy}"
STASH_PLUGIN_FILE="${STASH_PLUGIN_FILE:-}"
STASH_PLUGIN_MARKER="${STASH_PLUGIN_MARKER:-}"
SEEDBOX_RETENTION_LOG="${SEEDBOX_RETENTION_LOG:-}"
EXTRA_DETAILS=()
_qb="http://localhost:${QBITTORRENT_PORT:-8080}/api/v2"
_py=$(command -v /opt/homebrew/bin/python3 /usr/local/bin/python3 python3 2>/dev/null | head -1)
_qbpid=$(pgrep -x qbittorrent | head -1)
_qbup=0; [ -n "$_qbpid" ] && _qbup=$(( $(date +%s) - $(date -j -f "%a %b %d %T %Y" "$(ps -o lstart= -p "$_qbpid" | sed 's/  */ /g')" +%s 2>/dev/null || date +%s) ))

# 1. qBittorrent actually connected (not just the web page answering)
if [ "$CHECK_QBIT_NET" = "true" ] && [ -n "$_qbpid" ]; then
  _ti=$(curl -s --max-time 8 "$_qb/transfer/info")
  _st=$(printf '%s' "$_ti" | $_py -c "import sys,json;t=json.load(sys.stdin);print(t['connection_status'],t['dht_nodes'],round(t['up_info_speed']*8/1e6,1),round(t['dl_info_speed']*8/1e6,1))" 2>/dev/null)
  set -- $_st
  _ports=$(/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -a -p "$_qbpid" 2>/dev/null | grep -v ":${QBITTORRENT_PORT:-8080} " | grep -c LISTEN)
  if [ -z "$_st" ]; then results+=("qBit network|unknown")
  elif [ "$1" = "connected" ] || { [ "${2:-0}" -gt 0 ] && [ "${_ports:-0}" -gt 0 ]; }; then
    results+=("qBit network|up"); EXTRA_DETAILS+=("qBit network|$1, DHT $2, up $3 / down $4 Mbit/s")
  elif [ "$_qbup" -lt 600 ]; then
    results+=("qBit network|warn"); EXTRA_DETAILS+=("qBit network|starting up ($((_qbup/60)) min) - $1, DHT $2")
  else
    results+=("qBit network|down"); EXTRA_DETAILS+=("qBit network|$1, DHT $2, torrent port open: $([ "${_ports:-0}" -gt 0 ] && echo yes || echo NO) - quit and reopen qBittorrent")
  fi
fi

# 2. Open-files headroom. macOS defaults to 256 open files; a busy torrent client hits that and
#    silently stops announcing and connecting while its web page still answers.
if [ "$CHECK_QBIT_FDS" = "true" ]; then
  _lim=$(launchctl limit maxfiles 2>/dev/null | awk '{print $2}')
  if [ -n "$_lim" ] && [ "$_lim" -lt "$MAXFILES_MIN" ] 2>/dev/null; then
    results+=("Open-files limit|down"); EXTRA_DETAILS+=("Open-files limit|limit is $_lim (needs $MAXFILES_MIN) - raise it, see README")
  elif [ -n "$_qbpid" ]; then
    _used=$(/usr/sbin/lsof -p "$_qbpid" 2>/dev/null | wc -l | tr -d ' ')
    _pct=$(( _used * 100 / ${_lim:-256} ))
    if   [ "$_pct" -ge 95 ]; then results+=("Open-files limit|down")
    elif [ "$_pct" -ge 80 ]; then results+=("Open-files limit|warn")
    else results+=("Open-files limit|up"); fi
    EXTRA_DETAILS+=("Open-files limit|qBittorrent using $_used of $_lim (${_pct}%)")
  fi
fi

# 3+4. Trackers reachable + downloads stuck (one torrent list, no per-torrent calls)
if { [ "$CHECK_QBIT_TRACKERS" = "true" ] || [ "$CHECK_QBIT_STUCK" = "true" ]; } && [ -n "$_qbpid" ]; then
  _tq=$(curl -s --max-time 20 "$_qb/torrents/info" | $_py -c "
import sys,json,time
d=json.load(sys.stdin); now=time.time()
act=[t for t in d if not t['state'].startswith('stopped') and t['state'] not in ('error','missingFiles')]
noann=[t for t in act if not t.get('tracker')]
stuck=[t for t in act if t['progress']<1 and t['downloaded']==0 and now-t['added_on']>$STUCK_MINUTES*60]
print(len(act),len(noann),len(stuck))
for t in stuck[:5]: print(t['name'][:60])
" 2>/dev/null)
  _a=$(echo "$_tq" | sed -n 1p | awk '{print $1}'); _n=$(echo "$_tq" | sed -n 1p | awk '{print $2}'); _s=$(echo "$_tq" | sed -n 1p | awk '{print $3}')
  if [ "$CHECK_QBIT_TRACKERS" = "true" ] && [ -n "$_a" ]; then
    _np=$(( ${_n:-0} * 100 / (${_a:-0} + 1) ))
    if [ "$_qbup" -lt 1200 ]; then results+=("Trackers|up"); EXTRA_DETAILS+=("Trackers|qBittorrent started $((_qbup/60)) min ago - announcing ${_a} torrents")
    elif [ "$_np" -ge 25 ]; then results+=("Trackers|down"); EXTRA_DETAILS+=("Trackers|${_n} of ${_a} active torrents not announced (${_np}%)")
    elif [ "$_np" -ge 10 ]; then results+=("Trackers|warn"); EXTRA_DETAILS+=("Trackers|${_n} of ${_a} active torrents not announced (${_np}%)")
    else results+=("Trackers|up"); EXTRA_DETAILS+=("Trackers|$(( _a - _n )) of ${_a} active torrents announcing"); fi
  fi
  if [ "$CHECK_QBIT_STUCK" = "true" ] && [ -n "$_s" ]; then
    if [ "${_s:-0}" -gt 0 ]; then
      results+=("Stuck downloads|warn"); EXTRA_DETAILS+=("Stuck downloads|${_s} with no progress for ${STUCK_MINUTES}+ min (no seeders, or not announcing)")
      while IFS= read -r _l; do [ -n "$_l" ] && EXTRA_DETAILS+=("Stuck downloads|  $_l"); done <<< "$(echo "$_tq" | sed -n '2,6p')"
    else results+=("Stuck downloads|up"); fi
  fi
fi

# 5. A gateway / reverse proxy really serving (one can be running yet return nothing)
if [ "$CHECK_CABLE_GATEWAY" = "true" ] && [ -n "$CABLE_GATEWAY_URL" ]; then
  _gc=$(curl -s -o /dev/null --max-time 6 -w '%{http_code}' "$CABLE_GATEWAY_URL" 2>/dev/null)
  case "$_gc" in 2*|3*|401) results+=("Cable gateway|up") ;;
    *) results+=("Cable gateway|down"); EXTRA_DETAILS+=("Cable gateway|HTTP ${_gc:-000} from $CABLE_GATEWAY_URL - $CABLE_GATEWAY_FIX") ;; esac
fi

# 6. A plugin you patched locally still carries your patch (a plugin update silently overwrites it)
if [ "$CHECK_STASH_PLUGIN_PATCH" = "true" ] && [ -f "$STASH_PLUGIN_FILE" ] && [ -n "$STASH_PLUGIN_MARKER" ]; then
  if grep -qF "$STASH_PLUGIN_MARKER" "$STASH_PLUGIN_FILE"; then results+=("Stash plugin patch|up")
  else results+=("Stash plugin patch|down"); EXTRA_DETAILS+=("Stash plugin patch|$(basename "$STASH_PLUGIN_FILE") was updated and lost your patch - re-apply it"); fi
fi

# 7. Seedbox space vs plan size, plus (optionally) whether a cleanup job can still free anything
if [ "$CHECK_SEEDBOX_SPACE" = "true" ] && [ -n "${SEEDBOX_USER:-}" ] && [ -n "$SEEDBOX_PLAN_TB" ]; then
  _ck=$(mktemp)
  curl -s -o /dev/null --max-time 8 -c "$_ck" --data-urlencode "username=${SEEDBOX_USER}" --data-urlencode "password=${SEEDBOX_PASS}" "http://localhost:${SEEDBOX_PORT}/api/v2/auth/login" 2>/dev/null
  _used=$(curl -s --max-time 20 -b "$_ck" "http://localhost:${SEEDBOX_PORT}/api/v2/torrents/info" 2>/dev/null | $_py -c "import sys,json;print(int(sum(t['size'] for t in json.load(sys.stdin))/1e9))" 2>/dev/null)
  rm -f "$_ck"
  if [ -n "$_used" ]; then
    _free=$(awk -v p="$SEEDBOX_PLAN_TB" -v u="$_used" 'BEGIN{printf "%d", p*1000-u}')
    _ret=$([ -n "$SEEDBOX_RETENTION_LOG" ] && tail -6 "$SEEDBOX_RETENTION_LOG" 2>/dev/null | grep -q "DEAD WEIGHT EXHAUSTED" && echo " (cleanup job has nothing left to free)")
    if   [ "$_free" -lt 50 ]; then results+=("Seedbox space|down")
    elif [ "$_free" -lt "$SEEDBOX_MIN_FREE_GB" ]; then results+=("Seedbox space|warn")
    else results+=("Seedbox space|up"); fi
    EXTRA_DETAILS+=("Seedbox space|${_free} GB free of ${SEEDBOX_PLAN_TB} TB$_ret")
  else results+=("Seedbox space|unknown"); fi
fi
