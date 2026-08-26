module vxui

import os
import rand

// DisplayFamily groups display backends by how they present the page.
pub enum DisplayFamily {
	process  // external child process (e.g. a system browser)
	embedded // in-process native view (e.g. WebView2 / WKWebView / WebKitGTK)
}

struct DisplayBackendInfo {
	id     string
	family DisplayFamily
}

// DisplayFactory builds a Display for a given app Config.
type DisplayFactory = fn (&Config) !Display

// DisplayRegistry holds the known backend ids, their families, and factories.
struct DisplayRegistry {
mut:
	backends   map[string]DisplayBackendInfo
	factories  map[string]DisplayFactory
	registered bool
}

fn (mut r DisplayRegistry) ensure() {
	if r.registered { return }
	r.backends['browser'] = DisplayBackendInfo{'browser', .process}
	r.backends['chrome'] = DisplayBackendInfo{'chrome', .process}
	r.backends['firefox'] = DisplayBackendInfo{'firefox', .process}
	r.backends['edge'] = DisplayBackendInfo{'edge', .process}
	r.backends['brave'] = DisplayBackendInfo{'brave', .process}
	r.backends['safari'] = DisplayBackendInfo{'safari', .process}
	r.backends['system'] = DisplayBackendInfo{'system', .process}
	r.backends['webview2'] = DisplayBackendInfo{'webview2', .embedded}
	r.backends['wkwebview'] = DisplayBackendInfo{'wkwebview', .embedded}
	r.backends['webkitgtk'] = DisplayBackendInfo{'webkitgtk', .embedded}
	r.backends['android'] = DisplayBackendInfo{'android', .embedded}
	r.factories['browser'] = fn (cfg &Config) !Display {
		return BrowserDisplay{
			config: &cfg.browser
		}
	}
	r.factories['chrome'] = r.factories['browser']
	r.factories['firefox'] = r.factories['browser']
	r.factories['edge'] = r.factories['browser']
	r.factories['brave'] = r.factories['browser']
	r.factories['safari'] = r.factories['browser']
	r.factories['system'] = r.factories['browser']
	r.factories['webview2'] = fn (cfg &Config) !Display {
		return WebViewDisplay{
			config: &cfg.webview
			id:     'webview2'
		}
	}
	r.factories['wkwebview'] = fn (cfg &Config) !Display {
		return WebViewDisplay{
			config: &cfg.webview
			id:     'wkwebview'
		}
	}
	r.factories['webkitgtk'] = fn (cfg &Config) !Display {
		return WebViewDisplay{
			config: &cfg.webview
			id:     'webkitgtk'
		}
	}
	r.factories['android'] = fn (cfg &Config) !Display {
		return WebViewDisplay{
			config: &cfg.webview
			id:     'android'
		}
	}
	r.registered = true
}

// DisplayConfig selects and scopes the display backend by string id.
// id 'auto' (or empty) resolves at runtime via resolve_auto().
pub struct DisplayConfig {
pub mut:
	id string = 'auto'
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
mut:
	close() !
	set_size(w int, h int)
	set_title(t string)
	set_position(x int, y int)
}

// Display is the pluggable backend that turns an HTML file into one or more
// presented windows. The core talks to the page exclusively via WebSocket; the
// Display only has to get the page on screen.
pub interface Display {
mut:
	spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}

// BrowserDisplay launches an external browser process.
pub struct BrowserDisplay {
	config &BrowserConfig
}

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
					'Failed to launch Safari', {
					'stderr': res.output.trim_space()
				})
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

// WebViewConfig holds in-process WebView/WebKit backend options. Empty today;
// filled when a real WebView backend lands. @[heap] so a reference can be taken.
@[heap]
pub struct WebViewConfig {}

// WebViewDisplay is a reserved in-process WebView/WebKit backend. Its spawn is
// not yet implemented; it exists to prove the wiring is backend-agnostic — a
// real backend only needs to implement spawn() (and fill WebViewConfig).
pub struct WebViewDisplay {
	config &WebViewConfig
	id     string
}

pub fn (mut b WebViewDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return error('native WebView FFI not implemented on this platform (${b.id})')
}

struct WebViewSession {}

pub fn (mut s WebViewSession) close() ! {}

pub fn (mut s WebViewSession) set_size(w int, h int) {}

pub fn (mut s WebViewSession) set_title(t string) {}

pub fn (mut s WebViewSession) set_position(x int, y int) {}

