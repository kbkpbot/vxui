# vxui Improvements Implementation Plan (doc/vxui-improvements.md P0–P2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all actionable issues from the field report in `doc/vxui-improvements.md`: Windows launch failure, kiosk/app-mode misbehavior, heartbeat self-kill, run_js handler deadlock + callback leak, opaque auth/token logs, stale-tab slot blocking, non-UTF-8 write opacity, `no_app_mode` naming, and comptime dispatch diagnostics.

**Architecture:** vxui is a V module (`vxui.v`, `browser.v`, `utils.v`) plus a browser-side script (`js/vxui-ws.js`). All changes stay within this layout. Server-side message gating lives in `startup_ws_server()` callbacks; JS execution bookkeeping lives on `Context.js_callbacks`.

**Tech Stack:** V 0.5.2 (compiler at `/media/HD/github/kbkpbot/v`, verified behaviors below were tested against it), `net.websocket`, `x.json2`, vanilla-JS frontend.

## Global Constraints

- Toolchain is V 0.5.2 (9142d68). Comptime facts verified by experiment:
  - `$for` bodies reject `continue` ("continue is not allowed within a compile-time loop").
  - Runtime `if` guards do NOT gate instantiation of `app.$method(message)` — every string-returning method gets a call site.
  - `$if method.attrs.len > 0` is rejected ("only support .indirections/.return_type compare"); nested `$for attr in method.attributes` parses but does NOT gate instantiation.
  - Consequence for P2-10: the doc's suggested fix cannot compile; we ship a partial fix (validation + honest docs) instead.
- `doc/vxui-improvements.md` must NEVER be committed. Task 1 adds it to `.gitignore`; verify `git status` before every commit.
- Commit style matches repo history: lowercase conventional prefixes (`fix:`, `feat:`, `docs:`).
- Backward compatibility: legacy `BrowserConfig.no_app_mode = true` keeps working (forces `.normal`); default `require_auth` stays on; the only intentional behavior changes are documented ones (per-run temp browser profile, default app window instead of kiosk).
- After each task: `v test .` from the repo root must pass (run from workdir `/media/HD/mars/.vmodules/vxui`).

---

### Task 1: Keep the improvements report out of git

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add ignore entry**

Append to `.gitignore` under the `# Generated` section:

```
# Field improvement report (local only)
doc/vxui-improvements.md
```

- [ ] **Step 2: Verify**

Run: `git status --short && git check-ignore doc/vxui-improvements.md`
Expected: the file no longer appears as untracked; check-ignore prints the matching rule.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: keep local improvement report out of version control"
```

---

### Task 2: P0-3 — application heartbeat must not kill its own session

The client heartbeat `{cmd:"ping"}` carries no token; the server's token gate closes such connections with 1008 exactly 30s in. Fix both ends (server tolerates old cached JS).

**Files:**
- Modify: `vxui.v` (in `startup_ws_server`, between the auth block ending at ~L572 and the token gate at ~L576)
- Modify: `js/vxui-ws.js` (~L537)
- Test: `vxui_test.v`

**Interfaces:**
- Consumes: existing `message_token_valid()`, `handle_pong()`.
- Produces: server answers `{"cmd":"ping"}` with `{"cmd":"pong","client_id":...,"timestamp":...}` before the token gate; `last_ping` updated only when the ping's token is valid.

- [ ] **Step 1: Write the failing test**

Append to `vxui_test.v` after `test_websocket_integration_auth_rpc_and_reject`:

```v
// read_one_text reads text frames until one whose payload satisfies `want`,
// skipping protocol-level control frames. Fails after ~2s.
fn read_text_until(mut cl websocket.Client, want fn (string) bool) !string {
	for _ in 0 .. 40 {
		msg := cl.read_next_message()!
		if msg.opcode == .text_frame {
			s := msg.payload.bytestr()
			if want(s) {
				return s
			}
		}
	}
	return error('expected text frame not received')
}

