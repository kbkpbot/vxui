# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`WindowMode`** (`BrowserConfig.window_mode = .app | .kiosk | .normal`, default
  `.app`): the default window is now a standalone app window WITHOUT address bar,
  launched with the `=`-form `--app=<url>` (Chromium ignores the space form).
  The legacy `no_app_mode` flag still works but is deprecated in favor of
  `window_mode: .normal`.
- **Per-run browser profiles**: when neither `user_data_dir` nor `profile_dir` is
  set, each run gets a fresh temp profile — a leftover Chrome process sharing a
  persistent profile can delegate to the existing instance and silently swallow
  `--app`/`--kiosk`/window flags.
- **`post_js()` / `post_js_client()`**: fire-and-forget JS execution, safe to call
  from inside route handlers. Unlike `run_js(timeout > 0)` it never blocks the
  connection read loop on a result only that same loop could deliver (documented
  deadlock). The fire-and-forget path also no longer leaks its `js_callbacks`
  registration.
- **`Config.evict_on_new`**: with `multi_client=false`, a fresh successful auth
  now evicts stale sessions so a crash-restored tab cannot hold the single slot
  forever ("app won't open").
- **`sanitize_utf8()`**: replaces invalid UTF-8 bytes with U+FFFD; wrap risky
  payloads (byte-wise truncation of multibyte strings) before returning them
  from handlers. Failed response writes now log path, rpcID and a payload hex
  preview instead of failing deep inside the websocket layer.
- **Diagnostics**: auth failures now say why (`Auth failed: missing token` /
  `invalid token`) and token rejections log cmd/keys/payload preview, e.g.
  `rejected ... cmd=ping keys=[cmd,client_id,timestamp]` — instantly separating
  "heartbeat forgot its token" from forged messages.
- **Security gates** — the WebSocket server now (1) rejects connections from
  non-loopback interfaces unless `config.allow_remote = true`, and (2) enforces
  `config.require_auth` on every regular message: a missing token is rejected with
  1008 just like a wrong one. Previously the server bound all interfaces and
  token-less messages sailed through — anyone on the LAN could invoke app routes.
- **Client enumeration**: authenticated `get_clients` command replies `clients`
  with connected ids; vxui-ws.js exposes `requestClients()` / `getClients()` plus a
  `vxui:clients` event. run-js-playground's target dropdown is now populated for real.
- **Window/page title**: `window.title` (or a customized `app_name`) is applied to
  the page via `document.title` when a client connects.
- **JS reconnect cap**: reconnection stops after `maxReconnectAttempts` (default 10)
  and surfaces a persistent "reconnect failed" state + `vxui:reconnectFailed` event.

### Changed

- **Routing: attribute-gated only** — methods without `@[...]` attributes are no longer
  registered as routes. Previously every method became callable (untagged methods used
  `/method_name` implicitly), which made helper methods on the app struct either break
  compilation (string-returning helpers with custom parameters) or leak as hidden void
  routes. Tag your handlers explicitly (`@['/path']`, a verb, or both); see AGENTS.md.
  Examples `test` and `enchart` were migrated to explicit tags.
- **Server callbacks re-derive their Context from the captured app on every event**
  instead of capturing a second Context pointer — fixes routes silently returning 404
  when the two pointers diverged (caught by the new WebSocket integration tests).
- **Config honesty sweep**
  - `LogConfig`: removed never-implemented `max_file_size`/`rotate_files`/
    `show_timestamp`/`show_level`; `output` ('stderr' | 'stdout' | file path) is now
    actually wired up
  - `WindowConfig`: removed never-implemented `resizable`/`min_width`/`min_height`/
    `frameless`/`transparent` and the `set_resizable()` setter; `set_window_title()`
    now genuinely works (see title injection above)
  - `BrowserConfig.preferred_path` is now honored by browser detection
