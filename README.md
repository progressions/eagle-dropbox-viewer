# Eagle Dropbox Viewer

Internet Phoenix app to browse Isaac’s Eagle libraries over **Dropbox OAuth** (LTE, Ginger asleep).

**Plan:** `~/Dropbox/ISAAC/GENNIE/Ops/eagle-dropbox-viewer.md`  
**Not this:** LAN phone browse (`eagle-browse` / `http://eagle.local:8788`) — that stays as-is.

Repo: https://github.com/progressions/eagle-dropbox-viewer

## What works now

- Single-user login (`APP_USERNAME` / `APP_PASSWORD`)
- Dropbox OAuth (offline refresh): `files.metadata.read`, `files.content.read`, `account_info.read`
- Settings page: connect / disconnect + sample `list_folder` of `DROPBOX_LIBRARY_PATH`
- Tokens encrypted at rest (AES-GCM via endpoint `secret_key_base`) and never sent to the browser

Still out of scope: Eagle grid, `phone-index.json` sync, media proxy, Fly deploy.

## Setup

1. Create a Dropbox app at https://www.dropbox.com/developers/apps  
   - Access type: **Full Dropbox** (library lives under `/ISAAC/GENNIE/...`)  
   - Permissions tab: enable the three scopes above  
   - OAuth 2 redirect URI: `http://localhost:4010/auth/dropbox/callback`

2. Copy env:

```bash
cd ~/tech/eagle_dropbox_viewer
cp .env.example .env
# fill APP_PASSWORD, DROPBOX_APP_KEY, DROPBOX_APP_SECRET
set -a && source .env && set +a
```

3. DB + server (port **4010** — PromptForge uses 4000):

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
PORT=4010 mix phx.server
```

4. Open http://localhost:4010 → sign in → **Connect Dropbox**.

## Routes

| Path | Notes |
|------|--------|
| `/login` | App gate |
| `/settings` | Connect status + sample listing |
| `/auth/dropbox` | Start OAuth |
| `/auth/dropbox/callback` | OAuth callback |
| `POST /auth/dropbox/disconnect` | Clear stored tokens |

## Security notes

- Put this behind HTTPS in production; keep `APP_*` and Dropbox secrets out of git.
- Refresh tokens live only in Postgres (ciphertext). Revoke from Dropbox Connected apps if needed.

## Local Postgres (Docker)

```bash
sudo docker compose up -d
mix ecto.create && mix ecto.migrate
```

Defaults: `postgres`/`postgres` @ `127.0.0.1:5432`, db `eagle_dropbox_viewer_dev`.


## Sync + browse

With Dropbox connected:

1. Settings → **Sync index now** (downloads `phone-index.json`)
2. Open **Browse** (`/browse`) for the recent grid
3. Click a cell for detail; thumbs/originals use Dropbox temporary links via `/media/...`
