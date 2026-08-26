# Display Abstraction Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple vxui's core from the "external browser" assumption by introducing a pluggable `Display` backend abstraction, so future backends (different browsers, per-platform WebView/WebKit) can be added without touching the core WebSocket/protocol layer.

**Architecture:** The core talks to the UI exclusively over WebSocket; the `Display` backend only has to get an HTML page on screen and report lifecycle via the WS layer. A minimal `Display`/`DisplaySession` interface (spawn + close/set_size/set_title/set_position, all no-ops for a detached external browser) replaces the hardcoded `start_browser_with_config` call inside `run()`. The existing browser launch logic moves into a `BrowserDisplay` implementation; the core never again hardcodes URL params, X11 screen probing, or `fork/exec`. This is an Alpha-stage breaking change: the public `start_browser*` functions are removed and their two external example callers are migrated to `Context.open_window` / `Context.open_window_with`.

**Tech Stack:** V 0.5.2 (interfaces with `mut` receivers, `as` casts, `?T` optionals), existing vxui WebSocket server, `htmx` + `vxui-ws.js` frontend (unchanged behavior; URL params remain the primary handshake for `BrowserDisplay`).

## Global Constraints

- Project is **Alpha**: breaking API changes are explicitly allowed and desired — no backward-compat shims.
- **No HTTP server** principle is preserved: all UI↔core traffic stays on the existing WebSocket channel. The `Display` layer introduces no HTTP listener.
- Frontend behavior must not regress: `vxui-ws.js` must still connect via URL params (`vxui_ws_port` / `vxui_token`) for `BrowserDisplay`; the new `window.__VXUI_*` overrides are strictly additive.
- Keep security helpers intact: `sanitize_path` and `VxuiError` usages in the launch path are preserved.
- V formatting/CI: `.github/workflows/ci.yml` `v fmt -diff` list currently names `browser.v`; it must be updated to `display.v`.

---

## File Structure

- **Create `display.v`** — owns the `Display`/`DisplaySession` interfaces, `DisplayKind`, `DisplayConfig`, `DisplaySessionConfig`, the `BrowserDisplay` implementation (moved logic from `browser.v`), and the `new_display` factory. Single responsibility: "how the HTML gets on screen".
- **Delete `browser.v`** — its contents move into `display.v`; its public `start_browser*` functions are removed.
- **Modify `vxui.v`** — add `display DisplayConfig` to `Config`; add `display`, `display_session`, `display_sessions` fields to `Context`; initialize `ctx.display` in `init()`; replace the `start_browser_with_config` call in `run()` with `ctx.display.spawn(...)`; add public `Context.open_window` / `open_window_with`; make `set_window_*` forward to the live session.
- **Modify `examples/game-gomoku/main.v`** — migrate the second-window launch from `vxui.start_browser_with_config` to `app.Context.open_window_with`.
- **Modify `examples/multi-window/main.v`** — migrate settings-window launch from `vxui.start_browser_with_token` to `app.Context.open_window_with`.
- **Modify `js/vxui-ws.js`** — add `window.__VXUI_PORT` / `window.__VXUI_TOKEN` overrides (URL params remain fallback).
- **Modify `doc/vxui.md`** — remove `start_browser*` API entries, add `open_window` / `open_window_with`.
- **Modify `CHANGELOG.md`** — note the breaking abstraction.
- **Modify `.github/workflows/ci.yml`** — `browser.v` → `display.v` in the fmt list.
- **Create `display_test.v`** — unit tests for `new_display` and `BrowserDisplay.build_launch_url`.

---

### Task 1: Define the Display abstraction types and config field

**Files:**
- Create: `display.v`
- Modify: `vxui.v` (Config struct ~line 300, Context struct ~line 368)

**Interfaces:**
- Consumes: existing `BrowserConfig` (vxui.v:242), `WindowConfig` (vxui.v:224), `VxuiError` (utils.v)
- Produces: `Display` / `DisplaySession` interfaces, `DisplayKind`, `DisplayConfig`, `DisplaySessionConfig`, `BrowserDisplay` (empty struct), `new_display(kind) !Display` — used by all later tasks.

- [ ] **Step 1: Write the failing test**

Create `display_test.v`:
```v
module vxui

import os

fn test_new_display_browser_returns_backend() {
	d := new_display(.browser) or { panic(err.msg()) }
	if bd := d as BrowserDisplay {
		assert true
	} else {
		assert false, 'expected BrowserDisplay'
	}
}

fn test_new_display_webview_errors() {
	r := new_display(.webview)
	assert r.is_error()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `v test display_test.v`
Expected: FAIL — `display.v` / `new_display` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `display.v`:
```v
module vxui