fn test_heartbeat_ping_answered_before_token_gate() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// A token-less application heartbeat (old cached vxui-ws.js) must be
	// answered with a pong — NOT closed with 1008 like other gated messages.
	mut cl := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{read_timeout: 2 * time.second})!
	cl.connect()!
	cl.write_string('{"cmd":"ping","client_id":"pre-auth"}')!
	pong := read_text_until(mut cl, fn (s string) bool {
		return s.contains('"pong"')
	}) or {
		assert false, 'token-less ping was not answered with pong'
		return
	}
	assert pong.contains('pre-auth')

	// The connection survived: auth works on the same socket afterwards.
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	}), 'ping-before-gate must not have killed the connection'

	cl.close(1000, 'done') or {}
	ctx.ws.free()
}
```

Note: add `read_timeout: 2 * time.second` via `websocket.ClientOpt{...}` — struct is `@[params]`, fields are pub.

- [ ] **Step 2: Run test to verify it fails**

Run: `v test . 2>&1 | tail -20` (or target the test file: `v vxui_test.v` then run produced binary? Standard: `v test .`)
Expected: FAIL — connection closed before pong (`read_next_message` errors or auth never registers).

- [ ] **Step 3: Server-side fix in `vxui.v`**

Insert immediately AFTER the `if cmd := message['cmd'] { ... 'auth' ... }` block and BEFORE `if !message_token_valid(...)`:

```v
		// Application-level heartbeats carry no token on older cached
		// vxui-ws.js copies; answer them BEFORE the token gate so a session
		// can never be killed by its own keep-alive mechanism. Liveness
		// bookkeeping still requires a valid token.
		if cmd := message['cmd'] {
			if cmd.str() == 'ping' {
				if message_token_valid(message, true, ctx.config.token) {
					ctx.handle_pong(message)
				}
				mut pong := map[string]json2.Any{}
				pong['cmd'] = json2.Any('pong')
				pong['client_id'] = message['client_id'] or { json2.Any('') }
				pong['timestamp'] = json2.Any(time.now().unix_milli())
				ws.write(json2.encode(pong).bytes(), .text_frame)!
				return
			}
		}
```

(Note: pass `true` for require_auth here only when `ctx.config.require_auth` semantics matter — use `message_token_valid(message, ctx.config.require_auth, ctx.config.token)`.)

Final form uses: `message_token_valid(message, ctx.config.require_auth, ctx.config.token)`.

- [ ] **Step 4: JS-side fix in `js/vxui-ws.js`**

Replace the pingMsg construction (~L537):

```js
            // Send ping (must carry the token: the server rejects any
            // non-auth message without one)
            var pingMsg = {
                cmd: 'ping',
                client_id: clientId,
                token: token,
                timestamp: Date.now()
            }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `v test .`
Expected: PASS, including pre-existing `test_websocket_integration_auth_rpc_and_reject` (a token-less `pong` message is still rejected — only `ping` is exempt).

- [ ] **Step 6: Commit**

```bash
git status --short   # confirm doc/vxui-improvements.md absent
git add vxui.v js/vxui-ws.js vxui_test.v
git commit -m "fix: answer application heartbeats before the token gate and send token with client pings"
```

---

### Task 3: P0-1 — launch browser directly on Windows (no `cmd start` mangling of `&`)

Cannot runtime-test on Linux; correctness comes from API conformance (`os.new_process`/`set_args`/`run()` verified against vlib/os/process.c.v) plus keeping the POSIX path untouched.

**Files:**
- Modify: `browser.v` (~L314-329)

- [ ] **Step 1: Replace the Windows launch branch**

```v
	// Start browser process
	$if windows {
		// Spawn the browser directly instead of going through
		// `cmd /c start`: the URL arguments contain '&' (e.g.
		// ?vxui_ws_port=..&vxui_token=..) which cmd.exe treats as an
		// unquoted command separator, dropping the token and everything
		// after it. A direct spawn passes arguments verbatim.
		mut browser_process := os.new_process(browser_path)
		browser_process.set_args(cmd_args)
		browser_process.run()
	} $else {
		pid := os.fork()
		if pid == 0 {
			// Child process
			os.execvp(browser_path, cmd_args) or {
				eprintln('Failed to start browser: ${err}')
				exit(1)
			}
		} else if pid < 0 {
			return new_error_detail(VxuiError.process_fork_failed, 'Failed to fork process')
		}
	}
```

- [ ] **Step 2: Verify compilation (POSIX branch) and full suite**

Run: `v test .`
Expected: PASS (the `$if windows` arm is not compiled on Linux; the suite proves nothing regressed elsewhere).

- [ ] **Step 3: Commit**

```bash
git add browser.v
git commit -m "fix: spawn browser directly on Windows so URL params survive (cmd start mangled '&')"
```

---

### Task 4: P0-2 + P2-8 — `WindowMode` enum, `--app=` single-arg form, unique temp profile

Kiosk-by-default is wrong for desktop apps; `--app <url>` (space form) is ignored by Chromium; a shared persistent profile lets leftover Chrome processes swallow all flags. Introduce `WindowMode { app, kiosk, normal }` (default `.app`), emit `--app=<url>`, and give each run a fresh temp profile unless custom dirs are set. Keep `no_app_mode` working (deprecated alias for `.normal`).

**Files:**
- Modify: `vxui.v` (BrowserConfig ~L270-286)
- Modify: `browser.v` (profile selection ~L232, mode args ~L297-304)
- Test: `vxui_test.v`

