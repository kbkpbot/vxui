# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/kbkpbot/vxui/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/kbkpbot/vxui/releases/tag/v0.0.1