- **Heartbeat unification**: the odd text-`pong` reply to protocol-level pong frames is
  gone; application liveness uses only the JSON cmd ping/pong
- **Module Layout**: Moved all V sources from `src/` to the module root
  - Required by newer V compilers that no longer support `src/` as a virtual module root
  - Examples now compile again (`v run main.v` inside any `examples/*/`)
- **Internal Context Access**: Generic entry points (`run`, `init`, server callbacks) now access
  the embedded `Context` through an internal `context_of()` helper instead of promoted field
  access, keeping `Context` internals private while remaining compatible with cross-module
  generic instantiation
- **Config Wiring**: `ws_ping_interval_ms` and `ws_pong_timeout_ms` are now actually used by the
  runtime (previously hardcoded to 30s/60s)
- **Broadcast Resilience**: `broadcast`, `broadcast_except` and `trigger_hot_reload` skip
  per-client write failures instead of aborting the whole loop on the first stale connection

### Fixed

- **file-upload: uploading a file killed the session** — three stacked issues:
  the server's protocol-ping watchdog ran at a hardcoded 1-second interval
  (closing any client whose read loop was busy for >2s, e.g. while receiving a
  multi-MB upload — "no pong received" → app exit). The interval is now driven
  by `config.ws_ping_interval_ms` (30s default, 60s watchdog). The example now
  uploads in 1.5MB chunks (a multiple of 3, so per-chunk base64 has no
  mid-stream `=` padding) with a new `/upload-chunk` handler, and strips the
  `data:` prefix from EVERY chunk (readAsDataURL prefixes all of them).
  New public APIs in vxui-ws.js: `rpc(payload)` (Promise-based raw rpc) and
  `applyResponseHtml(html, targetSelector)` (run a response body through the
  standard oob/swap pipeline).
- **WebSocket RPC responses now honor `hx-swap-oob`** — `vxui-ws.js` processed
  responses with a plain innerHTML swap, so an all-OOB response (e.g. data-table's
  `<tbody hx-swap-oob>` plus pager) was dumped into the target and mangled by the
  HTML parser: the table stayed empty until the next interaction. Responses are
  now handled exactly like htmx's XHR path — OOB elements swap into their own
  targets first, the remainder swaps into `hx-target`, and an OOB-only response
  skips the target swap instead of wiping it.
- **chat example: messages never displayed** — the hidden `cid` input lived
  OUTSIDE both forms, so `/join` and `/send` always failed their `cid == ''`
  guard and returned before broadcasting anything (form still switched, hiding
  the failure). `cid` inputs now live inside each form and are synced at
  submit time; chat bubbles additionally carry
  `hx-swap-oob="beforeend:#messages"` so the frontend actually inserts them.
- **Windows launch**: browsers are spawned directly via `os.new_process`
  instead of `cmd /c start`, whose shell parsing truncated URL parameters at the
  first unquoted `&` — tokens were dropped and every session was rejected (1008)
  under default config on Windows.
- **Heartbeat self-kill**: application-level `{cmd:"ping"}` heartbeats carry no
  token on older cached vxui-ws.js copies; the server now answers them before
  the token gate (liveness bookkeeping still requires a valid token) and the JS
  client includes its token in pings. Idle sessions survive past 30 s.
- **Startup validation**: `generate_routes` fails fast when an attribute-tagged
  method does not return `string` instead of registering a route that cannot be
  dispatched.
- **Audit: pre-auth command surface closed (Critical)** — `js_result`/`pong`/`client_close`
  ran before the token gate, so any local web page could drive-by connect to the loopback
  port and forge run_js results, keep zombie clients alive, or evict real ones. Now only
  the `auth` handshake is reachable without a token; vxui-ws.js sends its token on all
  three commands
- **Audit: loopback gate now checks the PEER address** (`TcpConn.peer_addr()`) instead of
  the local endpoint it was dialed on, and recognizes `::ffff:127.` IPv4-mapped forms