**Interfaces:**
- Produces: `pub enum WindowMode { app kiosk normal }`; `BrowserConfig.window_mode WindowMode = .app`; private helpers `window_mode_args(mode WindowMode, url string) []string` and `effective_window_mode(config BrowserConfig) WindowMode`.

- [ ] **Step 1: Write failing tests**

Append to `vxui_test.v` near the browser/utility tests:

```v
fn test_window_mode_args_use_equals_form_for_app_mode() {
	url := 'file:///x/index.html?vxui_ws_port=1234&vxui_token=abc'
	assert window_mode_args(.app, url) == ['--app=${url}']
	assert window_mode_args(.kiosk, url) == ['--kiosk', url]
	assert window_mode_args(.normal, url) == [url]
	app_arg := window_mode_args(.app, url)[0]
	assert app_arg.starts_with('--app='), 'Chromium ignores space-form value switches'
	assert !app_arg.contains(' '), 'URL and flag must be ONE argument'
}

fn test_effective_window_mode_respects_legacy_no_app_mode() {
	mut cfg := BrowserConfig{}
	assert effective_window_mode(cfg) == .app // new default: plain app window
	cfg.no_app_mode = true
	assert effective_window_mode(cfg) == .normal // deprecated flag still honored
	mut cfg2 := BrowserConfig{window_mode: .kiosk}
	assert effective_window_mode(cfg2) == .kiosk
}
```

- [ ] **Step 2: Run to verify failure**

Run: `v test .`
Expected: FAIL — `window_mode_args`/`effective_window_mode` undefined; `WindowMode` unknown.

- [ ] **Step 3: Add enum + config field in `vxui.v`**

Directly above `pub struct BrowserConfig`:

```v
// WindowMode selects how the page window is presented. Only meaningful for
// Chromium-family browsers; Firefox/Safari open a normal tab regardless.
pub enum WindowMode {
	app    // standalone window WITHOUT address bar/tab strip (default)
	kiosk  // borderless fullscreen
	normal // an ordinary browser tab
}
```

Inside `BrowserConfig.pub mut:` replace the `no_app_mode bool` line with:

```v
	window_mode WindowMode = .app // presentation of the app window (see WindowMode)
	no_app_mode bool // DEPRECATED: legacy switch forcing a plain tab; use window_mode
```

Keep the rest of BrowserConfig unchanged.

- [ ] **Step 4: Implement helpers and rewire `browser.v`**

Add after `get_browser_args`:

```v
// window_mode_args returns the mode-specific launch argument(s) carrying the URL.
// Value-bearing Chromium switches MUST use the '=' form: `--app <url>` is parsed
// as a boolean flag plus a stray positional argument.
fn window_mode_args(mode WindowMode, url string) []string {
	match mode {
		.app {
			return ['--app=${url}']
		}
		.kiosk {
			return ['--kiosk', url]
		}
		.normal {
			return [url]
		}
	}
}

// effective_window_mode resolves the deprecated no_app_mode flag against window_mode.
fn effective_window_mode(config BrowserConfig) WindowMode {
	if config.no_app_mode {
		return .normal
	}
	return config.window_mode
}
```

Replace the profile selection (~L232):

```v
	profile_path := if browser_config.user_data_dir != '' {
		browser_config.user_data_dir
	} else if browser_config.profile_dir != '' {
		browser_config.profile_dir
	} else {
		// Fresh profile per run: a leftover Chrome process sharing a
		// persistent profile delegates to that existing instance and
		// silently swallows --app/--kiosk/window-size flags.
		os.join_path(os.temp_dir(), 'vxui_profile_${rand.u64()}')
	}
```

Add `import rand` to browser.v imports if missing.

Replace the mode block inside the `is_chrome_based` branch (~L297):

```v
		cmd_args << window_mode_args(effective_window_mode(browser_config),
			'file://${abs_path}?${url_params}')
```

- [ ] **Step 5: Run tests**

