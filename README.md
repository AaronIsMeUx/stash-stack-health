# Stash Stack Health

A [SwiftBar](https://github.com/swiftbar/SwiftBar) menubar plugin for macOS that monitors your self-hosted [Stash](https://stashapp.cc) media automation stack.

At a glance:
- 🟢 All services healthy
- 🟡 One or two services down
- 🔴 Multiple services down

Click the indicator for a live status breakdown and quick-launch links for each service.

![Stash Stack Health menubar screenshot](screenshot.png)

---

## What it monitors

| Service | Default port | Notes |
|---|---|---|
| [Stash](https://stashapp.cc) | 9999 | Native Mac app or Docker |
| [Whisparr](https://github.com/Whisparr/Whisparr) | 6969 | Adult content Arr |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | 9696 | Indexer manager |
| [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) | 8191 | Cloudflare bypass |
| [qBittorrent](https://www.qbittorrent.org) | 8080 | Download client |
| Docker daemon | — | Required for containerized services |
| Media drive | — | Optional: monitors an external drive mount |

All services are individually toggleable. Runs any combination — Radarr, Sonarr, Transmission, etc. can replace any of the defaults via `config.sh`.

---

## Requirements

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (free, open source)
- `curl` (pre-installed on macOS)
- `docker` CLI (only if `CHECK_DOCKER=true`)

---

## Install

**1. Install SwiftBar** if you haven't already:
```bash
brew install --cask swiftbar
```

**2. Copy the plugin** to your SwiftBar plugins folder:
```bash
cp stash-stack-health.5m.sh ~/Library/Application\ Support/SwiftBar/Plugins/
chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/stash-stack-health.5m.sh
```

The `.5m.` in the filename tells SwiftBar to refresh every 5 minutes. Rename to `.1m.` for every minute, `.30s.` for every 30 seconds, etc.

**3. Configure** (optional but recommended):
```bash
mkdir -p ~/.config/stash-stack-health
cp config.example.sh ~/.config/stash-stack-health/config.sh
# Edit ~/.config/stash-stack-health/config.sh to match your setup
```

**4. Refresh SwiftBar** — right-click the SwiftBar icon → Refresh All. Your stack indicator will appear in the menu bar.

---

## Configuration

Copy `config.example.sh` to `~/.config/stash-stack-health/config.sh` and edit:

```bash
# Disable services you don't run
CHECK_FLARESOLVERR=false
CHECK_WHISPARR=false

# Monitor an external media drive
CHECK_MEDIA_DRIVE=true
MEDIA_DRIVE_PATH="/Volumes/MY MEDIA DRIVE"

# Custom ports
STASH_PORT=9999
QBITTORRENT_PORT=8080

# Hide StashDB link from dropdown
STASHDB_URL=""
```

---

## Manual run

You can also run the health check directly in your terminal:

```bash
bash stash-stack-health.5m.sh
```

---

## Notifications

When a service changes state (healthy → degraded or vice versa), a macOS notification fires automatically. You won't get spammed on every refresh — only on state changes.

---

## License

MIT — see [LICENSE](LICENSE).