// new_display constructs the backend identified by `id`. An empty id or 'auto'
// resolves at runtime via resolve_auto(). It receives the whole app Config so
// each backend extracts its OWN sub-config — this keeps the construction wiring
// backend-agnostic (no hardcoded BrowserConfig).
pub fn new_display(id string, app_cfg &Config) !Display {
	mut r := DisplayRegistry{}
	r.ensure()
	resolved := if id == '' || id == 'auto' { resolve_auto(app_cfg) } else { id }
	f := r.factories[resolved] or { return error('unknown display backend: ${resolved}') }
	return f(app_cfg)
}

// resolve_auto picks the first available process-family browser backend.
// Linux-first; extend per platform. Falls back to 'system'.
pub fn resolve_auto(cfg &Config) string {
	for candidate in ['chrome', 'google-chrome', 'chromium', 'firefox', 'edge', 'brave', 'system'] {
		if candidate == 'system' { return 'system' }
		path := os.find_abs_path_of_executable(candidate) or { '' }
		if path != '' { return candidate }
	}
	return 'system'
}

// backend_family returns the family a backend id belongs to (defaults to .process).
pub fn backend_family(id string) DisplayFamily {
	mut r := DisplayRegistry{}
	r.ensure()
	info := r.backends[id] or { return .process }
	return info.family
}

// =============================================================================
// Browser-launch helpers (moved verbatim from browser.v in Task 2)
// =============================================================================

// ScreenSize holds screen dimensions
struct ScreenSize {
	width  int
	height int
}

// BrowserType represents different browser types
pub enum BrowserType {
	chrome
	firefox
	safari
	edge
	brave
	chromium
	unknown
}

// get_screen_size returns the primary screen resolution
fn get_screen_size() ScreenSize {
	// Default fallback
	default_size := ScreenSize{1920, 1080}

	$if linux {
		// Try xrandr first
		if os.exists('/usr/bin/xrandr') {
			result := os.execute('xrandr --query 2>/dev/null | grep " connected" | head -1')
			if result.exit_code == 0 {
				// Parse: "eDP-1 connected primary 1920x1080+0+0"
				parts := result.output.split(' ')
				for part in parts {
					if part.contains('x') && part.contains('+') {
						// Format: 1920x1080+0+0
						dim_part := part.all_before('+')
						dims := dim_part.split('x')
						if dims.len == 2 {
							w := dims[0].int()
							h := dims[1].int()
							if w > 0 && h > 0 {
								return ScreenSize{w, h}
							}
						}
					}
				}
			}
		}
		// Try xdpyinfo as fallback
		if os.exists('/usr/bin/xdpyinfo') {
			result := os.execute('xdpyinfo 2>/dev/null | grep dimensions')
			if result.exit_code == 0 {
				// Parse: "  dimensions:    1920x1080 pixels (507x285 millimeters)"
				parts := result.output.split('x')
				if parts.len >= 2 {
					w_str := parts[0].trim_space().split(' ').last()
					h_str := parts[1].all_before(' ').trim_space()
					w := w_str.int()
					h := h_str.int()
					if w > 0 && h > 0 {
						return ScreenSize{w, h}
					}
				}
			}
		}
	} $else $if macos {
		// macOS: use system_profiler or defaults
		result := os.execute('system_profiler SPDisplaysDataType 2>/dev/null | grep Resolution')
		if result.exit_code == 0 {
			// Parse: "    Resolution: 1920 x 1080"
			parts := result.output.split('x')
			if parts.len >= 2 {
				w_str := parts[0].trim_space().split(' ').last()
				h_str := parts[1].trim_space()
				w := w_str.int()
				h := h_str.int()
				if w > 0 && h > 0 {
					return ScreenSize{w, h}
				}
			}
		}
	} $else $if windows {
		// Windows: use wmic
		result := os.execute('wmic desktopmonitor get screenheight,screenwidth 2>nul')
		if result.exit_code == 0 {
			lines := result.output.split('\n')
			for line in lines {
				if line.trim_space().len > 0 && !line.contains('ScreenHeight') {
					parts := line.split(' ').filter(it.len > 0)
					if parts.len >= 2 {
						w := parts[0].int()
						h := parts[1].int()
						if w > 0 && h > 0 {
							return ScreenSize{w, h}
						}
					}
				}
			}
		}
	}

	return default_size
}