Run: `v test .`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add vxui.v browser.v vxui_test.v
git commit -m "feat: WindowMode config with --app= launches and per-run browser profiles"
```

---

### Task 5: P1-4 — fire-and-forget `post_js`, callback-leak fix, documented deadlock rule

`run_js(timeout_ms > 0)` called inside a route handler deadlocks: handlers run on the connection's read loop thread while `run_js` polls for a `js_result` only that same loop can deliver. Also, `timeout_ms <= 0` never deletes the registered `js_callbacks` entry (leak). Add `post_js`/`post_js_client`, clean registration on every exit path via `defer`, document the rule.

**Files:**
- Modify: `vxui.v` (`execute_js` ~L1301-1355, public wrappers ~L1372-1380)
- Modify: `AGENTS.md`, `README.md` (docs steps below)
- Test: `vxui_test.v`

**Interfaces:**
- Produces: `pub fn (mut ctx Context) post_js(js_code string) !`, `pub fn (mut ctx Context) post_js_client(client_id string, js_code string) !`. Contract: `execute_js` leaves `js_callbacks` empty on every return path.

- [ ] **Step 1: Write failing test**

```v
fn test_post_js_is_fire_and_forget_and_leaks_no_callback() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	mut cl := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{read_timeout: 2 * time.second})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	})

	ctx.post_js('void(0);')!
	// Registration must be gone immediately: post_js never waits.
	assert ctx.js_callbacks.len == 0, 'post_js left a pending js_callback'

	// The run_js command did go out on the wire (after the auth_ok frame).
	read_text_until(mut cl, fn (s string) bool {
		return s.contains('run_js') && s.contains('void(0)')
	}) or {
		assert false, 'post_js command never reached the client'
		return
	}

	cl.close(1000, 'done') or {}
	ctx.ws.free()
}
```

Also extend `RoutingTestApp` usage: no change needed (uses existing harness).

- [ ] **Step 2: Run to verify failure**

Run: `v test .`
Expected: FAIL — `post_js` undefined.

- [ ] **Step 3: Rework `execute_js` cleanup**

In `execute_js`, replace the register→write→poll sequence (~L1301) so the deletion happens on ALL paths:

```v
	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()
	defer {
		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
	}

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('run_js')
	cmd['js_id'] = json2.Any(js_id)
	cmd['script'] = json2.Any(js_code)
	cmd['timeout'] = json2.Any(timeout_ms)
	client_conn.write(json2.encode(cmd).bytes(), .text_frame)!

	ctx.trigger_event(EventType.js_execution, client_id, js_code, {
		'js_id': json2.Any(js_id)
	}, none, none, none)

	if timeout_ms > 0 {
		mut result := ''
		mut got_result := false
		deadline := time.now().unix_milli() + timeout_ms

		for time.now().unix_milli() < deadline {
			select {
				r := <-ch {
					result = r
					got_result = true
				}
				else {
					time.sleep(ctx.config.js_poll_ms * time.millisecond)
				}
			}
			if got_result {
				break
			}
		}

		ch.close()

		if !got_result {
			return new_error_detail(.js_timeout, 'JavaScript execution timeout')
		}

		if ctx.config.js_sandbox.enabled && result.len > ctx.config.js_sandbox.max_result_size {
			return new_error_detail(.js_result_too_large, 'Result exceeds maximum size')
		}

		return result
	}
	// timeout_ms <= 0: fire-and-forget; the result channel is dropped with
	// the registration removed by the defer above.
	return ''
```

Key points: the old explicit `ctx.js_callbacks.delete(js_id)` inside `if timeout_ms > 0` is REMOVED (defer covers it); `ch.close()` stays only in the consuming path so a late `js_result` finds either a live buffer or no map entry (`handle_js_result` skips unknown ids).

- [ ] **Step 4: Add public wrappers next to `run_js_client`**

```v
// post_js executes JavaScript in the frontend fire-and-forget: the result
// (or error) is discarded and the pending callback is unregistered
// immediately. Safe to call from INSIDE route handlers, unlike
// run_js(timeout_ms > 0), which deadlocks there: a handler runs on the
// connection read loop, the very goroutine that would deliver js_result.
pub fn (mut ctx Context) post_js(js_code string) ! {
	ctx.execute_js('', js_code, 0)!
}

// post_js_client is post_js targeting one specific client.
pub fn (mut ctx Context) post_js_client(client_id string, js_code string) ! {
	ctx.execute_js(client_id, js_code, 0)!
}
```

- [ ] **Step 5: Run tests**

Run: `v test .`
Expected: PASS (including pre-existing JS-timeout tests — behavior preserved because defer fires after the result is taken).

- [ ] **Step 6: Document the rule (AGENTS.md)**

In AGENTS.md "Attribute Tags / Routing rules" section append one bullet:

```markdown
- Route handlers execute on the WebSocket read-loop thread. Inside a handler,
  NEVER call `run_js(code, timeout)` with `timeout > 0` — it deadlocks until
  timeout (the read loop itself would need to deliver the result). Use
  fire-and-forget `post_js(code)!` / `post_js_client(id, code)!` there;
  reserve waiting calls for code running outside handlers or in `spawn`ed
  coroutines.
```

In README.md "Use run_js()" section append:

```markdown
```v
// Fire-and-forget: safe inside route handlers, result ignored
app.post_js('alert("saved")!')!
```

