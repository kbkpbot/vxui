# Display Config-Carrier Generalization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the `Display` construction/config wiring so a second backend (e.g. WebKit/WebView) is a pure add-on — no changes to `init()`, `run()`, `open_window*`, `set_*_config`, or dev-mode. Today `new_display(kind, &BrowserConfig)` and `Config.browser` bake the browser in (see review of the prior refactor). After this plan, selecting a backend only requires implementing one struct's `spawn`.

**Architecture:** Keep the `Display`/`DisplaySession` interfaces untouched. Change the config *carrier* from a hard `&BrowserConfig` to `&Config` (the whole config), and let `new_display` extract the per-kind sub-config inside its `match`. Add a symmetric `WebViewConfig` + a reserved `WebViewDisplay` stub (spawn returns a clear "not implemented" error) so the wiring is provably backend-agnostic. Drive `DisplaySession.close()` on app shutdown so in-process backends don't leak. All browser behavior is unchanged.

**Tech Stack:** V 0.5.2. Existing `Display`/`DisplaySession` interfaces, `BrowserDisplay`, `Config`, `Context`. No HTTP server; WebSocket-only (unchanged).

## Global Constraints

- Alpha: breaking changes allowed; no compat shims. `new_display` signature WILL change.
- No HTTP server: Display layer adds none.
- V 0.5.2: storing `&WebViewConfig`/`&BrowserConfig` references requires `@[heap]` on those structs (already on `BrowserConfig`; add to `WebViewConfig`). Interface mut-method calls need a mutable receiver.
- Browser behavior must be byte-for-byte equivalent: same launch args, same `fork`/`execvp`/`new_process`, same URL params. Only the *construction wiring* changes.

---

## File Structure

- **Modify `display.v`** — `new_display` takes `&Config`; add `WebViewConfig` (pub, empty placeholder, `@[heap]`); add `WebViewDisplay` stub (`config &WebViewConfig`, `spawn` returns informative error); `.webview` branch constructs it.
- **Modify `vxui.v`** — `Config` gets `webview WebViewConfig`; `init()` calls `new_display(kind, &ctx.config)`; dev-mode `browser.devtools` guarded by `kind == .browser`; add `set_webview_config`; add `close_displays()` and call it in the run-loop shutdown path (after `before_shutdown`).
- **Modify `display_test.v`** — update `new_display` calls to the new signature; add a `.webview` constructs-a-stub test.
- **Modify `CHANGELOG.md`** — note the generalization.

---

### Task 1: Generalize new_display + add WebViewConfig/WebViewDisplay stub

**Files:**
- Modify: `display.v`
- Modify: `display_test.v`

**Interfaces:**
- Consumes: `Display`/`DisplaySession` interfaces, `BrowserDisplay`, `DisplayKind`, `Config` (vxui.v), `BrowserConfig` (vxui.v, `@[heap]`), `VxuiError` (utils.v)
- Produces: `new_display(kind, &Config) !Display`; `WebViewConfig`; `WebViewDisplay` stub — consumed by Task 2 wiring.

- [ ] **Step 1: Update the test calls (TDD — make them fail first)**

In `display_test.v`, change the existing `new_display` calls:
```v
fn test_new_display_browser_returns_backend() {
	d := new_display(.browser, &Config{ browser: BrowserConfig{} }) or { panic(err.msg()) }
	if bd := d as BrowserDisplay {
		assert true
	} else {
		assert false, 'expected BrowserDisplay'
	}
}

fn test_new_display_webview_errors() {
	r := new_display(.webview, &Config{})
	assert r.is_error()
}
```
(Run `v test display_test.v` → FAIL: old one-arg signature.)

- [ ] **Step 2: Change new_display to take &Config and extract per-kind sub-config**

In `display.v`, replace:
```v
pub fn new_display(kind DisplayKind, browser_cfg &BrowserConfig) !Display {
	match kind {
		.browser {
			return BrowserDisplay{
				config: browser_cfg
			}
		}
		.webview {
			return error('WebView display backend is not implemented yet')
		}
	}
}
```
with:
```v
// new_display constructs the configured backend. It receives the whole app
// Config so each backend extracts its OWN sub-config — this keeps the
// construction wiring backend-agnostic (no hardcoded BrowserConfig).
pub fn new_display(kind DisplayKind, app_cfg &Config) !Display {
	match kind {
		.browser {
			return BrowserDisplay{ config: &app_cfg.browser }
		}
		.webview {
			return WebViewDisplay{ config: &app_cfg.webview }
		}
	}
}
```

- [ ] **Step 3: Add WebViewConfig + WebViewDisplay stub**

