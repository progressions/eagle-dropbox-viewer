# Eagle Dropbox Viewer

Internet Phoenix app to browse Isaac’s Eagle libraries over Dropbox OAuth (LTE, Ginger asleep).

**Plan:** `~/Dropbox/ISAAC/GENNIE/Ops/eagle-dropbox-viewer.md`  
**Not this:** LAN phone browse (`eagle-browse` / `http://eagle.local:8788`) — that stays as-is.

## Setup

```bash
cd ~/tech/eagle_dropbox_viewer
mix deps.get
# Edit config/dev.exs database name if needed (default eagle_dropbox_viewer_dev)
mix ecto.create
mix phx.server
```

Default Phoenix port is **4000**. PromptForge already uses that on Ginger — run this on another port for local smoke:

```bash
PORT=4010 mix phx.server
```

## Next (not scaffolded yet)

- App login (single user)
- Dropbox OAuth (`files.metadata.read` + `files.content.read`)
- Sync `phone-index.json` → Postgres
- LiveView grid + detail + search

Dropbox app: https://www.dropbox.com/developers/apps