> Handlers run on the connection read loop. Waiting `run_js(timeout > 0)`
> calls from a handler deadlock until timeout — use `post_js` there.
```

- [ ] **Step 7: Commit**

```bash
git add vxui.v vxui_test.v AGENTS.md README.md
git commit -m "feat: post_js fire-and-forget API; fix js_callbacks leak; document handler deadlock"
```

---

### Task 6: P1-5 — classify auth failures and enrich unauthorized-message warnings

Auth failures already log at error level and auth success at info (visible under default `.info`). What is missing: WHY auth failed, and enough context in token-rejection warnings to tell "heartbeat forgot the token" apart from "forged message".

**Files:**
- Modify: `vxui.v` (`handle_auth` ~L805, token gate ~L576, raw payload capture ~L552)

- [ ] **Step 1: Capture raw payload once in `on_message`**

Change (~L552):

```v
		raw_payload := msg.payload.bytestr()
		raw_message := json2.decode[json2.Any](raw_payload)!
		message := raw_message.as_map()
```

- [ ] **Step 2: Enrich the rejection warning (~L576)**

```v
		if !message_token_valid(message, ctx.config.require_auth, ctx.config.token) {
			rejected_cmd := message['cmd'] or { json2.Any('') }.str()
			mut keys := []string{}
			for k, _ in message {
				keys << k
			}
			keys.sort()
			mut preview := raw_payload.replace('\n', ' ')
			if preview.runes().len > 96 {
				preview = preview.runes()[..96].map(it.str()).join('') + '…'
			}
			ctx.logger.warn('Unauthorized message rejected (missing or invalid token): cmd=${rejected_cmd} keys=[${keys.join(',')}] payload="${preview}"')
			ws.close(1008, 'Invalid token')!
			return
		}
```

(The rune-safe cut keeps multibyte payloads readable in logs.)

- [ ] **Step 3: Classify auth failure reasons in `handle_auth`**

Replace the first lines:

```v
	client_token := message['token'] or { json2.Null{} }

	if client_token is json2.Null {
		return new_error_detail(.auth_invalid_token, 'missing token')
	}
	if client_token.str() == '' {
		return new_error_detail(.auth_invalid_token, 'missing token')
	}
	if client_token.str() != ctx.config.token {
		return new_error_detail(.auth_invalid_token, 'invalid token')
	}
```

The caller already composes `'Auth failed: ${err}'` and logs it at error level → final messages: `Auth failed: missing token` / `Auth failed: invalid token`.

- [ ] **Step 4: Run suite**

Run: `v test .`
Expected: PASS (rejection behavior unchanged — `test_websocket_integration_auth_rpc_and_reject` still green).

- [ ] **Step 5: Commit**

```bash
git add vxui.v
git commit -m "fix: classify auth failures and add cmd/keys/payload context to token rejections"
```

---

### Task 7: P1-6 — `evict_on_new`: fresh auth takes over the single client slot

With `multi_client=false`, a crash-restored tab holding the old session blocks every new page ("app won't open"). Add `Config.evict_on_new`: when set (and multi-client off), a new successful auth closes all older sessions instead of the connect gate rejecting first.

**Files:**
- Modify: `vxui.v` (Config ~L327, connect gate ~L531, `handle_auth`)
- Test: `vxui_test.v`

**Interfaces:**
- Produces: `Config.evict_on_new bool` (default false — current behavior untouched unless opted in).

- [ ] **Step 1: Write failing test**

```v
fn test_evict_on_new_lets_fresh_auth_replace_stale_session() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	app.config.multi_client = false
	app.config.evict_on_new = true
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// First (soon-stale) session
	mut cl_a := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{read_timeout: 2 * time.second})!
	cl_a.connect()!
	cl_a.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.get_client_count() == 1
	})
	first_id := ctx.get_clients()[0]

	// Crash-recovery style reconnect with the same token takes over the slot
	mut cl_b := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{read_timeout: 2 * time.second})!
	cl_b.connect()!
	cl_b.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(3000, fn [ctx] () bool {
		return ctx.get_client_count() == 1 && ctx.get_clients()[0] != first_id
	}), 'fresh auth must evict the stale session'

	// The stale socket was closed by the server
	mut stale_closed := false
	for _ in 0 .. 40 {
		cl_a.read_next_message() or {
			stale_closed = true
			break
		}
		time.sleep(25 * time.millisecond)
	}
	assert stale_closed, 'evicted client should observe a close/error'

	cl_a.close(1000, 'done') or {}
	cl_b.close(1000, 'done') or {}
	ctx.ws.free()
}
```

- [ ] **Step 2: Run to verify failure**

Run: `v test .`
Expected: FAIL — second auth never replaces the first (`multi_client is disabled` rejection at connect).

- [ ] **Step 3: Config field**

In `Config`, Client settings block:

```v
	// Client settings
	multi_client bool
	// When multi_client is off, let a NEW successful authentication evict
	// stale sessions instead of letting a restored/crashed browser tab hold
	// the single slot forever.
	evict_on_new bool
	max_clients  int = 10
	rate_limit   RateLimitConfig
