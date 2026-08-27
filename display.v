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
		return ProcessDisplay{
			engine: .auto
			config: &cfg.browser
		}
	}
	r.factories['chrome'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .chrome
			config: &cfg.browser
		}
	}
	r.factories['firefox'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .firefox
			config: &cfg.browser
		}
	}
	r.factories['edge'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .edge
			config: &cfg.browser
		}
	}
	r.factories['brave'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .brave
			config: &cfg.browser
		}
	}
	r.factories['safari'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .safari
			config: &cfg.browser
		}
	}
	r.factories['system'] = fn (cfg &Config) !Display {
		return ProcessDisplay{
			engine: .system
			config: &cfg.browser
		}
	}
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
	// wait_closed blocks until the window is gone. Backends that hand the
	// caller's thread to a native toolkit loop (GTK/WebView2) park inside it;
	// detached backends (external browser) return immediately.
	wait_closed() !
	// is_closed reports whether the window has already been destroyed (e.g. the
	// user closed it). The service worker uses it to break its loop promptly.
	is_closed() bool
}

// Display is the pluggable backend that turns an HTML file into one or more
// presented windows. The core talks to the page exclusively via WebSocket; the
// Display only has to get the page on screen.
pub interface Display {
mut:
	spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}

// ProcessDisplay launches an external browser process. It is parameterized by
// a BrowserEngine so each id selects the right executable + flags; the
// Chromium-family and Firefox/Safari behaviors are chosen per engine at spawn.
pub struct ProcessDisplay {
	engine BrowserEngine
	config &BrowserConfig
}

// launch_url builds the file:// URL the frontend loads, carrying the WebSocket
// port + auth token as query params. Shared by the process (browser) and
// embedded (WebView) backends so both present the page identically.
fn launch_url(abs_path string, port u16, token string) string {
	mut params := 'vxui_ws_port=${port}'
	if token != '' {
		params += '&vxui_token=${token}'
	}
	return 'file://${abs_path}?${params}'
}

// is_chromium_engine reports whether the engine uses Chromium-style flags
// (--app, --window-size, --user-data-dir, ...).
fn is_chromium_engine(e BrowserEngine) bool {
	return e in [.chrome, .edge, .brave]
}

// engine_from_path maps a browser executable path to the engine its flags need.
fn engine_from_path(path string) BrowserEngine {
	t := detect_browser_type(path)
	return match t {
		.firefox { .firefox }
		.safari { .safari }
		.edge { .edge }
		.brave { .brave }
		else { .chrome } // chromium / chromium-browser / unknown -> chromium flags
	}
}

// browser_executable_names returns candidate executable names for an engine.
fn browser_executable_names(engine BrowserEngine) []string {
	return match engine {
		.chrome { ['google-chrome-stable', 'google-chrome', 'chromium', 'chromium-browser'] }
		.edge { ['microsoft-edge', 'msedge', 'edge'] }
		.brave { ['brave', 'brave-browser'] }
		.firefox { ['firefox'] }
		.safari { ['safari'] }
		.system { ['x-www-browser', 'google-chrome', 'chromium', 'firefox'] }
		.auto { ['google-chrome', 'chromium', 'firefox'] }
	}
}

// find_engine_path locates an executable for the given engine, honoring a
// preferred path first.
fn find_engine_path(engine BrowserEngine, preferred string) string {
	if preferred != '' && os.exists(preferred) {
		return preferred
	}
	for name in browser_executable_names(engine) {
		p := os.find_abs_path_of_executable(name) or { '' }
		if p != '' { return p }
	}
	return ''
}

// get_firefox_args builds the Firefox-specific launch argument list. Firefox
// does not understand Chromium switches (--app=, --window-size=), so it gets
// its own flags.
fn get_firefox_args(profile_path string, width int, height int, kiosk bool, url string) []string {
	mut args := ['-new-instance', '-profile', profile_path]
	if width > 0 && height > 0 {
		args << '-width'
		args << '${width}'
		args << '-height'
		args << '${height}'
	}
	if kiosk {
		args << '-kiosk'
	}
	args << url
	return args
}

