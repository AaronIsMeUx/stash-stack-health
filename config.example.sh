# Stash Stack Health — user configuration
# Copy this file to ~/.config/stash-stack-health/config.sh and edit to match your setup.

# --- Enable or disable each service check (true/false) ---
CHECK_STASH=true
CHECK_WHISPARR=true
CHECK_PROWLARR=true
CHECK_FLARESOLVERR=true
CHECK_QBITTORRENT=true
CHECK_DOCKER=true

# Set to true and set MEDIA_DRIVE_PATH below to monitor your media drive mount
CHECK_MEDIA_DRIVE=false
MEDIA_DRIVE_PATH="/Volumes/YOUR_DRIVE_NAME"

# --- Ports (change if your services run on non-default ports) ---
STASH_PORT=9999
WHISPARR_PORT=6969
PROWLARR_PORT=9696
FLARESOLVERR_PORT=8191
QBITTORRENT_PORT=8080

# --- Links shown in the SwiftBar dropdown ---
# Set to empty string "" to hide a link
STASHDB_URL="https://stashdb.org"