- **Audit: rate limiter re-hardened** — `blocked_until` is cleared when a punishment
  block is consumed; without this the limiter stayed permanently bypassed after the
  first block (pinned by a steady-traffic regression test)
- **JS lifecycle races** — per-attempt socket generation id guards stale onopen/onclose
  handlers from clobbering a newer connection; `retryCount` resets on full auth success
  instead of mere TCP open, so an open/flap server can no longer churn reconnects
  forever
- **Rate limiter**: a completed punishment block now grants a fresh window — previously
  the leftover over-limit count re-blocked the client in short pulses until the original
  window slid, making `block_duration` meaningless
- **JS connect timeout**: stalled WebSocket handshakes now abort after
  `config.connectTimeout` (ms) and fall into the reconnect path instead of freezing the
  message queue forever; `connectTimeout` was previously declared but never used
- **Lock hygiene**: `client_disconnected` events now fire AFTER releasing the context
  write lock in both the timeout sweep and the removal channel loop — handlers can call
  back into Context APIs (`broadcast`, `get_clients`, ...) and do network IO without
  holding up the removal pipeline or risking recursive-lock deadlocks on pthread-backed
  platforms
- **Safari launch (macOS)**: a failed `open -a Safari` is now returned as a structured
  error instead of being silently ignored
- **data-table example**: filtering while on a high page now clamps to the last valid
  page (pager state matches served rows) instead of rendering an empty view
- **chat example**: nickname no longer double-escaped in the leave broadcast
- **data-table example**: silenced unused-parameter notice on `/reset-sort`
- **system-monitor example**: removed dead `last_sample` field
- **rpcID Collisions (JS)**: `generateRpcID()` now combines `Date.now()` with a counter so
  simultaneous htmx requests in the same millisecond no longer overwrite each other in
  `pendingRequests`

### Added

- **game-minesweeper example**: 16×16/40 mines with mouse-precision
  interaction (left = reveal, right = flag via contextmenu), first-click-safe
  generation, flood-fill openings, server-side timing, and the classic Win95
  bevel look. Demonstrates the programmatic `rpc()` + `applyResponseHtml()`
  API pair alongside 2048's declarative style.

### Fixed

- **F5 reload killed the app** (single-client mode): the page's beforeunload
  `client_close` removed the client synchronously, the event loop saw "all
  clients disconnected" and shut down before the reloading page could
  reconnect. The event loop now holds a 1.5s grace window after the last
  client leaves; a reconnecting client cancels the shutdown (regression test
  `test_reconnect_within_grace_window_keeps_server_alive`).
- **`evict_on_new` now defaults to true**: without it the same reload race
  rejected the fresh connection under `multi_client = false`.
- **Google Translate popup suppressed by default**: Chromium's translate
  prompt appeared on every fresh profile whenever the page language differed
  from the browser UI language. The obsolete `--disable-translate` flag (no
  effect on current Chromium) is replaced by merging
  `Translate,TranslateUI,TranslateMessageUI` into the single
  `--disable-features` switch (repeated `--disable-features` flags overwrite
  each other), and fresh temp profiles are pre-seeded with
  `{"translate":{"enabled":false}}` in `Default/Preferences`. User-supplied
  `user_data_dir`/`profile_dir` settings are never overwritten.
- **run-js-playground: every button failed with "JavaScript execution timeout"**.
  The example called the blocking `run_js()` inside route handlers — handlers
  run on the connection read loop, the very coroutine that would deliver the
  `js_result` they wait for (the documented deadlock constraint in AGENTS.md).
  `run_and_log()` now runs its waiting call in a spawned coroutine; all six
  demo buttons verified working end-to-end in a real browser. The example also
  opts out of the default `setTimeout(`/`setInterval(` sandbox ban, which
  blocked its auto-dismissing toast.

### Removed

- **Dead config**: `JsSandboxConfig.allowed_apis` was never consulted —
  validation only ever checked `forbidden_patterns`. The field is gone
  (vxui-ws.js keeps syncing it harmlessly).
