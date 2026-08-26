# Simplify & Refactor vxui Framework

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify and refactor the vxui framework core for clarity and maintainability. The user explicitly waived backwards-compatibility ("不必考虑兼容性问题"), so we MAY remove/rename public APIs and restructure files — but runtime behavior (desktop UI over WebSocket to a browser) must be preserved and all tests must pass.

**Scope:** Framework core only — `vxui.v`, `display.v`, `utils.v`, `embed.v`, `js/vxui-ws.js`, and the framework tests (`vxui_test.v`, `display_test.v`). Examples are touched ONLY if they call something we remove (verified: none call `set_window_*`, none reference `webview`).

**Explicit decisions (judgment calls):**
- **KEEP** the `Display`/`DisplaySession` abstraction and the reserved `WebViewDisplay`/`WebViewConfig`/`set_webview_config`/`.webview` branch. This is the project's chosen direction (pluggable backends); removing it would undo prior work. It is NOT "dead code" in the sense we want gone.
- **REMOVE** `set_window_size`/`set_window_position`/`set_window_title`: no example callers, and they are misleading no-ops for the browser backend (same bug class as the already-removed `set_resizable`).
- **SKIP** for this pass: `JsSandboxConfig` reconciliation (D3/D4, low value), and gating timing-based integration tests (F2, hygiene only).

**Tech Stack:** V 0.5.2. Same module (`vxui`); comptime `$for method in T.methods` dispatch and `context_of` must keep resolving after any file split.

## File Structure (after Task 4)
- `vxui.v` (orchestrator: `run`, `Context`, wiring) + new sibling files:
  - `errors.v` — `VxuiError`, `VxuiErrorDetail`
  - `events.v` — `EventType`, `EventData`, `trigger_event`, `on_event`
  - `config.v` — `Config` + sub-configs (`JsSandboxConfig`, `WindowConfig`, `WindowMode`, `BrowserConfig`, `LogConfig`, `DevConfig`)
  - `clients.v` — `Client`, client mgmt, `broadcast*`, `send_to_client`, `ping_*`, `process_client_removals`, `check_client_timeouts`
  - `ws.v` — `startup_ws_server`, `handle_control_message` (+ split handlers), `dispatch_rpc`, `find_client_id_by_connection`, `handle_auth`, `handle_pong`, `handle_js_result`, `message_token_valid`, `addr_is_loopback`
  - `routing.v` — `Route`, `generate_routes`, `parse_attrs`, `fire_call`, `handle_request`, `build_request`
  - `jsexec.v` — `execute_js`, `validate_js_code`, `run_js`, `run_js_client`, `post_js`, `post_js_client`, `send_cmd`/`broadcast_cmd` helpers
  - `displaymgr.v` — `open_window*`, `set_window_*`, `set_*_config`, `close_displays`, `get_port`/`get_token`
- `display.v`, `utils.v`, `embed.v`, `js/vxui-ws.js` — pruned by Tasks 1–2.

---

## Task 1: Dead-code & misleading-API purge

**Files:** `vxui.v`, `utils.v`, `display.v`, `vxui_test.v`, `display_test.v`

- [ ] **A1** — Remove `Client.request_count`, `Client.last_request`, `Client.connected` (vxui.v ~337-338, init at ~805-812). Update `vxui_test.v` `test_client_struct` (~242-260).
- [ ] **A2** — Delete `fn find_browser_path()` wrapper (display.v ~428-430).
- [ ] **A4** — Remove `VxuiError` members `connection_error`, `connection_closed`, `invalid_message`, `request_timeout`, `method_not_allowed` (vxui.v ~30-46). Remove their test assertions in `vxui_test.v` (~1349-1350, 1356-1357, 1561, 1565, 1568-1569). Keep `unknown` (zero value).
- [ ] **A6 + D5** — Remove `Response.headers` field (vxui.v ~193) + test (`vxui_test.v` ~116-128). Slim `Request` to `{ verb, path, client_id, raw_message }` (drop `parameters`/`headers`/`body`/`id`/`timestamp`; update `build_request` ~706-751 and its tests ~110-1415). Confirm `handle_request` only reads `verb`/`path` — keep those.
- [ ] **D2** — Remove `set_window_size`/`set_window_position`/`set_window_title` (vxui.v ~1577-1601) + their tests (`vxui_test.v` ~320-337).
- [ ] **A5** — Delete unused public utils in `utils.v`: `escape_html`, `escape_attr`, `is_valid_email`, `truncate_string`, `generate_id`, and their tests (`vxui_test.v` `test_escape_html`/`test_escape_attr`/`test_is_valid_email`/`test_truncate_string`/`test_generate_id`, ~1186-1253). KEEP `escape_js` (used in `handle_auth`) and `sanitize_utf8` (public, documented).
- [ ] **Verify:** `v test vxui_test.v` + `v test display_test.v` PASS; `v fmt -diff` clean; `v build` (via `v test`) green.

---

## Task 2: JSON correctness + DRY envelopes

**Files:** `vxui.v` (and `jsexec.v` after Task 4)

