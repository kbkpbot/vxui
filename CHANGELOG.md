# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/kbkpbot/vxui/compare/v0.6.0...HEAD
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