- **Middleware system and rate limiting**: both were web-server concepts with
  zero real-world usage (no example, test scenario, or doc recipe ever used
  them) and are gone outright — `Middleware`/`MiddlewareContext`/
  `MiddlewareResult`, `Context.use()`, `RateLimitConfig`,
  `Config.rate_limit`, `check_rate_limit()`, `set_rate_limit()`, the
  `middleware_rejected` / `rate_limited` error codes and the
  `middleware_error` event. A loopback desktop UI has no caller to throttle
  and no middleware pipeline to compose; request handling is now a straight
  route dispatch between the before/after_request events.
- **Dead public API** (zero callers in examples, tests, or docs):
  `run_with_config()` (set `app.config` directly before `run()`),
  `run_embedded()` (use `new_packed_app()` + `add_file_string()` +
  `run_packed()`), `use_logger()` / `use_auth()` middleware helpers (compose
  with `use()` instead), and `VxuiErrorDetail.full_message()`.
- **`BrowserConfig.no_app_mode`**: the deprecated legacy flag was removed;
  use `window_mode: .normal` for a plain tab.
- **file-upload example**: removed. In the local-desktop positioning (backend
  and browser share one filesystem), shipping file bytes through the browser
  and back over loopback is wasted motion — the backend can simply be handed a
  path. Small in-browser payloads (drag-and-drop, clipboard) remain served by
  the standard htmx request path.
- **Dead Config**: Removed `ReconnectConfig`, `RequestConfig` and `BackoffStrategy`
  (and `Config.reconnect` / `Config.request`) — they were never implemented; reconnection
  lives entirely in `vxui-ws.js`. Re-add alongside a real implementation if needed.
- **Dead Code**: Removed unused `ResponseOption` type and `VxuiErrorDetail.err()`
  (errors are now returned as structured `VxuiErrorDetail` directly, preserving `code`/`details`)

## [0.6.3] - 2026-02-26

### Added

- **$tmpl Template Support**: Examples now use V's built-in `$tmpl` for cleaner HTML generation
  - All examples refactored to separate HTML templates from V code
  - Templates located in `templates/` subdirectories
  - Zero runtime overhead (compiled at build time)
  - Supports `@if`, `@for`, `@else` and direct struct field access

- **Browser Config Option**: New `no_app_mode` setting in `BrowserConfig`
  - Set `no_app_mode = true` to disable kiosk mode
  - Allows file dialogs to work properly in file-upload example
  - Useful when native OS dialogs are needed

### Changed

- **Browser Launch Mode**: Changed from `--app` to `--kiosk` mode for Chrome
  - Better fullscreen experience
  - Use `no_app_mode = true` for standard window mode

### Examples

- `examples/file-upload`: Refactored with `$tmpl`, added `templates/file_list.html`
- `examples/gallery`: Refactored with `$tmpl`, added template files for table, tabs, notifications, progress
- `examples/test`: Refactored with `$tmpl`, added contact view/edit templates
- `examples/todo-app`: Refactored with `$tmpl`, added `templates/todo_list.html`

## [0.6.2] - 2026-02-25

### Added

- **OOB Update Command**: New `oob_update` command for broadcasting HTML updates to multiple clients
  - Backend can push HTML fragments to all connected clients
  - Supports CSS variable updates via data attributes (`data-bg`, `data-accent`, `data-font-size`)
  - Automatically rebinds htmx event listeners after DOM updates
- **Chrome Remote Debugging Support**: 
  - New `remote_debug_port` option in `BrowserConfig`
  - Allows connecting Chrome DevTools for debugging
- **Multi-Window Example**: Enhanced `examples/multi-window` demo
  - Beautiful glassmorphism UI design
  - Settings window with live preview
  - Real-time synchronization across multiple browser windows
  - CSS variable-based theming

