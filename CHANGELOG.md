# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/kbkpbot/vxui/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kbkpbot/vxui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kbkpbot/vxui/releases/tag/v0.1.0
[0.0.1]: https://github.com/kbkpbot/vxui/releases/tag/v0.0.1