```

- [ ] **Step 4: Relax the connect gate (~L531)**

```v
		if !ctx.config.multi_client && !ctx.config.evict_on_new && client_count > 0 {
			ctx.logger.warn('Rejecting connection: multi_client is disabled')
			return false
		}
```

- [ ] **Step 5: Evict in `handle_auth` before registering the new client**

Insert between the token checks and `client_id := generate_client_id()`:

```v
	// evict_on_new: a fresh successful auth takes over the single client
	// slot; older sessions are closed so a restored tab cannot lock out
	// the real page.
	if ctx.config.evict_on_new && !ctx.config.multi_client {
		current_id := ctx.find_client_id_by_connection(ws)
		ctx.mu.rlock()
		mut stale_ids := []string{}
		for id, _ in ctx.clients {
			if id != current_id {
				stale_ids << id
			}
		}
		ctx.mu.runlock()
		for id in stale_ids {
			ctx.logger.info('Evicting stale client ${id} for new session')
			ctx.close_client(id) or {}
		}
	}
```

- [ ] **Step 6: Run tests**

Run: `v test .`
Expected: PASS including `test_websocket_integration_auth_rpc_and_reject` (its app does not set evict_on_new → gate still rejects).

- [ ] **Step 7: Document (AGENTS.md Multi-Client section)**

```markdown
### Single-slot takeover

```v
app.multi_client = false
app.config.evict_on_new = true // fresh auth evicts stale sessions
```

Without this, a crash-restored tab holding the old session blocks every new
connection when multi_client is disabled.
```

- [ ] **Step 8: Commit**

```bash
git add vxui.v vxui_test.v AGENTS.md
git commit -m "feat: Config.evict_on_new lets fresh auth replace stale single-slot sessions"
```

---

### Task 8: P1-7 — rune-safe payload sanitizer + write-failure diagnostics

Non-UTF-8 route responses make `ws.write` fail deep in the websocket lib ("malformed utf8") with zero routing context. Add `sanitize_utf8` for handlers and contextual error logging at the response write site.

**Files:**
- Modify: `utils.v` (add sanitizer)
- Modify: `vxui.v` (response write ~L663)
- Test: `vxui_test.v`

**Interfaces:**
- Produces: `pub fn sanitize_utf8(s string) string` (invalid sequences → U+FFFD, EF BF BD); private `(ctx &Context) log_write_failure(path string, rpc_id i64, payload string, err IError)`.

- [ ] **Step 1: Write failing tests**

```v
fn test_sanitize_utf8_passes_valid_text_through() {
	assert sanitize_utf8('hello') == 'hello'
	assert sanitize_utf8('中文备注') == '中文备注'
	assert sanitize_utf8('') == ''
	assert sanitize_utf8('mix中en文') == 'mix中en文'
}

fn test_sanitize_utf8_repairs_truncated_multibyte() {
	s := '中文备注'
	truncated := s.bytes()[..s.len - 1].bytestr() // cuts half of the last rune
	fixed := sanitize_utf8(truncated)
	assert utf8.validate_str(fixed), 'output must be valid UTF-8'
	assert fixed.starts_with('中文备')
}

fn test_sanitize_utf8_repairs_stray_continuation_bytes() {
	bad := [u8(0x61), u8(0x80), u8(0x62)].bytestr() // a, stray cont., b
	fixed := sanitize_utf8(bad)
	assert utf8.validate_str(fixed)
	assert fixed.len == 5 // 1 byte + U+FFFD(3 bytes) + 1 byte
	assert fixed[0] == u8(0x61) && fixed[4] == u8(0x62)
}
```

Test file needs `import encoding.utf8` added to its import block.

- [ ] **Step 2: Run to verify failure**

Run: `v test .`
Expected: FAIL — `sanitize_utf8` undefined.

- [ ] **Step 3: Implement in `utils.v`**

Add import `import encoding.utf8` and:

```v
// sanitize_utf8 returns `s` with every invalid UTF-8 byte replaced by the
// Unicode replacement character (U+FFFD). The websocket layer REJECTS text
// frames that are not valid UTF-8, so any payload built from byte-wise
// slicing of multibyte strings must be passed through this helper before
// being returned from a route handler.
pub fn sanitize_utf8(s string) string {
	if utf8.validate_str(s) {
		return s
	}
	replacement := [u8(0xEF), u8(0xBF), u8(0xBD)] // U+FFFD
	mut out := []u8{cap: s.len + replacement.len}
	mut i := 0
	for i < s.len {
		b := s[i]
		seq_len := match true {
			b < 0x80 { 1 } // ASCII
			b >= 0xC2 && b <= 0xDF { 2 }
			b >= 0xE0 && b <= 0xEF { 3 }
			b >= 0xF0 && b <= 0xF4 { 4 }
			else { 0 } // continuation byte out of place or invalid lead
		}
		valid := seq_len > 0 && i + seq_len <= s.len
			&& utf8.validate_str(s[i..i + seq_len])
		if valid {
			out << s[i..i + seq_len].bytes()
			i += seq_len
		} else {
			out << replacement
			i++
		}
	}
	return out.bytestr()
}