// calculate_center_position calculates window position to center on screen
fn calculate_center_position(window_width int, window_height int) (int, int) {
	screen := get_screen_size()
	x := (screen.width - window_width) / 2
	y := (screen.height - window_height) / 2
	// Ensure positive values
	return if x > 0 { x } else { 100 }, if y > 0 {
		y
	} else {
		100
	}
}

// get_browser_args returns browser-specific arguments
fn get_browser_args(browser_name string) []string {
	base_args := [
		'--no-first-run',
		'--disable-breakpad',
		'--disable-client-side-phishing-detection',
		'--disable-default-apps',
		'--disable-dev-shm-usage',
		'--disable-infobars',
		'--disable-features=site-per-process,Translate,TranslateUI,TranslateMessageUI',
		'--disable-hang-monitor',
		'--disable-ipc-flooding-protection',
		'--disable-popup-blocking',
		'--disable-prompt-on-repost',
		'--disable-renderer-backgrounding',
		'--metrics-recording-only',
		'--no-default-browser-check',
		'--safebrowsing-disable-auto-update',
		'--password-store=basic',
		'--use-mock-keychain',
		'--disable-gpu',
		'--disable-software-rasterizer',
		'--no-proxy-server',
		'--safe-mode',
		'--disable-extensions',
		'--disable-background-mode',
		'--disable-plugins',
		'--disable-plugins-discovery',
		'--bwsi',
		'--disable-sync',
		'--disable-sync-preferences',
		// Disable hardware acceleration to avoid VA-API errors on Linux
		'--disable-accelerated-video-decode',
		'--disable-accelerated-video-encode',
		'--disable-gpu-compositing',
		'--disable-vaapi',
	]

	// Firefox doesn't support --app-mode, so use different args
	if browser_name.to_lower().contains('firefox') {
		return [
			'--new-instance',
			'--no-remote',
		]
	}

	return base_args
}

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

// find_browser_path finds browser path based on current platform.
// `preferred` (BrowserConfig.preferred_path) wins when it exists on disk;
// otherwise platform-specific candidates are probed in order.
fn find_browser_path_with_preferred(preferred string) string {
	if preferred != '' && os.exists(preferred) {
		return preferred
	}
	$if linux {
		return find_browser_path_linux()
	} $else $if macos {
		return find_browser_path_macos()
	} $else $if windows {
		return find_browser_path_windows()
	}
	return ''
}

// find_browser_path_linux finds browser on Linux
fn find_browser_path_linux() string {
	paths := [
		'/usr/bin/google-chrome-stable',
		'/usr/bin/google-chrome',
		'/usr/bin/chromium',
		'/usr/bin/chromium-browser',
		'/usr/bin/microsoft-edge',
		'/usr/bin/brave',
		'/usr/bin/firefox',
	]
	for path in paths {
		if os.exists(path) {
			return path
		}
	}
	return ''
}

// find_browser_path_macos finds browser on macOS
fn find_browser_path_macos() string {
	paths := [
		'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
		'/Applications/Chromium.app/Contents/MacOS/Chromium',
		'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
		'/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
		'/Applications/Safari.app/Contents/MacOS/Safari',
		'/Applications/Firefox.app/Contents/MacOS/Firefox',
	]
	for path in paths {
		if os.exists(path) {
			return path
		}
	}
	return ''
}

// find_browser_path_windows finds browser on Windows
fn find_browser_path_windows() string {
	paths := [
		'C:/Program Files/Google/Chrome/Application/chrome.exe',
		'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
		'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
		'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
		'C:/Program Files/Mozilla Firefox/firefox.exe',
		'C:/Program Files (x86)/Mozilla Firefox/firefox.exe',
	]
	for path in paths {
		if os.exists(path) {
			return path
		}
	}
	return ''
}

// detect_browser_type determines the browser type from path
pub fn detect_browser_type(browser_path string) BrowserType {
	name := os.base(browser_path).to_lower()
	if name.contains('safari') {
		return .safari
	}
	if name.contains('firefox') {
		return .firefox
	}
	if name.contains('edge') || name.contains('msedge') {
		return .edge
	}
	if name.contains('brave') {
		return .brave
	}
	if name.contains('chromium') {
		return .chromium
	}
	if name.contains('chrome') {
		return .chrome
	}
	return .unknown
}

// is_app_mode_supported returns true if browser supports app mode
pub fn is_app_mode_supported(browser_type BrowserType) bool {
	return browser_type in [.chrome, .edge, .brave, .chromium]
}
