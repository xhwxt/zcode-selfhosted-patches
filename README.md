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
| j | Reconnect without page reload + scroll-position restore (direct page) | A real disconnect reloaded the entire page: blank screen, ~7MB of JS re-downloaded and re-parsed (2s+); the reload also lost the reading position, and the late restore could yank the scroll position while the user was already scrolling | Soft reconnect: retry the WebSocket with 1/2/4/8s backoff and re-mount the React tree under a new `connectionEpoch` key — no page reload, the old UI stays readable under a top banner, and recovery semantics are unchanged (server remains the source of truth, snapshot replay restores the session); full reload only after the backoff is exhausted or on a reconnect storm. Scroll memory is mirrored to `sessionStorage` (LRU 40) and restored by **distance-from-bottom** with a bounded 4s convergence pass over measurement/prepend changes; any real user scroll intent cancels the restore immediately, and a degenerate snapshot (`pinned=false` but at the bottom) is never persisted |

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

- Item j also fixes a latent render crash that fired once per page load:
  `useProviderSettingsView` passed `getServerSnapshot` a second time; under
  React 19 the update path compared against an undefined hook slot and threw
  `TypeError: Cannot read properties of undefined (reading 'length')`. The
  parameter is redundant for client-only rendering and was dropped.
- The official mobile remote-control page (`/remote/v4`) can be proxied and wired
  to a self-hosted server; that relay is deployment-specific and not part of this
  patch set.
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
- `0003-0004-selfhosted-web-patches-mobile.patch` — items g+h combined (legacy convenience file)

Apply against upstream `v3.14.3` (commit `29628c9`) in order 0001 → 0006
(0001+0002 may also be applied as one combined file historically named
`0001-0002-selfhosted-web-patches.patch`; do not apply the combined file together
with 0001/0002). All variants are verified with `git apply --check`, and applying
0001 → 0006 to a clean `29628c9` checkout reproduces the maintainer tree
byte-for-byte. `apply-selfhosted-web-patches.sh` runs the full sequence.