### Changed

- **JS File Organization**: All example JS files are now symlinks to `js/` directory
  - Ensures consistency across all examples
  - Single source of truth for `vxui-ws.js` and `htmx.js`
- **WebSocket Close Code**: Fixed invalid close code (1006 → 1000) for stale connections

### Fixed

- **Broadcast CSS Updates**: CSS variables now update correctly when broadcasting to clients
  - CSS must be defined in initial HTML for htmx body swaps
  - Data attributes used to pass values for CSS variable updates

## [0.6.1] - 2026-02-24

### Changed

- **Unified Error Handling**:
  - All errors now use `VxuiErrorDetail` structured error type
  - Added `msg()` and `code()` methods for IError interface compliance
  - Added new error codes: `profile_create_failed`, `process_fork_failed`, `hidden_file_access`, `null_byte_detected`, `absolute_path_not_allowed`, `invalid_method`, `method_not_allowed`, `attribute_parse_error`

## [0.6.0] - 2026-02-24

### Security

- **Enhanced Path Validation**:
  - Added URL-encoded path traversal detection
  - Blocks double-encoded attacks (`%252e%252e%252f`)
  - Prevents null byte injection
  - Restricts hidden file access (except allowed extensions)
- **Enhanced JS Sandbox**:
  - Added 60+ forbidden patterns including constructor access, prototype pollution
  - Script size limit (64KB max)
  - Statement count limit (max 10 statements)
  - Blocks try-catch and template literals with interpolation
  - Detects obfuscation attempts

### Added

- **Comprehensive Test Suite**:
  - Enhanced path sanitization tests (URL encoding, null bytes, hidden files)
  - Error handling consistency tests
  - All error codes validation

### Changed

- **Breaking Changes**:
  - Removed deprecated `app.token` field - use `app.config.token`
  - Removed deprecated `app.multi_client` field - use `app.config.multi_client`

### Documentation

- Added migration guide in README
- Added security best practices section
- Added Mermaid architecture diagram

## [0.5.2] - 2026-02-24

### Changed

- **Modernized UI Examples**:
  - `examples/test`: Redesigned with dark theme, card-based layout, glassmorphism effects
  - `examples/enchart`: Enhanced dashboard with gradient backgrounds, stat cards, live status indicator
  - Window sizes adjusted for better display (test: 1000x700, enchart: 1200x800)

### Fixed

- Removed CSS animations (gradient, pulse) to reduce CPU usage
- Stat card text centering in enchart example
- Chart height adjusted to 80vh for better responsiveness

### Added

- **Element Plus Example**: Vue 3 + Element Plus integration demo
  - Demonstrates professional UI components (Button, Form, Table, Dialog, DatePicker, etc.)
  - Backend-driven notifications via `send_js_async()` for instant response
  - Shows vxui working with modern Vue 3 ecosystem
- **Gallery Example**: Comprehensive desktop UI controls demo
  - Buttons, forms, inputs, sliders, toggles
  - Progress bars, tabs, tables, cards
  - Modals, notifications
  - Dark mode toggle

### Fixed

- Added `hx-ext="vxui-ws"` to Element Plus example HTML body
- Added `rpcID` and `token` to WebSocket messages for backend routing
- Fixed `get_params()` to use `as_map()` method
- Added `hx-swap="none"` to buttons that don't need response body updates
- Added `hx-target` to prevent button text disappearing on swap
- Added `notranslate` meta tag to all examples to prevent Chrome translation popup
- Various htmx attribute fixes in gallery example

### Changed

- Optimized Element Plus notifications to use async JS execution
  - Created `send_js_async()` for fire-and-forget JS commands
  - Instant UI response instead of 2-3 second delay

## [0.5.0] - 2026-02-24

### Added

- **Hot Reload**: Automatic browser refresh on file changes
  - `DevConfig` struct for development mode settings
  - File watching with configurable `watch_ms` interval
  - `trigger_hot_reload()` method
  - Frontend `reload` command handling