In `display.v`, add (near `BrowserDisplay`):
```v
// WebViewConfig holds in-process WebView/WebKit backend options. Empty today;
// filled when a real WebView backend lands. Must be @[heap] so a reference can
// be taken (same as BrowserConfig).
@[heap]
pub struct WebViewConfig {}

// WebViewDisplay is a reserved in-process WebView/WebKit backend. Its spawn is
// not yet implemented; it exists to prove the wiring is backend-agnostic — a
// real backend only needs to implement spawn() (and fill WebViewConfig).
pub struct WebViewDisplay {
	config &WebViewConfig
}

pub fn (mut b WebViewDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return error('WebView display backend is not implemented yet')
}

struct WebViewSession {}

pub fn (mut s WebViewSession) close() ! {}
pub fn (mut s WebViewSession) set_size(w int, h int) {}
pub fn (mut s WebViewSession) set_title(t string) {}
pub fn (mut s WebViewSession) set_position(x int, y int) {}
```
(Note: `WebViewSession` is currently unused by spawn's error path — that is fine; it satisfies the `DisplaySession` interface for when spawn is implemented. If V complains about an unused struct, it will not, since it implements the interface; if it does, leave it — it is the future return type.)

- [ ] **Step 4: Run tests to pass**

`v test display_test.v` → PASS (browser builds, webview constructs without browser coupling). `v fmt -diff display.v display_test.v` clean.

- [ ] **Step 5: Commit**

```bash
git add display.v display_test.v
git commit -m "refactor(display): generalize new_display to &Config; add reserved WebViewConfig/WebViewDisplay"
```

---

### Task 2: Wire config carrier + close() into core

**Files:**
- Modify: `vxui.v` (`Config` field, `init()`, dev-mode guard, `set_webview_config`, `close_displays`, run-loop shutdown)

**Interfaces:**
- Consumes: `new_display(kind, &Config)` from Task 1; `Config`, `Context`, `WebViewConfig`, `DisplaySession` from display.v
- Produces: `set_webview_config`; `close_displays` — used at shutdown; no other callers needed.

- [ ] **Step 1: Add Config.webview field**

In `Config` (after `browser BrowserConfig`, ~line 303), add:
```v
	// WebView/WebKit backend config (used when display.kind == .webview)
	webview WebViewConfig
```

- [ ] **Step 2: Update init()**

Change `vxui.v:433` from:
```v
	ctx.display = new_display(ctx.config.display.kind, &ctx.config.browser) or { return err }
```
to:
```v
	ctx.display = new_display(ctx.config.display.kind, &ctx.config) or { return err }
```

- [ ] **Step 3: Guard dev-mode browser mutation**

Change `vxui.v:1069` from:
```v
		ctx.config.browser.devtools = ctx.config.dev.auto_devtools
```
to:
```v
		if ctx.config.display.kind == .browser {
			ctx.config.browser.devtools = ctx.config.dev.auto_devtools
		}
```

- [ ] **Step 4: Add set_webview_config (symmetric with set_browser_config)**

After `set_browser_config` (vxui.v:1622), add:
```v
// set_webview_config configures WebView/WebKit backend options (used when
// display.kind == .webview).
pub fn (mut ctx Context) set_webview_config(config WebViewConfig) {
	ctx.config.webview = config
}
```

- [ ] **Step 5: Add close_displays and call it at shutdown**

Add a method near `set_webview_config`:
```v
// close_displays tears down all live display sessions. No-op for the detached
// external-browser backend; REQUIRED for in-process backends (WebView) so
// native windows/handles are released on shutdown.
pub fn (mut ctx Context) close_displays() {
	for mut s in ctx.display_sessions {
		s.close() or {}
	}
	if mut s := ctx.display_session {
		s.close() or {}
	}
	ctx.display_sessions = []
}
```
In `run()`, after the `before_shutdown` trigger (vxui.v:1195-1196) and before `ctx.ws.free()`, add:
```v
	ctx.close_displays()
```

- [ ] **Step 6: Verify**

`v build vxui.v` compiles. `v test display_test.v` still PASS. `v fmt -diff vxui.v` clean on edited regions (ignore pre-existing unrelated drift).

- [ ] **Step 7: Commit**

```bash
git add vxui.v
git commit -m "refactor: route display construction through &Config; drive close() on shutdown"
```

---

### Task 3: Docs + verification

**Files:**
- Modify: `CHANGELOG.md`
- Verify: fmt, `v test .` (per-file fallback if V3 parallel hangs), example builds.

- [ ] **Step 1: CHANGELOG**

Under the Unreleased "### Changed (breaking)" note added earlier, append a line:
```
- Display construction generalized: `new_display` now takes `&Config` and each
  backend extracts its own sub-config (`Config.browser` / `Config.webview`).
  Added `WebViewConfig` + a reserved `WebViewDisplay` stub, and
  `Context.set_webview_config`; `DisplaySession.close()` is now driven on
  shutdown. Adding a WebView/WebKit backend is now a pure add-on (implement
  `WebViewDisplay.spawn`).
```

- [ ] **Step 2: Format + test matrix**

`v fmt -diff vxui.v display.v display_test.v` (apply if branch-introduced drift). Run per-file tests (display_test.v, vxui_test.v, and the example `*_test.v` files) — all expected PASS. Build examples: `game-2048 game-gomoku game-minesweeper markdown-editor multi-window todo-app enchart element-plus packed` (each `v examples/$ex/main.v -o /tmp/ve_$ex`; binary expected). Report results.

- [ ] **Step 3: Commit (only if fmt fixes applied)**

```bash
git add vxui.v display.v display_test.v CHANGELOG.md
git commit -m "chore: post-generalization fmt + docs"  # only if step 2 needed changes
```
If no fmt changes, skip commit and report "no commit needed".

---

## Self-Review

1. **Spec coverage:** `new_display(&Config)` ✓ (Task 1); `Config.webview` + `WebViewConfig` + `WebViewDisplay` stub ✓ (Task 1); `init` uses `&ctx.config` ✓ (Task 2); dev-mode guarded ✓ (Task 2); `set_webview_config` ✓ (Task 2); `close_displays` + shutdown call ✓ (Task 2); CHANGELOG ✓ (Task 3). Browser behavior unchanged (spawn body untouched). A real WebView backend now only implements `WebViewDisplay.spawn` + fills `WebViewConfig` — no wiring edits.
2. **Placeholder scan:** No TBDs. `WebViewDisplay.spawn` returns an explicit error (reserved). `WebViewSession` is the future return type.
3. **Type consistency:** `new_display(kind, &Config)` matches Task 1 test calls and Task 2 `init` call. `WebViewConfig` (`@[heap]`, value field in `Config`) matches `WebViewDisplay.config &WebViewConfig`. `close_displays` iterates `display_sessions`/`display_session` of type `[]DisplaySession`/`?DisplaySession` — consistent with Task 2 of the prior refactor.