// log_write_failure records a failed text-frame write with routing context
// and a hex prefix, so non-UTF-8 or oversized payloads show up as a
// diagnosable error instead of a mysterious disconnect.
fn (ctx &Context) log_write_failure(path string, rpc_id i64, payload string, err IError) {
	n := if payload.len > 32 { 32 } else { payload.len }
	hex_preview := payload.bytes()[..n].hex()
	ctx.logger.error('WebSocket write failed for path=${path} rpcID=${rpc_id}: ${err} payload_hex[0..${n}]=${hex_preview}')
}
```

Check `utils.v` header: it currently has no imports needed beyond what exists; `encoding.utf8` import goes with the others. `log_write_failure` may live in utils.v only if `Context` is visible there (same module — yes).

- [ ] **Step 4: Guard the response write in `vxui.v` (~L663)**

```v
			json_response := '{"rpcID":"${rpc_id.i64()}", "data":${json2.encode(response.body)}}'
			ws.write(json_response.bytes(), .text_frame) or {
				ctx.log_write_failure(req.path, rpc_id.i64(), json_response, err)
				return
			}
```

- [ ] **Step 5: Run tests**

Run: `v test .`
Expected: PASS.

- [ ] **Step 6: Document (AGENTS.md Backend Development item 3)**

Amend to: "Return `string` (HTML fragment). Fragments MUST be valid UTF-8 — byte-wise truncation of multibyte strings breaks them; wrap risky payloads in `vxui.sanitize_utf8(payload)`."

- [ ] **Step 7: Commit**

```bash
git add utils.v vxui.v vxui_test.v AGENTS.md
git commit -m "feat: sanitize_utf8 helper and contextual logging for websocket write failures"
```

---

### Task 9: P2-10 partial + P2-9 note — fail fast on bad tagged methods; honest comptime docs

Verified against V 0.5.2: the doc's suggested `continue` guards do NOT compile and runtime filters cannot stop per-method instantiation of the dispatch call. Ship what IS possible: `generate_routes` rejects attribute-tagged methods that don't return string (clear startup error, veb-style), and `fire_call`'s NOTE documents the tested compiler reality. P2-9 (V vmod lookup quirk) becomes a README note.

**Files:**
- Modify: `vxui.v` (`generate_routes` ~L1048, `fire_call` comment ~L984)
- Modify: `README.md` (Notes section)
- Test: `vxui_test.v`

**Interfaces:**
- Produces: `generate_routes[T]` returns error `'method \`X\` has route attributes but must return string, got ...'` for tagged non-string methods. No signature changes otherwise.

- [ ] **Step 1: Write failing test**

```v
struct BadReturnApp {
	Context
}

@['/bad']
fn (mut app BadReturnApp) bad_handler(message map[string]json2.Any) int {
	return 1
}