- **Immediate Shutdown**: Detect browser window close
  - Frontend `beforeunload` event sends `client_close` notification
  - Backend tracks `had_clients` flag
  - Exit immediately when all clients disconnect (no timeout wait)
- **New Examples**:
  - `examples/todo-app`: Full CRUD example with beautiful UI
  - `examples/file-upload`: File upload/download with drag-drop support

### Fixed

- All examples updated to use `config.close_timer_ms`
- Fixed enchart example to use `vxui-ws.js` for proper authentication
- Fixed various mutability issues in examples and core
- Reduced `close_timer_ms` to 1000ms for faster startup timeout

## [0.4.1] - 2026-02-24

### Added

- **Error Chain Support**: Structured error handling with cause tracking
  - `VxuiErrorDetail.cause` field for underlying errors
  - `with_cause()` method to chain errors
  - `with_detail()` method to add context details
  - `full_message()` for complete error chain display
- **Safari Browser Support**: macOS Safari detection and launch
  - `BrowserType` enum for browser identification
  - `detect_browser_type()` function
  - `is_app_mode_supported()` helper
- **Connection Status UI**: Visual feedback for WebSocket state
  - Auto-show connecting/connected/disconnected/error states
  - Configurable position (top-right, top-left, bottom-right, bottom-left)
  - New `vxuiWs` APIs: `showStatus()`, `hideStatus()`, `getConnectionState()`

### Changed

- **API Unification**: Consolidated configuration in `Context.config`
  - Removed redundant fields: `window`, `browser`, `js_sandbox`, `js_poll_ms`, `close_timer_ms`
  - Added deprecation warnings for `token` and `multi_client` (backward compatible)
  - All setters now update `config` struct

### Fixed

- `validate_js_code()` now respects `sandbox.enabled` flag

### Tests

- Added route matching tests (multi-verb, case handling)
- Added security tests (HTML/JS/attr escape, email validation)
- Added JS sandbox tests
- Added request building tests
- Added config integration tests

## [0.4.0] - 2026-02-24

### Added

- **Middleware System**: Request/response processing pipeline
  - `Middleware` type and `MiddlewareContext` struct
  - `use()` method to add middleware
  - `use_logger()` built-in logging middleware
  - `use_auth()` authentication middleware helper
- **Event System**: Lifecycle hooks for app events
  - `EventType` enum: before_start, after_start, client_connecting, etc.
  - `on_event()` to register handlers
  - `EventData` struct with full context
- **Typed Errors**: Structured error handling
  - `VxuiError` enum with 20+ error codes
  - `VxuiErrorDetail` struct with code, message, details
  - Error-specific handling throughout codebase
- **Rate Limiting**: Request rate control
  - `RateLimitConfig` with max_requests, window_ms, block_duration
  - Per-client rate tracking with `RateCounter`
- **Request/Response Types**: Type-safe message handling
  - `Request` struct with verb, path, parameters, headers, body
  - `Response` struct with status, headers, body
- **Unified Configuration**: `Config` struct consolidating all settings
  - Application, connection, security, client, JS, request, window, browser, logging
  - `run_with_config()` for full configuration control
- **Backoff Strategies**: Reconnection delay algorithms
  - `BackoffStrategy` enum: constant, linear, exponential, full_jitter
  - Configurable via `ReconnectConfig`

### Changed

- Major codebase refactoring with improved architecture
- Better separation of concerns

## [0.3.0] - 2026-02-24

### Added

- **Packed App Support**: Embed frontend files into single executable
  - `PackedApp` struct for managing embedded files
  - `$embed_file` integration with V's compile-time embedding
  - `run_packed()` - Run app with packed resources
  - `run_embedded()` - Quick method for single HTML file
  - Automatic extraction to temp directory with cleanup
