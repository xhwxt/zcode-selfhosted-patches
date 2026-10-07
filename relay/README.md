# Remote-control relay (official mobile page ↔ self-hosted server)

`relay-v28.mjs` is a small, dependency-light Node service (~450 lines) that lets the
**official ZCode mobile remote-control page** run against a **self-hosted server**.

The official page is written for the vendor relay: it bootstraps its task list from
`/api/remote-control/...`, opens a control WebSocket, and asks for a `wsUrl` before
it talks to a server. This relay answers exactly those calls, reads the task list
from the same `tasks-index.sqlite` the local UI uses, and hands the page a
WebSocket URL pointing at your own server — no vendor relay, no vendor account.

It also **pins the page version** to the version of your server. That matters:
the vendor serves different page bundles per `app_version`, and an older page
rejects frames containing newer tool cards — which shows up as
`fault.subscription.recoveryFailed` in the UI.

```
phone ── HTTPS ──▶ nginx ──┬─ /web-remote, /remote/, /api/remote-control/ ─▶ relay :3032
                           ├─ /ws/remote-control/            (WS upgrade)  ─▶ relay :3032
                           └─ /, /api/*, /ws                              ─▶ server :3030
```

## What it serves

| Route | Purpose |
|---|---|
| `GET /web-remote` | Entry page (mirror of the pinned official page, with a recovery shim injected). Also `/remote/v4` |
| `GET /remote/v4/<version>/assets/*` | Page assets, served from the local mirror when present |
| `GET /api/v1/client/configs` | UI config JSON (mirrored, so the page never calls the vendor host) |
| `GET /api/remote-control/windows/bootstrap/<token>` | Task list + workspaces (read from `tasks-index.sqlite`, read-only) |
| `WS  /ws/remote-control/window/<token>` | Control channel; replies `window-control-ready` |
| `POST /api/remote-control/windows/<token>/workspace-bridge` | Hands the page its `wsUrl` (your server) |
| `POST /api/remote-control/windows/<token>/mobile-view-state` | Remembers the active workspace/task so a page reload returns to the same conversation |
| `POST /api/remote-control/platform/<token>` | Platform stub |

Everything under `/api/remote-control/` and the control WebSocket is authenticated
with `ZCODE_REMOTE_TOKEN` (constant-time compare; mismatch → 403 / socket destroy).

## Requirements

- Node 24+ (uses `node:sqlite`)
- the `ws` package — resolved from `ZCODE_WS_MODULE`, then `ws` from `node_modules`,
  then a copy shipped next to an installed ZCode
- a running ZCode web server (`zcode-web`), reachable at `ZCODE_HOST_ORIGIN`

## Configuration

| Env | Default | Meaning |
|---|---|---|
| `ZCODE_RELAY_PORT` | `3032` | Listen port (binds `127.0.0.1`) |
| `ZCODE_REMOTE_TOKEN` | — (required) | Token the page presents (`/web-remote?remoteControlToken=…`) |
| `ZCODE_SERVER_TOKEN` | — (required) | Token of your ZCode server (`--token`); passed to the page inside `wsUrl` |
| `ZCODE_HOST_ORIGIN` | `http://127.0.0.1:3030` | Your ZCode server |
| `ZCODE_BRIDGE_PUBLIC_WS` | derived from the request `Host` | WS URL handed to the page; set it explicitly when nginx terminates TLS (e.g. `wss://your.host/ws`) |
| `ZCODE_TASKS_DB` | `<install>/…/tasks-index.sqlite` | Task index read for the task list |
| `ZCODE_CONVERSATION_WORKSPACE` | `<dataBaseDir>/.zcode/workspace/default` | The shared "not in a project" workspace |
| `ZCODE_REMOTE_MIRROR` | `/opt/zcode-remote-mirror` | Local page mirror (optional; see below) |

`ZCODE_BRIDGE_PUBLIC_WS` is derived as `wss://<host>/ws` (or `ws://` for plain HTTP),
honouring `X-Forwarded-Proto` / `X-Forwarded-Host`, so a proxy setup usually needs no
extra configuration.

## Run

```bash
npm i ws                     # or point ZCODE_WS_MODULE at an existing ws entry
ZCODE_REMOTE_TOKEN=… ZCODE_SERVER_TOKEN=… \
  node relay-v28.mjs
# → 桥监听 127.0.0.1:3032
# → entry: /web-remote?remoteControlToken=<ZCODE_REMOTE_TOKEN>
```

systemd unit:

```ini
[Unit]
Description=ZCode remote-control relay
After=network.target zcode-web.service
BindsTo=zcode-web.service
PartOf=zcode-web.service

[Service]
Type=simple
WorkingDirectory=/opt/zcode-relay
Environment=ZCODE_RELAY_PORT=3032
Environment=ZCODE_REMOTE_TOKEN=change-me
Environment=ZCODE_SERVER_TOKEN=change-me
Environment=ZCODE_BRIDGE_PUBLIC_WS=wss://your.host/ws
ExecStart=/usr/bin/node /opt/zcode-relay/relay-v28.mjs
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

nginx (TLS terminated here):

```nginx
location /web-remote { proxy_pass http://127.0.0.1:3032; }
location /remote/    { proxy_pass http://127.0.0.1:3032; }
location /api/remote-control/ { proxy_pass http://127.0.0.1:3032; }

location /ws/remote-control/ {          # WebSocket upgrade required
    proxy_pass http://127.0.0.1:3032;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}

location / { proxy_pass http://127.0.0.1:3030; }   # the ZCode server itself
```

Put `ZCODE_HOST_ORIGIN` behind the same proxy so the page and the API share an origin.

## Optional: local page mirror (offline mode)

When `ZCODE_REMOTE_MIRROR` contains `index.html` plus the referenced assets, the page
is served entirely from disk and the browser makes **no request to the vendor host**
(the relay also answers `/api/v1/client/configs` from `client-configs.json` in the
mirror). Without a mirror the relay proxies the pinned page from the vendor host
instead — that still works, it just is not offline.

The mirror keeps the official URL layout, e.g.:

```
<mirror>/index.html                              # https://<vendor>/remote/v4?app_version=<ver>
<mirror>/remote/v4/<ver>/assets/…                # every asset the HTML references (2.4k files)
<mirror>/client-configs.json                     # https://<vendor>/api/v1/client/configs
```

Fetch it once with any recursive mirror tool (`wget --recursive --page-requisites
--convert-links=off`, `httrack`, or a short script), keeping the paths above. Note
that these assets belong to the vendor — fetch them for your own deployment rather
than redistributing them.

## Notes and limits

- Pin `PAGE_VERSION` (top of the file) to the version of your ZCode server; a
  mismatched page is the usual cause of frame-rejection errors in the UI.
- The relay never stores conversation content: the task list is a read-only query,
  the view state is held in memory only.
- The recovery shim injected into the page only handles the page's own WebSocket
  lifecycle (banner + rate-limited reload on abnormal close, reload when the socket
  died while the tab was hidden). It does not touch conversation content.
- One relay serves one ZCode server; run it on the same host as the server.