- [ ] **C1** — Build the error/404 frames via `json2.encode(map[string]json2.Any{...})` instead of raw string interpolation: vxui.v ~666 (`route_not_found` with `req.path`) and ~935 (`'{"error": "${err}"}'`). Escape interpolated values by going through `json2.encode`.
- [ ] **B1** — Add private helpers:
  ```v
  fn (mut ctx Context) send_cmd(mut conn &websocket.Client, cmd string, extra map[string]json2.Any) ! {
  	mut m := map[string]json2.Any{}
  	m['cmd'] = cmd
  	for k, v in extra { m[k] = v }
  	ctx.send_to_client(conn, json2.encode(m).bytes()) or {}
  }
  fn (mut ctx Context) broadcast_cmd(cmd string, extra map[string]json2.Any) {
  	mut m := map[string]json2.Any{}
  	m['cmd'] = cmd
  	for k, v in extra { m[k] = v }
  	ctx.broadcast(json2.encode(m)) or {}
  }
  ```
  Replace the ~7 hand-built envelope sites (pong ~585, get_clients ~633, auth_ok ~819, run_js ~1311, ping_client ~1531, ping_all_clients ~1539, trigger_hot_reload ~1687) with these helpers.
- [ ] **Verify:** `v test vxui_test.v` PASS; `v fmt -diff` clean.

---

## Task 3: Structural readability (run loop + control dispatch)

**Files:** `vxui.v` (and `run.v`/`ws.v` after Task 4)

- [ ] **C2** — Extract from `run()`'s `for` loop (~1124-1203) three small helpers called from the loop: `should_shutdown(had_clients bool, empty_since time.Time, last_client_time time.Time) bool`, `maybe_hot_reload(watch_dirs []string, mut file_mtimes map[string]time.Time)`, `maybe_heartbeat(mut last_ping_time time.Time)`. Keep `run()` a readable skeleton. Behavior identical.
- [ ] **C3** — Split `handle_control_message` (~557-642) into `handle_ping(mut conn)`, `handle_get_clients(mut conn)`, `handle_client_close(mut conn)`, and a thin `handle_control_message` that switches on `cmd` (reusing existing `handle_auth`, `handle_js_result`, `handle_pong`). No behavior change.
- [ ] **Verify:** `v test vxui_test.v` PASS; `v fmt -diff` clean.

---

## Task 4: Split vxui.v into focused files

**Files:** `vxui.v` → `errors.v`, `events.v`, `config.v`, `clients.v`, `ws.v`, `routing.v`, `jsexec.v`, `displaymgr.v`, `run.v` (same `vxui` module).

- [ ] Move code by concern per the File Structure above. `Context` struct stays in `vxui.v` (or `context.v`); keep `run`/`run_packed` as the orchestrator entry. Ensure `import` lines are correct per file; `context_of` and `[T]` comptime dispatch must still resolve (same module, so generics work across files).
- [ ] `send_cmd`/`broadcast_cmd` (Task 2) live in `jsexec.v` (or wherever `Context` methods cluster). `open_window*`/display methods in `displaymgr.v`.
- [ ] **Verify (critical):** `v test .` is known to hang under V3 parallel — run per-file: `v test vxui_test.v`, `v test display_test.v`, and any example `*_test.v`. Build examples: `game-2048 game-gomoku game-minesweeper markdown-editor multi-window todo-app enchart element-plus packed`. All expected to compile. `v fmt -diff` clean.

---

## Task 5: Verification + CHANGELOG

- [ ] Run full matrix: `v test vxui_test.v` + `v test display_test.v` (all PASS); build all 9 examples (binaries produced); `v fmt -diff` clean on touched files.
- [ ] Add CHANGELOG entry under Unreleased "### Changed" (note: breaking removals are intentional per no-compat directive): removed dead `Client` fields, `find_browser_path`, unused `VxuiError` members, unused utils (`escape_html`/`escape_attr`/`is_valid_email`/`truncate_string`/`generate_id`), `Response.headers`; slimmed `Request`; removed no-op `set_window_*`; added `send_cmd`/`broadcast_cmd`; split `vxui.v` into focused modules.
- [ ] Commit (if fmt/changelog changes). If no changes beyond prior tasks, report "no commit needed".

---

## Self-Review
1. **Spec coverage:** Dead-code (A1,A2,A4,A5,A6,D5,D2) ✓ Task 1; JSON+DRY (C1,B1) ✓ Task 2; structure (C2,C3) ✓ Task 3; file split (E1) ✓ Task 4; verify+CHANGELOG ✓ Task 5. WebView stub KEPT ✓.
2. **Behavior preserved:** Every task keeps `run()`'s shutdown grace/heartbeat/hot-reload, control-message dispatch, routing, `run_js` semantics, broadcast, display lifecycle. Tests pass after each task.
3. **Placeholder scan:** No TBDs. `send_cmd`/`broadcast_cmd` are the only new helpers.
4. **Type consistency:** After Task 4 split, `Context` fields referenced across files remain in `vxui` module; `websocket`, `json2`, `time`, `os` imports added per new file as needed.