- **Config struct**: Centralized configuration options
  - `close_timer`, `ws_ping_interval`
  - `token`, `require_auth`
  - `multi_client`, `max_clients`
  - `js_timeout_default`, `js_poll_interval`
  - `window` settings integration
- **Comprehensive test coverage**: 50+ test cases
  - Tests for new structs (Client, WindowConfig, Config, PackedApp)
  - Tests for all public APIs
  - Error handling tests

### Fixed

- Channel leak in `run_js()` timeout handling - properly close channels
- Temp directory path validation in browser launcher

### Examples

- Added `examples/packed/` - Complete packed app example
  - Demonstrates `$embed_file` usage
  - Build single executable with `v -prod main.v`

## [0.2.0] - 2026-02-24

### Added

- **Token Authentication**: Auto-generated security token for client verification
- **run_js()**: Execute JavaScript from backend and receive results
  - `run_js(code, timeout)` - Execute on first client
  - `run_js_client(client_id, code, timeout)` - Execute on specific client
- **Multi-client Support**: 
  - `get_clients()` - Get list of connected client IDs
  - `get_client_count()` - Get number of connected clients
  - `close_client(client_id)` - Disconnect specific client
  - `broadcast(message)` - Send message to all clients
- **Window Management API**:
  - `set_window_size(width, height)` - Set window dimensions
  - `set_window_position(x, y)` - Set window position (-1 for center)
  - `set_window_title(title)` - Set window title
  - `set_resizable(bool)` - Enable/disable window resizing
- **Client struct**: Track connected browser clients with ID, token, connection time

### Changed

- **htmx.js**: Now uses official htmx 2.0.7 (no modifications required)
- **vxui-ws.js**: New extension using official htmx extension API
  - Token authentication support
  - Auto-reconnection with jitter
  - JavaScript execution from backend
  - Message queuing

### Removed

- `ajaxhook.js` - No longer needed (using htmx extension API)
- `vxui-htmx.js` - Replaced by `vxui-ws.js`
- `vxui-webui.js` - No longer used

### Documentation

- Translated AGENTS.md to English
- Updated README with new features and examples
- Regenerated API documentation (doc/vxui.md)

## [0.1.0] - 2026-02-23

### Added

- Modular architecture with separated concerns:
  - `browser.v`: Browser detection and launching
  - `router.v`: Routing logic
  - `utils.v`: Utility and security functions
- Cross-platform browser auto-detection (Chrome, Chromium, Edge, Firefox)
- Security features:
  - Input sanitization to prevent path traversal
  - HTML escaping functions (`escape_html`, `escape_js`, `escape_attr`)
  - Safe file path validation
- Comprehensive test suite with 22 test cases
- Error handling improvements (removed panic() calls)
- Better logging throughout the application
- Port allocation retry mechanism with max attempts

### Changed

- Refactored monolithic `vxui.v` into multiple focused modules
- Improved WebSocket connection handling
- Better error messages for debugging
- Updated examples with proper error handling

### Fixed

- Fixed rpcID generation in JavaScript to use timestamp + random
- Fixed path traversal vulnerability
- Fixed excessive panic() usage
- Fixed browser path hardcoding

### Security

- Added XSS protection with HTML escaping
- Added path traversal prevention
- Improved input validation

## [0.0.1] - 2024-XX-XX

### Added

- Initial release
- Basic WebSocket server
- Chrome browser integration
- htmx integration
- Simple routing system
- Basic examples

[Unreleased]: https://github.com/kbkpbot/vxui/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/kbkpbot/vxui/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/kbkpbot/vxui/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/kbkpbot/vxui/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/kbkpbot/vxui/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/kbkpbot/vxui/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/kbkpbot/vxui/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/kbkpbot/vxui/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/kbkpbot/vxui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kbkpbot/vxui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kbkpbot/vxui/releases/tag/v0.1.0
[0.0.1]: https://github.com/kbkpbot/vxui/releases/tag/v0.0.1
