<h1 align="center">Z÷</h1>

<div align="center"><pre>
                      /´¯/)
                    ,/¯../
                   /..../
             /´¯/'...'/´¯¯`·¸
          /'/.../..../......./¨¯\
        ('(...´...´.... ¯~/'...')
         \.................'..../
          ''...\.......... _.·´
            \..............(
             \.............\
</pre></div>

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
| f | Mobile background disconnects (direct page) | Mobile browsers freeze/kill the page's WebSocket within seconds of backgrounding; on return the socket is dead with no indication and RPC calls fail silently | Connection guard: a real `close` event marks the socket dead; a dead socket on return to foreground triggers recovery (see item j for the in-page reconnect that replaced the original full-page reload) |
| g | Mobile drawer layout (direct page) | Below 768px the sidebar and right side pane are in-flow split columns; opening either squeezes the conversation area | Drawer viewport: sidebar and side pane become sliding overlays (min(85vw,480px), 200ms transition) over a click-to-dismiss backdrop; sidebar drag handle not rendered; drawers are mutually exclusive; the top-left sidebar toggle (web branch of `DesktopTopOverlay`) sits at z-40 above the drawers so it always works |
| h | Directory browser create folder | The server-side directory browser could only pick existing directories — no way to create a project folder on a phone | `IFileService.createDirectory` (server-side single-segment mkdir, `recursive: false`, path separators rejected in the name; final path is joined server-side); inline "New folder" form in `DirectoryBrowser` refreshes the listing on success; i18n zh-CN/en-US |
| i | Mobile header offset & touch affordances (direct page) | (1) The header applied a desktop window-controls left padding (152px) whenever the sidebar was collapsed — on the drawer viewport the sidebar is collapsed by default, so the conversation title and buttons were pushed off-screen/clipped; (2) message action bars (time/copy) were hover-only, i.e. permanently invisible on touch devices; (3) a false-positive guard marked the socket dead on every background/foreground cycle, forcing a reload on each quick tab switch; (4) `AskUserQuestion` answers rendered as "未提供回答" because the CLI serializes them as text while the parser only accepted JSON | Gate the window-controls padding on the desktop platform and reserve 80px on the web drawer viewport for the floating overlay buttons (mobile title cap 46vw); make action bars always visible under `@media (hover: none)`; only a real `close` event marks the socket dead; parse the CLI's `"Q"="A"` text form in addition to JSON |
| j | Reconnect without page reload + scroll-position restore (direct page) | A real disconnect reloaded the entire page: blank screen, ~7MB of JS re-downloaded and re-parsed (2s+); the reload also lost the reading position, and the late restore could yank the scroll position while the user was already scrolling | Soft reconnect with short backoff — no page reload, the old UI stays readable under a top banner, and recovery semantics are unchanged (server remains the source of truth). Originally re-mounted the React tree under a `connectionEpoch` key; item k later replaced that with a hot transport swap (no re-render at all). Scroll memory is mirrored to `sessionStorage` (LRU 40) and restored by **distance-from-bottom** with a bounded 4s convergence pass; any real user scroll intent cancels the restore immediately |

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

## Optional add-on: official mobile remote-control page

The relay that lets the **official** mobile remote-control page run against a
self-hosted server is published under [`relay/`](relay/) with its own README
(endpoints, environment variables, systemd/nginx wiring, optional offline page
mirror, version pinning). It is deployment tooling, not a source patch — the patch
set above is what makes the server itself usable; the relay only adds the vendor
page on top.

## Notes

- Item j also fixes a latent render crash that fired once per page load:
  `useProviderSettingsView` passed `getServerSnapshot` a second time; under
  React 19 the update path compared against an undefined hook slot and threw
  `TypeError: Cannot read properties of undefined (reading 'length')`. The
  parameter is redundant for client-only rendering and was dropped.
- The official mobile remote-control page (`/remote/v4`) needs the relay in
  [`relay/`](relay/) (plus TLS/reverse-proxy wiring); without it only the direct
  page (built-in web UI) is reachable.
- Known limitation: if the server is killed mid-conversation, the task row can
  stay `running` in tasks-index.sqlite (no orphan cleanup on startup yet).

## Self-hosting checklist (beyond the patch set)

These are deployment steps, not source patches — they are listed here so a
self-hosted install is complete:

- **Plugin packages.** The plugin bundles that ship in the official release
  (`skill-creator-plugin`, `zcode-guide-plugin`, `documents-plugin`,
  `spreadsheets-plugin`, `pdf-plugin`, `presentations-plugin`,
  `restore-legacy-sessions-plugin`, `browser-use-plugin`, …, plus
  `bundled-skills`) are **not part of the source tree** and are not produced by
  `pnpm build:zcode`. Make sure `<install>/packages/` contains them (copy from an
  official release artifact / AppImage); otherwise the plugin store and the
  skill/guide tooling are missing.
- **Keep plugin copies and the agent bundle from the same release.** Official
  plugin definitions declare `requiredSeedPaths` (for example `zcode-guide`
  requires `commands/workflow.md` and `skills/dynamic-workflows/*`). At startup
  the agent checks those paths against the plugin copy on disk; if any are
  missing it logs `ZCODE_PLUGIN_SEED_INCOMPLETE` and **skips seeding that
  plugin** (the guide skill silently stays absent). Source and plugin copies must
  therefore come from a matching release: either use plugin directories that
  contain the paths your `installed agent/zcode.cjs` requires, or install the
  agent bundle that matches the plugin copies you have.
- **Agent runtime bundle.** `<install>/agent/zcode.cjs` is the prebuilt agent
  runtime. Rebuilding it from source replaces whatever the installer put there,
  so re-check the point above after every agent-bundle update.

## Patches

- `0001-self-hosted-web-parity.patch` — items a–e (single commit)
- `0002-web-connection-guard.patch` — item f (single commit)
- `0003-feat-ui-mobile-drawer-layout-for-sidebar-and-side-pa.patch` — item g
- `0004-fix-ui-mobile-drawer-polish-directory-browser-create.patch` — item h
- `0005-fix-ui-web-round2-mobile-fixes.patch` — item i
- `0006-fix-ui-web-mobile-header-window-controls-padding-per.patch` — item j
- `0007-fix-rpc-client-server-websocket-keepalive-liveness.patch` — item k
- `0003-0004-selfhosted-web-patches-mobile.patch` — items g+h combined (legacy convenience file)

Apply against upstream `v3.14.3` (commit `29628c9`) in order 0001 → 0007
(0001+0002 may also be applied as one combined file historically named
`0001-0002-selfhosted-web-patches.patch`; do not apply the combined file together
with 0001/0002). All variants are verified with `git apply --check`, and applying
0001 → 0007 to a clean `29628c9` checkout reproduces the maintainer tree
byte-for-byte. `apply-selfhosted-web-patches.sh` runs the full sequence.

### Item k — WebSocket keepalive liveness (half-open detection)

The direct web page previously had zero liveness probes on its browser ↔ server
WebSocket: `SocketProtocol` silently dropped `KeepAlive` frames, neither end sent
heartbeats, and the foreground guard probed with an HTTP fetch — which opens a
*different* connection and cannot detect a half-open one. A dead-but-open socket
looked normal while every new RPC failed silently.

- `packages/rpc` — `SocketProtocol` now answers a `KeepAlive` probe (`ack=0`)
  with exactly one echo (`ack=1`); new `sendKeepAlive()` / `onKeepAlive`.
  Queue/MessagePort transports moved to `port-protocol.ts` (line-limit split).
- `packages/client` — `connectViaWebSocket` attaches a heartbeat monitor by
  default (15 s probe / 30 s no-frame deadline). On deadline it closes the
  socket so the existing guard + soft-reconnect take over; `onHeartbeat` exposes
  a same-socket liveness handle to the host page.
- `packages/web` — the visibility guard's foreground check now uses that
  same-socket handle (fresh timestamp → healthy; stale → one probe + short wait
  → dead ⇒ soft reconnect) instead of an HTTP fetch.
- `packages/server` & `packages/zcode-server-cli` — `/ws` connections get an
  RFC 6455 ping loop (30 s interval, terminate after 2 missed pongs), freeing
  server-side half-open sockets and triggering the browser `close` path.

Spec: `packages/rpc/specs/socket-keepalive.md`; unit tests:
`packages/rpc/test/socket-keepalive.test.ts`.

### Item k (evolved) — hot transport swap, in-place recovery

Item k grew well past its original "heartbeat" scope through real-device
iteration. Current recovery architecture (all inside patch 0007):

1. **Hot transport swap** — on reconnect, the new WebSocket is swapped into
   the *same* `ChannelClient` (`resetTransport`): pending Promise requests are
   fail-closed, buffered frames (including the server's `Initialize`) are
   replayed, **active event subscriptions are re-sent**, and the handshake
   cache is invalidated by epoch. The React tree never re-mounts and
   `IServiceAccessor` object identity never changes — the UI shows zero
   visual change across a reconnect.
2. **Bounded silent retry** — every subscribe failure runs a backoff
   (250ms → 8s rhythm, aligned to the 8s handshake-RPC timeout, ~75s budget)
   before any error surface. Transient races (handshake/session swap/network
   jitter) are invisible to the user.
3. **Server-side connection hygiene** — RFC 6455 ping loop with a relaxed
   pong tolerance (4 misses ≈ 2.5 min): mobile Chrome stops answering pings
   for backgrounded pages (power saving) while the connection is still alive.
4. **Service Worker shell cache** (v7) — navigation and assets replay from
   local cache on page discard (instant recovery), background revalidation
   keeps deployments reaching clients; injected scripts (`/zusage/boot.js`)
   are network-first so they always update.

Known behavioral notes:
- `document.wasDiscarded` reloads (Android Chrome memory management) still
  produce a page load — replayed from local cache in ~1s; not preventable
  from web code.
- The `/web-remote` official page is closed-source (token flow has no native
  recovery coordinator); its recovery relies on the relay's injected shim
  (banner + reload only on unrecoverable error screens).

E2E scripts: [`e2e/`](e2e/) (half-open blackhole,
in-place recovery, reload telemetry).

### Release discipline (for maintainers)

- **Patch application is atomic.** `apply-selfhosted-web-patches.sh` runs a
  cumulative dry-run on a temp index before touching the worktree; any failure
  leaves the worktree clean. Baseline mismatch is a hard error (`STRICT=0`
  overrides at your own risk). Rollback is `git checkout -- .` or
  `git apply -R`.
- **Every patch-set update must re-verify the chain.** Apply 0001→000N to a
  clean `29628c9` worktree; the resulting tree hash must equal the maintainer
  HEAD tree hash. This is checked on every patch-repo push.
- **Known verification gap (accepted for now):** unit tests cover the protocol
  layer (keepalive echo, event re-send); end-to-end recovery was validated
  against real devices via the E2E scripts above, but there is no automated
  clean-baseline build + offline-recovery CI. Contributions in that direction
  are the highest-value next step.