fn test_generate_routes_rejects_tagged_non_string_method() {
	mut app := BadReturnApp{}
	generate_routes(app) or {
		assert '${err}'.contains('return string'), 'unexpected error: ${err}'
		return
	}
	assert false, 'tagged method returning non-string must be rejected at startup'
}
```

(Safe to declare: `fire_call` only instantiates STRING-returning methods, so `bad_handler` returning int creates no dispatch call site.)

- [ ] **Step 2: Run to verify failure**

Run: `v test .`
Expected: FAIL — generate_routes currently accepts the tagged int method silently.

- [ ] **Step 3: Validate return type in `generate_routes`**

```v
pub fn generate_routes[T](app &T) !map[string]Route {
	mut routes := map[string]Route{}
	$for method in T.methods {
		$if method.return_type is string {
			// Only attribute-tagged methods become routes; untagged methods
			// are plain helpers and must not be reachable from the frontend.
			if method.attrs.len > 0 {
				verbs, route_path := parse_attrs(method.name, method.attrs) or {
					return new_error_detail_with_cause(VxuiError.attribute_parse_error,
						'Error parsing method attributes', err)
				}
				routes[method.name] = Route{
					verb: verbs
					path: route_path
				}
			}
		} $else {
			// Tagged methods are dispatched with (mut app, message) and MUST
			// return string; anything else tagged is a configuration mistake
			// worth failing fast on (mirrors veb's route validation).
			if method.attrs.len > 0 {
				return new_error_detail_with_details(VxuiError.attribute_parse_error,
					'method `${method.name}` has route attributes but must return string', {
					'method':      method.name
					'return_type': method.return_type.str()
				})
			}
		}
	}
	return routes
}
```

(Check `method.return_type.str()` availability — it is a Type wrapped value in $for context supporting `.str()`; if the checker refuses, drop the details map entry and interpolate `'${method.return_type}'` into the message.)

- [ ] **Step 4: Rewrite the `fire_call` NOTE honestly**

Replace the NOTE comment above `fire_call`:

```v
// fire_call calls the method
// Only methods carrying route attributes (@['/path'] and/or a verb) are
// dispatchable; untagged helper methods are invisible to routing.
//
// NOTE on V comptime limits (tested on V 0.5.2 / 9142d68): the dispatch call
// below is instantiated ONCE FOR EVERY string-returning method of T,
// regardless of attributes — runtime `if` guards do not gate comptime
// instantiation, `$for attr in method.attributes` nesting parses but does
// not gate it either, and `continue` is illegal inside `$for`. Helpers on
// the app struct must therefore return void/non-string types (or take no
// parameters): a string-returning helper with custom parameters will not
// compile. generate_routes fails fast when a TAGGED method has the wrong
// return type, which keeps this constraint discoverable at startup.
pub fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
```

Body unchanged.

- [ ] **Step 5: Update examples/run-js-playground/main.v comment**

Its line-40 comment says "Must not return string: fire_call dispatches every string-returning method." — still accurate; leave as-is.

- [ ] **Step 6: README Notes addition (P2-9)**

Under README "Notes" section add:

```markdown
6. **Local modules using `#flag @VMODROOT/...`**: on V ≤ 0.5.2 a local module
   in a subdirectory needs its own `v.mod` for `@VMODROOT` to resolve, even
   when the project root already has one ("need a v.mod in <module file>, or
   in one of its parent folders"). Drop a minimal `v.mod` into that module's
   directory.
```

(renumber if a list already exists — adapt to actual README structure during execution)

- [ ] **Step 7: Run tests**

Run: `v test .`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add vxui.v vxui_test.v README.md
git commit -m "fix: fail fast on tagged non-string handlers; document comptime dispatch limits"
```

---

### Task 10: Release chores — CHANGELOG, version bump, full verification

**Files:**
- Modify: `CHANGELOG.md`, `v.mod`
- Verify: whole suite + representative example builds

- [ ] **Step 1: Bump version**

`v.mod`: `version: '0.6.2'`.

- [ ] **Step 2: CHANGELOG entry**

Prepend a `## 0.6.2` section summarizing (match existing changelog tone):

- Windows: browsers spawn directly (no `cmd start`), URL `&params` survive
- Default window is now a standalone `--app=` window (`WindowMode.app`); `kiosk`/`normal` selectable via `BrowserConfig.window_mode`; `no_app_mode` deprecated but honored
- Per-run temp browser profile by default (leftover Chrome instances can no longer swallow launch flags)
- Application heartbeats answered before the token gate; client pings carry the token — idle sessions survive past 30s
- New `post_js` / `post_js_client` fire-and-forget APIs; fixed `js_callbacks` leak for fire-and-forget runs; documented handler-vs-run_js deadlock
- Auth failures now say why (missing vs invalid token); token rejections log cmd/keys/payload preview
- New `Config.evict_on_new`: fresh auth evicts stale sessions when `multi_client=false`
- New `sanitize_utf8()` helper; failed response writes now log path/rpcID/payload hex
- `generate_routes` fails fast on tagged methods not returning string

- [ ] **Step 3: Full verification**

Run: `v test .`
Expected: all tests PASS.

Run: `v -o /tmp/opencode/vxui_example_check examples/test/main.v` then delete the binary.
Expected: compiles clean (examples consume the public API; catches accidental breaking changes).

Run: `git status --short` — confirm `doc/vxui-improvements.md` is absent.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md v.mod
git commit -m "chore: release 0.6.2"
```

---

## Self-Review

**Spec coverage:** P0-1→Task 3; P0-2→Task 4; P0-3→Task 2; P1-4→Task 5; P1-5→Task 6 (note: doc's claim that info-level auth logs are invisible was stale — default level is `.info`; classification/context added where genuinely missing); P1-6→Task 7; P1-7→Task 8; P2-8→Task 4; P2-9→Task 9 Step 6; P2-10→Task 9 Steps 1-5 (partial, with verified rationale recorded in Global Constraints).

**Placeholder scan:** none — every code step shows complete code; the two conditional notes (return_type `.str()`, README numbering) name the exact fallback.

**Type consistency:** `window_mode_args/effective_window_mode` defined Task 4 used only there; `post_js/post_js_client` Task 5 signatures consistent; `evict_on_new` referenced identically in Config/gate/handle_auth/tests; `sanitize_utf8`/`log_write_failure` signatures consistent between definition and call sites.