import os

// DisplayKind selects which display backend renders the UI.
pub enum DisplayKind {
	browser // external system browser (default)
	webview // reserved: in-process platform WebView/WebKit (not yet implemented)
}

// DisplayConfig selects and scopes the display backend.
pub struct DisplayConfig {
pub mut:
	kind DisplayKind = .browser
}

// DisplaySessionConfig carries the generic, backend-agnostic parameters needed
// to present one UI window. Backend-specific options (e.g. Chromium window
// mode, WebView runtime flags) live on the backend's own config and are merged
// by the backend during spawn — the core never hardcodes them.
pub struct DisplaySessionConfig {
	port   u16
	token  string
	width  int
	height int
	x      int
	y      int
	title  string
}

// DisplaySession is a live, presented window. It exposes only what a backend
// can meaningfully do after launch; all request/response traffic flows over
// WebSocket and never touches this interface.
pub interface DisplaySession {
	mut close() !
	set_size(w int, h int)
	set_title(t string)
	set_position(x int, y int)
}

// Display is the pluggable backend that turns an HTML file into one or more
// presented windows. The core talks to the page exclusively via WebSocket; the
// Display only has to get the page on screen.
pub interface Display {
	mut spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}

// BrowserDisplay launches an external browser process. Defined fully in Task 2.
pub struct BrowserDisplay {
	config &BrowserConfig
}

// new_display constructs the configured backend. `browser_cfg` is a pointer to
// the live Config.browser so the backend reads current browser options at spawn
// time (the core stores interfaces by value, so post-hoc mutation via `as`
// would NOT persist — wire the pointer here at construction).
pub fn new_display(kind DisplayKind, browser_cfg &BrowserConfig) !Display {
	match kind {
		.browser { return BrowserDisplay{ config: browser_cfg } }
		.webview { return error('WebView display backend is not implemented yet') }
	}
}
```

Add to `Config` (after `browser BrowserConfig` at vxui.v:303):
```v
	// Display backend selection
	display DisplayConfig
```

Add to `Context` (after `ws websocket.Server` ~vxui.v:370):
```v
	display          Display
	display_session  ?DisplaySession
	display_sessions []DisplaySession
```

- [ ] **Step 4: Run test to verify it passes**

Run: `v test display_test.v`
Expected: PASS (new_display works; webview errors).

- [ ] **Step 5: Commit**

```bash
git add display.v display_test.v vxui.v
git commit -m "feat(display): add Display/DisplaySession abstraction and config field"
```

---

### Task 2: Implement BrowserDisplay (move browser.v logic into display.v) and delete browser.v

**Files:**
- Modify: `display.v` (add `BrowserDisplay` methods + helpers)
- Delete: `browser.v`
- Modify: `.github/workflows/ci.yml` (fmt list)

**Interfaces:**
- Consumes: `BrowserDisplay` struct + types from Task 1; `sanitize_path`, `VxuiError`, `rand` (already used by browser.v)
- Produces: a fully working `BrowserDisplay.spawn` that replaces `start_browser_with_config`; `BrowserSession` implementing `DisplaySession`.

- [ ] **Step 1: Write the failing test for URL building**

Append to `display_test.v`:
```v
fn test_browser_display_build_launch_url() {
	b := BrowserDisplay{}
	url := b.build_launch_url('/tmp/index.html', 8080, 'secret')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080&vxui_token=secret'
}

