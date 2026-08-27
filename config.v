module vxui

import log

// =============================================================================
// Configuration Structures
// =============================================================================

// JsSandboxConfig controls JavaScript execution security
pub struct JsSandboxConfig {
pub mut:
	enabled            bool = true        // Enable sandbox restrictions
	timeout_ms         int  = 5000        // Max execution time
	max_result_size    int  = 1024 * 1024 // Max result size in bytes (1MB)
	allow_eval         bool // Allow eval() in frontend (dangerous!)
	forbidden_patterns []string = [// Forbidden patterns
		'eval(',
		'Function(',
		'setTimeout(',
		'setInterval(',
		'XMLHttpRequest',
		'fetch(',
		'WebSocket',
		'import(',
	]
}

// WindowConfig holds window configuration.
// NOTE: only size/position/title are actually enforced by the browser launch;
// the previous resizable/min-size/frameless fields never had any effect and
// were removed (see CHANGELOG).
pub struct WindowConfig {
pub mut:
	width  int = 800
	height int = 600
	x      int = -1 // -1 means center
	y      int = -1 // -1 means center
	title  string // window/page title; falls back to config.app_name when set
}

// WindowMode selects how the page window is presented. Only meaningful for
// Chromium-family browsers; Firefox/Safari open a normal tab regardless.
pub enum WindowMode {
	app    // standalone window WITHOUT address bar/tab strip (default)
	kiosk  // borderless fullscreen
	normal // an ordinary browser tab
}

// BrowserEngine selects which browser executable + launch flags the process
// family uses. `.auto` (the default) probes the system and resolves to the
// first usable engine at spawn time.
pub enum BrowserEngine {
	auto   // probe system (default)
	chrome // Chromium-family (google-chrome / chromium)
	firefox
	edge   // Chromium-family (microsoft-edge)
	brave  // Chromium-family (brave)
	safari // macOS Safari
	system // platform default launcher
}

// BrowserConfig holds browser startup configuration
@[heap]
pub struct BrowserConfig {
pub mut:
	custom_args       []string // Additional custom arguments
	profile_dir       string   // Custom profile directory (empty = default)
	headless          bool     // Run in headless mode (for testing)
	devtools          bool     // Open DevTools automatically
	no_sandbox        bool     // Disable sandbox (for root/CI)
	window_mode       WindowMode = .app // presentation of the app window (see WindowMode)
	user_data_dir     string // Custom user data directory
	preferred_path    string // Preferred browser path (skip detection)
	remote_debug_port int    // Chrome remote debugging port (0 = disabled)
	engine            BrowserEngine = .auto // Which engine/executable to launch
}

// LogConfig holds logging settings.
// `output` accepts 'stderr' (default), 'stdout', or a file path.
// The previous max_file_size/rotate_files/show_* fields never had any
// effect and were removed (see CHANGELOG).
pub struct LogConfig {
pub mut:
	level  log.Level = .info
	output string    = 'stderr'
}

// Config is the unified configuration for vxui
pub struct Config {
pub mut:
	// Application settings
	app_name string = default_app_name

	// Development settings
	dev DevConfig // Development mode settings

	// Connection settings
	close_timer_ms      int = 5000  // Close app after N ms with no browser
	ws_ping_interval_ms int = 30000 // WebSocket ping interval
	ws_pong_timeout_ms  int = 60000 // Timeout for pong response

	// Security settings
	token        string // Security token (auto-generated if empty)
	require_auth bool = true // Require token authentication
	allow_remote bool // Accept connections from non-loopback interfaces (default false)

	// Client settings
	multi_client bool // Allow multiple browser clients
	// When multi_client is off, let a NEW successful authentication evict
	// stale sessions instead of letting a restored/crashed browser tab hold
	// the single slot forever. Defaults to true: without it, a simple F5
	// reload races the async client cleanup and the fresh connection gets
	// rejected — the app appears dead after a refresh.
	evict_on_new bool = true
	max_clients  int  = 10 // Maximum concurrent clients (0 = unlimited)

	// JavaScript execution settings
	js_timeout int = 5000 // Default timeout for run_js()
	js_poll_ms int = 10   // Polling interval for JS result
	js_sandbox JsSandboxConfig // JS execution sandbox

	// Window settings
	window WindowConfig

	// Browser settings
	browser BrowserConfig

	// WebView settings: native WebView/WebKit host backends (WebKitGTK on Linux,
	// WKWebView on macOS, WebView2 on Windows). Each is hosted in an independent
	// lightweight child process via the --vxui-host control-pipe protocol; the
	// `android` id is still a reserved placeholder.
	webview WebViewConfig // reserved placeholder; not yet applied by host backends (see WebViewConfig)

	// Display backend selection
	display DisplayConfig

	// Logging settings
	log LogConfig
}

// DevConfig holds development mode settings
pub struct DevConfig {
pub mut:
	enabled       bool // Enable development mode
	hot_reload    bool = true // Enable hot reload (refresh browser on file change)
	watch_dirs    []string // Directories to watch for changes (default: html file dir)
	watch_ms      int  = 500  // File watch interval in milliseconds
	auto_devtools bool = true // Auto-open DevTools in dev mode
	show_errors   bool = true // Show error overlay in browser
}
