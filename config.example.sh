# Stash Stack Health — user configuration
# Copy this file to ~/.config/stash-stack-health/config.sh and edit to match your setup.

# --- Enable or disable each service check (true/false) ---
CHECK_STASH=true
CHECK_STASHY=true
CHECK_STASHARR=true
CHECK_WHISPARR=true
CHECK_PROWLARR=true
CHECK_PROWLARR_INDEXERS=true
CHECK_FLARESOLVERR=true
CHECK_QBITTORRENT=true
CHECK_HOMARR=true
CHECK_GLANCES=true
CHECK_DOCKER=true

# Set to true and set MEDIA_DRIVE_PATH below to monitor your media drive mount
CHECK_MEDIA_DRIVE=false
MEDIA_DRIVE_PATH="/Volumes/YOUR_DRIVE_NAME"

# --- Stashy (iPhone app) remote-access check ---
# Verifies Stash is reachable from a phone/other device (bound beyond localhost).
# Use your Mac's LAN IP for home WiFi, or a Tailscale/VPN IP for remote access.
STASHY_HOST="192.168.1.50"

# --- Ports (change if your services run on non-default ports) ---
STASH_PORT=9999
STASHARR_PORT=3000
WHISPARR_PORT=6969
PROWLARR_PORT=9696
FLARESOLVERR_PORT=8191
QBITTORRENT_PORT=8080
HOMARR_PORT=7575
GLANCES_PORT=61208

# --- Prowlarr indexer health ---
# CHECK_PROWLARR above only pings Prowlarr's port. That can answer perfectly while
# every indexer is failing (expired tracker cookie), so search dies silently while
# the light stays green. CHECK_PROWLARR_INDEXERS asks Prowlarr's health API whether
# any indexers are actually unavailable, and names them in the dropdown.
# Leave the key empty to auto-read it from the Docker container named below.
PROWLARR_API_KEY=""
PROWLARR_CONTAINER="prowlarr"

# --- Links shown in the SwiftBar dropdown ---
# Set to empty string "" to hide a link
STASHDB_URL="https://stashdb.org"

# Show a dedicated shortcut submenu in the menu bar dropdown
OPEN_SHORTCUTS=true

# --- Radarr (movies) and Jellyfin (media server) -----------------------------
CHECK_RADARR=true
RADARR_PORT=7878
CHECK_JELLYFIN=true
JELLYFIN_PORT=8096

# --- Optional extras --------------------------------------------------------
# These default to FALSE in the script so a fresh install never reports a
# service you do not run. Set to true only for the ones you actually have.

# qui - alternative qBittorrent web UI
CHECK_QUI=false
QUI_PORT=7476

# Long-running supervised jobs (github.com/... jobrunner). Flags a job that has
# died or stalled, which is otherwise invisible until you go looking.
CHECK_JOBS=false
# JOBRUNNER_PATH="$HOME/tools/jobrunner/jobrunner.py"

# A remote seedbox's qBittorrent, reached over a local SSH tunnel.
# Checks the whole chain: tunnel up, credentials valid, client answering.
CHECK_SEEDBOX=false
SEEDBOX_PORT=29963
SEEDBOX_USER=""
SEEDBOX_PASS=""

# --- Functional checks (v1.10.0, in extra-checks.sh) -------------------------
# These catch failures where a service still answers its port but has stopped
# doing its job. Keep extra-checks.sh next to the plugin script.

# qBittorrent: ON by default.
CHECK_QBIT_NET=true        # connected to the network, DHT nodes, torrent port listening
CHECK_QBIT_FDS=true        # macOS open-files limit is high enough (default 256 is not)
CHECK_QBIT_TRACKERS=true   # share of active torrents that have announced to a tracker
CHECK_QBIT_STUCK=true      # downloads with zero progress after STUCK_MINUTES
MAXFILES_MIN=65536
STUCK_MINUTES=60

# Setup-specific: OFF by default. Enable only the ones that apply to you.

# A gateway or reverse proxy that must answer (one can be running yet serve nothing).
CHECK_CABLE_GATEWAY=false
CABLE_GATEWAY_URL=""                     # e.g. "http://192.168.1.50:8443/"
CABLE_GATEWAY_FIX="restart the proxy"    # hint shown in the dropdown when it fails

# A Stash plugin you patched by hand. Turns red if an update overwrote your patch.
CHECK_STASH_PLUGIN_PATCH=false
STASH_PLUGIN_FILE=""                     # full path to the patched .js/.py file
STASH_PLUGIN_MARKER=""                   # text that only exists in your patched version

# Seedbox free space, computed from torrent sizes (needs the CHECK_SEEDBOX settings above).
CHECK_SEEDBOX_SPACE=false
SEEDBOX_PLAN_TB=""                       # your plan's storage in TB, e.g. 4
SEEDBOX_MIN_FREE_GB=150                  # warn below this; red below 50 GB
SEEDBOX_RETENTION_LOG=""                 # optional: log of a cleanup job; "DEAD WEIGHT EXHAUSTED" in it is flagged

# --- Check 8: files that must stay under a size / line limit (OFF by default) ---
# Useful for files a tool silently truncates, e.g. an AI assistant's memory index.
CHECK_FILE_SIZES=false
FILE_SIZE_WARN_PCT=90        # yellow at this % of the limit, red at 100%
# FILE_SIZE_WATCH=("Label|/path/to/file|max_kb|max_lines")   # max_lines optional