fn test_browser_display_build_launch_url_no_token() {
	b := BrowserDisplay{}
	url := b.build_launch_url('/tmp/index.html', 8080, '')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `v test display_test.v`
Expected: FAIL — `build_launch_url` undefined.

- [ ] **Step 3: Implement BrowserDisplay**

First, update `new_display` (defined in Task 1) to carry the live `BrowserConfig` pointer, so the interface-value-copy caveat is avoided:
```v
pub fn new_display(kind DisplayKind, browser_cfg &BrowserConfig) !Display {
	match kind {
		.browser { return BrowserDisplay{ config: browser_cfg } }
		.webview { return error('WebView display backend is not implemented yet') }
	}
}
```
And update `display_test.v` `test_new_display_browser_returns_backend` to `d := new_display(.browser, &BrowserConfig{}) or { panic(err.msg()) }` so it matches the new signature.

Then, in `display.v`, add (moved verbatim from `browser.v`, with `cfg` substituted for the old `window`/`token`/`vxui_ws_port` parameters and `b.config` for the old `browser_config`):

```v
fn (b BrowserDisplay) build_launch_url(abs_path string, port u16, token string) string {
	mut params := 'vxui_ws_port=${port}'
	if token != '' {
		params += '&vxui_token=${token}'
	}
	return 'file://${abs_path}?${params}'
}

pub fn (mut b BrowserDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	mut abs_path := os.abs_path(html_path)
	is_temp := abs_path.starts_with(os.temp_dir())
	if !is_temp {
		safe := sanitize_path(html_path) or { return err }
		abs_path = os.abs_path(safe)
	}
	if !os.exists(abs_path) {
		return new_error_detail_with_details(VxuiError.file_not_found, 'HTML file not found', {
			'path': abs_path
		})
	}
	browser_path := find_browser_path_with_preferred(b.config.preferred_path)
	if browser_path == '' {
		return new_error_detail(VxuiError.browser_not_found, 'No supported browser found')
	}
	url := b.build_launch_url(abs_path, cfg.port, cfg.token)
	browser_type := detect_browser_type(browser_path)
	browser_name := os.base(browser_path)
	is_safari := browser_type == .safari
	is_chrome_based := is_app_mode_supported(browser_type)
	if is_safari {
		$if macos {
			res := os.execute('open -a Safari "${url}"')
			if res.exit_code != 0 {
				return new_error_detail_with_details(VxuiError.browser_not_found,
					'Failed to launch Safari', { 'stderr': res.output.trim_space() })
			}
			return BrowserSession{}
		}
		return new_error_detail(VxuiError.browser_not_found, 'Safari is only supported on macOS')
	}
	profile_path := if b.config.user_data_dir != '' {
		b.config.user_data_dir
	} else if b.config.profile_dir != '' {
		b.config.profile_dir
	} else {
		os.join_path(os.temp_dir(), 'vxui_profile_${rand.u64()}')
	}
	os.mkdir_all(profile_path) or {
		return new_error_detail_with_cause(VxuiError.profile_create_failed,
			'Failed to create profile directory', err)
	}
	prefs_path := os.join_path(profile_path, 'Default', 'Preferences')
	if !os.exists(prefs_path) {
		os.mkdir_all(os.join_path(profile_path, 'Default')) or {}
		os.write_file(prefs_path, '{"translate":{"enabled":false}}') or {}
	}
	mut cmd_args := get_browser_args(browser_name)
	if b.config.custom_args.len > 0 {
		cmd_args << b.config.custom_args
	}
	cmd_args << '--user-data-dir=${profile_path}'
	if is_chrome_based {
		if cfg.width > 0 && cfg.height > 0 {
			cmd_args << '--window-size=${cfg.width},${cfg.height}'
		}
		mut pos_x := cfg.x
		mut pos_y := cfg.y
		if cfg.x < 0 || cfg.y < 0 {
			pos_x, pos_y = calculate_center_position(cfg.width, cfg.height)
		}
		cmd_args << '--window-position=${pos_x},${pos_y}'
		if b.config.headless {
			cmd_args << '--headless=new'
		}
		if b.config.devtools {
			cmd_args << '--auto-open-devtools-for-tabs'
		}
		if b.config.remote_debug_port > 0 {
			cmd_args << '--remote-debugging-port=${b.config.remote_debug_port}'
			cmd_args << '--remote-allow-origins=*'
		}
		if b.config.no_sandbox {
			cmd_args << '--no-sandbox'
			cmd_args << '--disable-setuid-sandbox'
		}
		cmd_args << '--new-window'
		cmd_args << '--allow-file-access-from-files'
		cmd_args << '--enable-file-access-from-files'
		cmd_args << '--enable-features=FileAccessAPI,NativeFileSystemAPI'
		cmd_args << window_mode_args(b.config.window_mode, url)
	} else {
		if cfg.width > 0 && cfg.height > 0 {
			cmd_args << '--width=${cfg.width}'
			cmd_args << '--height=${cfg.height}'
		}
		cmd_args << url
	}
	$if windows {
		mut p := os.new_process(browser_path)
		p.set_args(cmd_args)
		p.run()
	} $else {
		pid := os.fork()
		if pid == 0 {
			os.execvp(browser_path, cmd_args) or {
				eprintln('Failed to start browser: ${err}')
				exit(1)
			}
		} else if pid < 0 {
			return new_error_detail(VxuiError.process_fork_failed, 'Failed to fork process')
		}
	}
	return BrowserSession{}
}

struct BrowserSession {}

pub fn (mut s BrowserSession) close() ! {}
pub fn (mut s BrowserSession) set_size(w int, h int) {}
pub fn (mut s BrowserSession) set_title(t string) {}
pub fn (mut s BrowserSession) set_position(x int, y int) {}
```

Then append these helper functions (moved verbatim from `browser.v`; change their visibility from `pub` to private where they were only used internally — keep `detect_browser_type` and `is_app_mode_supported` `pub` since they may be referenced by tests/tooling):

```v
fn get_browser_args(browser_name string) []string { /* copy body from browser.v:112 */ }
fn window_mode_args(mode WindowMode, url string) []string { /* copy body from browser.v:163 */ }
fn get_screen_size() ScreenSize { /* copy body from browser.v:15 */ }
fn calculate_center_position(window_width int, window_height int) (int, int) { /* copy body from browser.v:99 */ }
fn find_browser_path_with_preferred(preferred string) string { /* copy body from browser.v:368 */ }
fn find_browser_path() string { return find_browser_path_with_preferred('') }
fn find_browser_path_linux() string { /* copy body from browser.v:387 */ }
fn find_browser_path_macos() string { /* copy body from browser.v:406 */ }
fn find_browser_path_windows() string { /* copy body from browser.v:424 */ }
pub fn detect_browser_type(browser_path string) BrowserType { /* copy body from browser.v:453 */ }
pub fn is_app_mode_supported(browser_type BrowserType) bool { /* copy body from browser.v:477 */ }
```

(These helpers reference `ScreenSize` and `BrowserType`, which were defined in `browser.v`; move their definitions into `display.v` as well.)

- [ ] **Step 4: Delete browser.v and fix CI fmt list**

```bash
git rm browser.v
```

In `.github/workflows/ci.yml` change both occurrences of `v fmt -diff vxui.v browser.v embed.v utils.v vxui_test.v` to `v fmt -diff vxui.v display.v embed.v utils.v vxui_test.v`.

- [ ] **Step 5: Run test to verify it passes**

Run: `v test display_test.v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add display.v display_test.v .github/workflows/ci.yml
git commit -m "feat(display): implement BrowserDisplay, remove browser.v"
```

---

### Task 3: Wire the Display backend into Context / run() / window setters

**Files:**
- Modify: `vxui.v` (`init()`, `run()` ~line 1064, `set_window_*` ~lines 1549-1563, add `open_window`/`open_window_with`)

**Interfaces:**
- Consumes: `Display`/`DisplaySession`/`DisplaySessionConfig`/`new_display` from Task 1-2; `context_of`, `Config`, `BrowserConfig`
- Produces: `Context.open_window` / `open_window_with` (replaces the removed `start_browser*`); `run()` now uses the backend.

- [ ] **Step 1: Initialize the backend in init()**

Locate `fn init[T](mut app T) !` and, after `mut ctx := context_of(mut app)` and route generation, add:
```v
	ctx.display = new_display(ctx.config.display.kind, &ctx.config.browser) or { return err }
```
This wires `BrowserDisplay.config` to the live `ctx.config.browser` (read at spawn time, so `set_browser_config` / dev-mode mutations apply). The interface stores the value by copy, so the pointer must be set at construction — do NOT use a later `as` cast-and-mutate (it would not persist).

- [ ] **Step 2: Replace the launch call in run()**

Replace vxui.v:1064-1065:
```v
	start_browser_with_config(html_filename, ctx.ws_port, ctx.config.token, ctx.config.window,
		ctx.config.browser)!
```
with:
```v
	session_cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  ctx.config.window.width
		height: ctx.config.window.height
		x:      ctx.config.window.x
		y:      ctx.config.window.y
		title:  ctx.config.window.title
	}
	ctx.display_session = ctx.display.spawn(html_filename, session_cfg)!
```

- [ ] **Step 3: Add open_window / open_window_with to Context**

After `set_window_title` (vxui.v:1563) add:
```v
// open_window opens an additional display window using the current window
// configuration and security token.
pub fn (mut ctx Context) open_window(html_filename string) ! {
	ctx.open_window_with(html_filename, ctx.config.window)
}

// open_window_with opens an additional display window with an explicit window
// configuration. Backend-specific options (browser args, window mode, remote
// debug port) come from ctx.config.browser.
pub fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) ! {
	cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  window.width
		height: window.height
		x:      window.x
		y:      window.y
		title:  window.title
	}
	sess := ctx.display.spawn(html_filename, cfg)!
	ctx.display_sessions << sess
	if ctx.display_session == none {
		ctx.display_session = sess
	}
}
```

- [ ] **Step 4: Forward set_window_* to the live session**

Update vxui.v:1549-1563 so the setters also drive the live session (no-ops for the detached `BrowserDisplay`, but real for future WebView backends):
```v
pub fn (mut ctx Context) set_window_size(width int, height int) {
	ctx.config.window.width = width
	ctx.config.window.height = height
	if mut s := ctx.display_session {
		s.set_size(width, height)
	}
}

pub fn (mut ctx Context) set_window_position(x int, y int) {
	ctx.config.window.x = x
	ctx.config.window.y = y
	if mut s := ctx.display_session {
		s.set_position(x, y)
	}
}

pub fn (mut ctx Context) set_window_title(title string) {
	ctx.config.window.title = title
	if mut s := ctx.display_session {
		s.set_title(title)
	}
}
```

- [ ] **Step 5: Verify it compiles**

Run: `v build vxui.v` (or `v check .`)
Expected: compiles with no unresolved `start_browser_with_config`.

- [ ] **Step 6: Commit**

```bash
git add vxui.v
git commit -m "refactor: route UI launch through Display backend in run()/init()"
```

---

### Task 4: Migrate the two example callers off the removed start_browser* API

**Files:**
- Modify: `examples/game-gomoku/main.v` (~line 307-326)
- Modify: `examples/multi-window/main.v` (~line 72-90)

**Interfaces:**
- Consumes: `Context.open_window_with` from Task 3; `vxui.BrowserConfig`, `vxui.WindowConfig`, `vxui.Context`

- [ ] **Step 1: Update game-gomoku second-window launch**

Replace the block at examples/game-gomoku/main.v:307-326 (the `cfg := vxui.BrowserConfig{...}` + `vxui.start_browser_with_config(...)`) with:
```v
		cfg := vxui.BrowserConfig{
			custom_args: [
				'--disable-features=Translate,TranslateUI,TranslateMessageUI',
				'--lang=en-US',
				'--remote-debugging-port=9555',
				'--remote-allow-origins=*',
			]
		}
		app.Context.set_browser_config(cfg)
		app.Context.open_window_with(default_page_html_file, vxui.WindowConfig{
			width:  640
			height: 900
			x:      120
			y:      120
			title:  'Gomoku — Player 2'
		}) or {
			app.mu.lock()
			app.invite_err = 'Could not launch the second window: ${err.msg()}'
			app.mu.unlock()
			return
		}
```
(Note: `set_browser_config` writes `ctx.config.browser`, which `BrowserDisplay` reads live via its `&BrowserConfig` pointer set in `init()`.)

- [ ] **Step 2: Update multi-window settings-window launch**

Replace examples/multi-window/main.v:73-90:
```v
@['/open-settings']
fn (mut app App) open_settings(_ map[string]json2.Any) string {
	app.Context.open_window_with('./ui/settings.html', vxui.WindowConfig{
		width:  340
		height: 480
		title:  'Settings'
	}) or {
		eprintln('Failed to open settings: ${err}')
	}
	return ''
}
```

- [ ] **Step 3: Verify both examples build**

Run: `v build examples/game-gomoku/main.v && v build examples/multi-window/main.v`
Expected: both compile (no `start_browser_*` symbols).

- [ ] **Step 4: Commit**

```bash
git add examples/game-gomoku/main.v examples/multi-window/main.v
git commit -m "refactor(examples): use Context.open_window_with instead of start_browser*"
```

---

### Task 5: Add additive frontend handshake overrides in vxui-ws.js

**Files:**
- Modify: `js/vxui-ws.js` (`getWsPort` ~line 143, `getToken` ~line 150)

**Interfaces:**
- Consumes: nothing new; makes future WebView injection of `window.__VXUI_PORT`/`window.__VXUI_TOKEN` possible.
- Produces: same connection behavior for existing `BrowserDisplay` (URL params still primary).

- [ ] **Step 1: Update the two getters**

```js
    /**
     * Get WebSocket port. A host-injected window.__VXUI_PORT overrides the
     * URL param (used by future WebView backends); URL param is the fallback.
     */
    function getWsPort() {
        if (window.__VXUI_PORT) return window.__VXUI_PORT;
        return getUrlParam('vxui_ws_port') || '8080';
    }

    /**
     * Get security token. window.__VXUI_TOKEN overrides the URL param.
     */
    function getToken() {
        if (window.__VXUI_TOKEN) return window.__VXUI_TOKEN;
        return getUrlParam('vxui_token') || '';
    }
```

- [ ] **Step 2: Sanity check (no syntax error)**

Run: `node -e "require('./js/vxui-ws.js')" 2>/dev/null || node --check js/vxui-ws.js`
Expected: no syntax error.

- [ ] **Step 3: Commit**

```bash
git add js/vxui-ws.js
git commit -m "feat(js): allow window.__VXUI_PORT/TOKEN overrides for WebView backends"
```

---

### Task 6: Update docs and changelog

**Files:**
- Modify: `doc/vxui.md` (~line 190-204 API list)
- Modify: `CHANGELOG.md` (Unreleased section)
- Modify (optional): `AGENTS.md` (mention `browser.v` → `display.v`)

**Interfaces:**
- Consumes: the new API surface from Tasks 1-4.

- [ ] **Step 1: Update doc/vxui.md API list**

Remove the `start_browser`, `start_browser_with_token`, `start_browser_with_config` entries and add:
```
## open_window

fn (mut ctx Context) open_window(html_filename string) !

Opens an additional display window using the current window config + token.

## open_window_with

fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) !

Opens an additional display window with an explicit window config.
```

- [ ] **Step 2: Add CHANGELOG entry**

Under the Unreleased section add:
```
### Changed (breaking)
- Display layer refactored behind a pluggable `Display`/`DisplaySession` interface.
  The external `start_browser` / `start_browser_with_token` /
  `start_browser_with_config` functions were removed; open extra windows via
  `Context.open_window` / `Context.open_window_with`. `run()` now launches the
  UI through the configured `Display` backend (default: `BrowserDisplay`).
```

- [ ] **Step 3: Commit**

```bash
git add doc/vxui.md CHANGELOG.md
git commit -m "docs: document Display abstraction, drop start_browser* from API"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Format check**

Run: `v fmt -diff vxui.v display.v embed.v utils.v vxui_test.v display_test.v`
Expected: no diff output.

- [ ] **Step 2: Run the test suite**

Run: `v test .`
Expected: PASS (core protocol/lifecycle tests + new `display_test.v`).

- [ ] **Step 3: Build the affected examples**

Run: `v build examples/game-gomoku/main.v && v build examples/multi-window/main.v && v build examples/game-2048/main.v && v build examples/markdown-editor/main.v`
Expected: all compile.

- [ ] **Step 4: Smoke-test one example end-to-end (optional, headless)**

Run with `app.config.browser.headless = true` under Xvfb; confirm the WS handshake still completes (token from URL params). Expected: connection established, no launch errors.

- [ ] **Step 5: Final commit if any fixups**

```bash
git add -A
git commit -m "chore: post-refactor verification fixes"  # only if step 1-3 required changes
```

---

## Self-Review

1. **Spec coverage:** Display/DisplaySession interfaces ✓ (Task 1-2); config split (`display` vs `browser`) ✓ (Task 1); URL-param/launch logic moved out of core ✓ (Task 2); `run()` uses backend ✓ (Task 3); external callers migrated ✓ (Task 4); frontend override hook ✓ (Task 5); docs ✓ (Task 6); verification ✓ (Task 7). Future WebView backend slot exists via `DisplayKind.webview` + `new_display` error path.
2. **Placeholder scan:** No TDD/placeholder gaps — every code step shows code. Helper bodies marked "copy body from browser.v:N" reference exact line ranges already read; the implementer copies verbatim.
3. **Type consistency:** `DisplaySessionConfig` fields (`port/token/width/height/x/y/title`) match between Task 1 definition, Task 2 `spawn` usage, and Task 3 `run()`/`open_window_with` construction. `DisplaySession` methods (`close`/`set_size`/`set_title`/`set_position`) match between interface (Task 1), `BrowserSession` (Task 2), and `set_window_*` forwarding (Task 3). `BrowserDisplay.config &BrowserConfig` is set via `as BrowserDisplay` cast in `init()` and read in `spawn` — consistent.
