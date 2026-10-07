# ZCode Self-Hosted Web Parity Patches

Enhancements that make a self-hosted [ZCode](https://github.com/zai-org/ZCode) web
deployment work as a standalone service (no desktop app required), for both the
built-in web UI ("direct page") and the official mobile remote-control page.

Base: ZCode v3.14.3 (commit `29628c9`).

## What's included

| # | Area | Problem | Fix |
|---|------|---------|-----|
| a | Remote page `@` menu | Official remote page (v3.14.0) calls the pre-3.14.3 one-shot `file.listWorkspaceFiles`; server only implements the `Length`/`Range` chunked API → `Method not found` | Add a compat method that reuses the host-side workspace file index cache and unpacks it to the legacy array shape |
| b | Direct page sidebar task list | The sidebar "Tasks" section queries the `window-controller` RPC channel, which is only registered by the desktop Host → queries time out, list stays empty | Register a minimal server-side `IWindowControllerService` that forwards to the in-process `IZCodeTaskService` (same tasks-index.sqlite source as desktop) |
| c | Token-mode server-info | The web entry fetches `/api/server-info` without credentials → always 401 when the server runs with `--token`, workspace announcement never reaches the page | Forward the URL `?token=` query to the fetch (same credential the WebSocket already uses) |
| d | Session restore | Web entry never enabled `restoreSession`, so no workspace tabs are restored at startup and scoped task queries have no data source | Enable the same `useTabPersistence` restore path the desktop app uses |
| e | Workspace purpose | `server-info` workspaces carry no purpose; the conversation backing workspace can't be distinguished from user projects | Add optional `workspacePurpose` to the workspace info schema (backward compatible) |
| f | Mobile background disconnects (direct page) | Mobile browsers freeze/kill the page's WebSocket within seconds of backgrounding; on return the socket is dead with no indication and RPC calls fail silently | Connection guard: non-clean `close` (≠1000/1001) shows a reconnect banner and reloads the page once visible; on return to foreground, a dead-while-hidden socket or a failed `/api/server-info` probe triggers the same recovery; reload rate-limited to 3/60s (server is the source of truth, nothing is lost) |

All changes are source-level, protocol-compatible additions — no desktop behavior
changes, no environment-specific values.

## Applying

```bash
# inside a checkout of zai-org/ZCode at v3.14.3
bash apply-selfhosted-web-patches.sh

# build the distribution
pnpm install
pnpm build:zcode --base-url https://your-dist-host/dist/
# artifact: dist/zcode/releases/<version>/zcode-<version>.tar.gz
```

Run the server with a token (the web UI accepts `?token=<token>` on first visit):

```bash
node bin/zcode.mjs --web --workspace <dir> --host 127.0.0.1 --port 3030 --token <token>
```

`--workspace` pointing at the app-managed conversation workspace
(`<dataBaseDir>/.zcode/workspace/default`) is announced as
`workspacePurpose: "conversation"` — the UI shows it as "not working in a
project" (draft mode). Create real projects from the UI as needed.

## Notes

- The official mobile remote-control page (`/remote/v4`) can be proxied and wired
  to a self-hosted server; that relay is deployment-specific and not part of this
  patch set.
- Known limitation: if the server is killed mid-conversation, the task row can
  stay `running` in tasks-index.sqlite (no orphan cleanup on startup yet).

## Patches

- `0001-self-hosted-web-parity.patch` — items a–e (single commit)
- `0002-web-connection-guard.patch` — item f (single commit)
- `0001-0002-selfhosted-web-patches.patch` — both combined (apply in one step)

Apply against upstream `v3.14.3` (commit `29628c9`); all three variants are
verified with `git apply --check`.
