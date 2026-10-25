# mtbrowser-hmos

> Lightweight bookmark-centric browser for **HarmonyOS NEXT** (ArkTS / ArkWeb), built for
> self-hosted services behind **mutual TLS** (LibreChat, admin panels, router consoles, …).
> Port of [mtbrowser](https://github.com/Sail64/mtbrowser) (Android).

## Features

- **Bookmark home** — native layout, add / edit / delete, empty-state guide
- **Multi-tab** — one persistent `Web` per tab (LRU cap of 4), tab overview to switch / close
- **Top bar** — home, address bar (auto-prefixes `https://`), reload, one-tap bookmark, tab count
- **Floating fullscreen button** — draggable with remembered position; fullscreen hides the app bar
- **mTLS client certificate** — per-site selection via the system certificate dialog; the app only
  stores the credential `keyUri`, never the key material
- **Controllable SSL errors** — self-signed / expired certs prompt the user; "proceed anyway" is
  session-only, never silent
- **Domain whitelist** — local-only config file; non-whitelisted hosts are blocked before navigation
  *and* re-checked after commit (`onLoadIntercept` + `onNavigationEntryCommitted`)
- **Dangerous scheme blocking** — `file:` / `javascript:` / `data:` / `blob:` / `content:` are
  never handed to the page
- **Downloads** — kernel download stack, filenames sanitized against path traversal
- **File upload** — `<input type="file">` supported
- **Session persistence** — cookies flushed to disk on page end / background; open tabs restored
  **to their site root** on cold start (deep links are deliberately not restored: unauthenticated
  deep links make apps like LibreChat wipe the session)
- **Dark mode** — `darkMode(Auto)` only; `forceDarkAccess` is never enabled (it turns some SPAs
  fully white)

## Usage

### 1. Add a site
Tap **＋ 添加** on the bookmark home. While browsing, tap ☆ in the top bar to bookmark the current
page. Long-press a bookmark to edit or delete it.

### 2. Tabs
Tap the tab icon to open the overview: tap a card to switch, ✕ to close, **＋ 新建标签** for a new one.

### 3. Client certificate (mTLS)
When a site requests a client certificate the system dialog appears. Install the certificate first
through **Settings → Certificate management → Install from storage → User credentials** — do *not*
open the `.p12` from a file manager, an Android compatibility layer may hijack the handler.

### 4. Whitelist
Copy `entry/src/main/resources/rawfile/domain_whitelist.txt.example` to `domain_whitelist.txt` and
list the hosts you want reachable. `*.example.com` matches the domain and its subdomains.

## Build

Requires DevEco Studio (or its `devecocli`) with **HarmonyOS SDK API 26**.

```bash
# 1. project config + debug signing material (kept out of git)
cp build-profile.example.json5 build-profile.json5
devecocli signature generate          # writes p12/cer/p7b under ~/.ohos/config/
#    then fill the four paths/passwords in build-profile.json5
#    (no device yet? delete the `signingConfigs` block and the `signingConfig` reference
#     inside `products` — the build then succeeds and emits entry-default-unsigned.hap)

# 2. local whitelist
cp entry/src/main/resources/rawfile/domain_whitelist.txt.example \
   entry/src/main/resources/rawfile/domain_whitelist.txt

# 3. build / install
devecocli build
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b cn.tobe.mtbrowser.hmos
```

## Checks (headless, no IDE needed)

```bash
node tools/check-arch.mjs     # dependency direction guard, exits 1 on violation
sh tools/domain-smoke.sh      # 115 pure-domain assertions, runs in plain Node
```

## Code structure

```
entry/src/main/ets/
├── domain/     pure logic, zero platform imports (@ohos.* / @kit.* forbidden)
├── data/       preferences-backed stores, repository implementations
├── platform/   ArkWeb / certificate / download adapters
├── ui/         ArkUI components; BrowserWeb is the only place ArkWeb events are wired
├── pages/      thin controller (Index)
└── app/        AppGraph — the single composition root
```

The boundary is enforced mechanically, not by convention: `domain/` must build in plain Node (that
is what the smoke test does), and `ui/`/`pages/` may not import `platform/` directly.

## Known gaps vs the Android version

- No third-party cookie isolation API on ArkWeb (cookies are shared per host, not per port)
- `openAuthorizeDialog` accepts no `keyTypes` / `principals` filter
- `onSslErrorEventReceive` does not carry the failing URL, so subresource cert errors are attributed
  to the main frame
- No status-bar tinting tied to page background
- No bookmark import/export between platforms

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (Chinese) for the platform traps that were hit
and the reasoning behind each decision.

## License

MIT — see [LICENSE](LICENSE).