pub fn (mut b ProcessDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
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
	mut eff_engine := b.engine
	mut browser_path := ''
	if eff_engine == .auto || eff_engine == .system {
		browser_path = find_browser_path_with_preferred(b.config.preferred_path)
		if browser_path == '' {
			return new_error_detail(VxuiError.browser_not_found, 'No supported browser found')
		}
		eff_engine = engine_from_path(browser_path)
	} else {
		browser_path = find_engine_path(eff_engine, b.config.preferred_path)
		if browser_path == '' {
			browser_path = find_browser_path_with_preferred(b.config.preferred_path)
		}
		if browser_path == '' {
			return new_error_detail(VxuiError.browser_not_found,
				'No supported browser for engine ${eff_engine}')
		}
		if eff_engine == .auto || eff_engine == .system {
			eff_engine = engine_from_path(browser_path)
		}
	}
	url := launch_url(abs_path, cfg.port, cfg.token)
	browser_name := os.base(browser_path)
	if eff_engine == .safari {
		$if macos {
			res := os.execute('open -a Safari "${url}"')
			if res.exit_code != 0 {
				return new_error_detail_with_details(VxuiError.browser_not_found,
					'Failed to launch Safari', {
					'stderr': res.output.trim_space()
				})
			}
			return ProcessSession{}
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
	if is_chromium_engine(eff_engine) {
		mut cmd_args := get_browser_args(browser_name)
		if b.config.custom_args.len > 0 {
			cmd_args << b.config.custom_args
		}
		cmd_args << '--user-data-dir=${profile_path}'
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
	} else {
		// Firefox (and any non-Chromium engine)
		mut cmd_args := b.config.custom_args.clone()
		cmd_args << get_firefox_args(profile_path, cfg.width, cfg.height,
			b.config.window_mode == .kiosk, url)
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
	}
	return ProcessSession{}
}

struct ProcessSession {}

pub fn (mut s ProcessSession) close() ! {}

pub fn (mut s ProcessSession) set_size(w int, h int) {}

pub fn (mut s ProcessSession) set_title(t string) {}

pub fn (mut s ProcessSession) set_position(x int, y int) {}

// wait_closed returns immediately: an external browser is a detached process,
// there is no in-process window to await.
pub fn (mut s ProcessSession) wait_closed() ! {}

// is_closed is always false: an external browser is a detached process we do
// not track from inside this process.
pub fn (mut s ProcessSession) is_closed() bool {
	return false
}

// WebViewConfig holds in-process WebView/WebKit backend options. @[heap] so a
// reference can be taken.
@[heap]
pub struct WebViewConfig {}

// WebViewDisplay is the in-process WebView/WebKit backend. The platform FFI
// lives in per-platform files picked by V's platform-dependent file mechanism
// (display_windows.v / display_linux.v / display_default.v); this shared code
// only dispatches to their hook contract.
pub struct WebViewDisplay {
	config &WebViewConfig
	id     string
}

pub fn (mut b WebViewDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return embedded_spawn(b.id, html_path, cfg)
}

struct WebViewSession {
mut:
	window     voidptr // GtkWidget* (linux) / HWND (windows)
	view       voidptr // WebKitWebView* (linux) / ICoreWebView2* (windows)
	controller voidptr // WebKitWebView* unused / ICoreWebView2Controller* (windows)
	quit       voidptr // raw malloc'd bool shared with GTK callbacks (NOT V-managed)
}

pub fn (mut s WebViewSession) close() ! {
	embedded_session_close(&s)
}

pub fn (mut s WebViewSession) set_size(w int, h int) {
	embedded_session_set_size(&s, w, h)
}

pub fn (mut s WebViewSession) set_title(t string) {
	embedded_session_set_title(&s, t)
}

pub fn (mut s WebViewSession) set_position(x int, y int) {
	embedded_session_set_position(&s, x, y)
}

// wait_closed parks the caller until the window is gone. On platforms whose
// toolkit must own the main thread this blocks inside the native loop; the
// per-platform body lives in display_<os>.v (embedded_session_wait_closed).
pub fn (mut s WebViewSession) wait_closed() ! {
	embedded_session_wait_closed(mut &s)
}

// is_closed reports whether the native window has been destroyed. The service
// worker polls this to break its loop as soon as the user closes the window.
pub fn (mut s WebViewSession) is_closed() bool {
	return s.window == unsafe { nil }
}

// NullDisplay is the default, no-op display backend. It satisfies the `Display`
// interface so `Context{}` / `App{}` can be constructed without an uninitialized
// interface field; run() replaces it with a real backend via new_display().
struct NullDisplay {}

pub fn (mut d NullDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return error('no display backend configured; call vxui.run with a valid config.display.id')
}

// resolve_backend_id returns the concrete backend id that will be used:
// an empty/'auto' override_id (or the cfg's own 'auto'/empty id) is resolved
// via resolve_auto(); anything else is passed through. Single resolution
// point shared by new_display() and frontend logging.
pub fn resolve_backend_id(cfg &Config, override_id string) string {
	id := if override_id != '' { override_id } else { cfg.display.id }
	if id == '' || id == 'auto' {
		return resolve_auto(cfg)
	}
	return id
}

// new_display constructs the backend identified by `id`. An empty id or 'auto'
// resolves at runtime via resolve_auto(). It receives the whole app Config so
// each backend extracts its OWN sub-config — this keeps the construction wiring
// backend-agnostic (no hardcoded BrowserConfig).
pub fn new_display(id string, app_cfg &Config) !Display {
	mut r := DisplayRegistry{}
	r.ensure()
	resolved := resolve_backend_id(app_cfg, id)
	f := r.factories[resolved] or { return error('unknown display backend: ${resolved}') }
	return f(app_cfg)
}

// resolve_auto picks the backend used for display.id 'auto'/empty.
// It PREFERS this platform's native embedded WebView when the build carries one
// (embedded_native_id() from the per-platform display_<os>.v file), because a
// native window needs no external browser install. Otherwise it falls back to
// probing for browser executables, mapping each found NAME to its registered
// backend id (e.g. `google-chrome` / `chromium` both resolve to `chrome`), so
// the id handed to new_display is always one the registry knows.
pub fn resolve_auto(cfg &Config) string {
	// 1. Native WebView first (webkitgtk on Linux, webview2 on Windows, ...).
	native_id := embedded_native_id()
	if native_id != '' {
		return native_id
	}
	// 2. Browser fallback: (executable name -> backend id) pairs, Linux-first.
	candidates := [
		['chrome', 'chrome'],
		['google-chrome', 'chrome'],
		['google-chrome-stable', 'chrome'],
		['chromium', 'chrome'],
		['chromium-browser', 'chrome'],
		['firefox', 'firefox'],
		['edge', 'edge'],
		['microsoft-edge', 'edge'],
		['msedge', 'edge'],
		['brave', 'brave'],
		['brave-browser', 'brave'],
		['safari', 'safari'],
	]
	for pair in candidates {
		path := os.find_abs_path_of_executable(pair[0]) or { '' }
		if path != '' { return pair[1] }
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
