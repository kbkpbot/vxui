module vxui

import os

// BrowserConfig is defined in vxui.v, this file contains browser-related functions

// ScreenSize holds screen dimensions
struct ScreenSize {
	width  int
	height int
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
	return if x > 0 { x } else { 100 }, if y > 0 { y } else { 100 }
}

// get_browser_args returns browser-specific arguments
fn get_browser_args(browser_name string, config BrowserConfig) []string {
	base_args := [
		'--no-first-run',
		'--disable-breakpad',
		'--disable-client-side-phishing-detection',
		'--disable-default-apps',
		'--disable-dev-shm-usage',
		'--disable-infobars',
		'--disable-features=site-per-process',
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
		'--disable-translate',
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

// start_browser starts the browser and open the `filename`
pub fn start_browser(filename string, vxui_ws_port u16) ! {
	start_browser_with_config(filename, vxui_ws_port, '', WindowConfig{}, BrowserConfig{})!
}

// start_browser_with_token starts the browser with security token and window config
pub fn start_browser_with_token(filename string, vxui_ws_port u16, token string, window WindowConfig) ! {
	start_browser_with_config(filename, vxui_ws_port, token, window, BrowserConfig{})!
}

// start_browser_with_config starts the browser with full configuration
pub fn start_browser_with_config(filename string, vxui_ws_port u16, token string, window WindowConfig, browser_config BrowserConfig) ! {
	// Check if it's an absolute path to temp directory (for packed apps)
	mut abs_path := os.abs_path(filename)
	is_temp := abs_path.starts_with(os.temp_dir())

	// Sanitize the filename (skip for temp directory)
	if !is_temp {
		safe_filename := sanitize_path(filename)!
		abs_path = os.abs_path(safe_filename)
	}

	// Ensure the file exists
	if !os.exists(abs_path) {
		return error('HTML file not found: ${abs_path}')
	}

	// Detect browser path based on platform
	browser_path := find_browser_path()

	if browser_path == '' {
		return error('No supported browser found')
	}

	// Build URL with parameters
	mut url_params := 'vxui_ws_port=${vxui_ws_port}'
	if token != '' {
		url_params += '&vxui_token=${token}'
	}
	if window.width > 0 {
		url_params += '&vxui_width=${window.width}'
	}
	if window.height > 0 {
		url_params += '&vxui_height=${window.height}'
	}

	// Detect browser type
	browser_type := detect_browser_type(browser_path)
	browser_name := os.base(browser_path)
	is_safari := browser_type == .safari
	is_chrome_based := is_app_mode_supported(browser_type)

	// Safari requires special handling on macOS
	if is_safari {
		$if macos {
			// Safari doesn't support command-line arguments, use 'open' command
			url := 'file://${abs_path}?${url_params}'
			os.execute('open -a Safari "${url}"')
			return
		}
		return error('Safari is only supported on macOS')
	}

	// Create profile directory for non-Safari browsers
	profile_path := if browser_config.user_data_dir != '' {
		browser_config.user_data_dir
	} else if browser_config.profile_dir != '' {
		browser_config.profile_dir
	} else {
		os.join_path(os.home_dir(), '.vxui', 'browser_profile')
	}
	os.mkdir_all(profile_path) or { return error('Failed to create profile directory: ${err}') }

	// Build command arguments
	mut cmd_args := get_browser_args(browser_name, browser_config)

	// Add custom arguments first
	if browser_config.custom_args.len > 0 {
		cmd_args << browser_config.custom_args
	}

	cmd_args << '--user-data-dir=${profile_path}'

	// Add window size for Chrome-based browsers
	if is_chrome_based {
		win_width := if window.width > 0 { window.width } else { 800 }
		win_height := if window.height > 0 { window.height } else { 600 }

		if window.width > 0 && window.height > 0 {
			cmd_args << '--window-size=${window.width},${window.height}'
		}

		// Handle window position: -1 means center
		mut pos_x := window.x
		mut pos_y := window.y
		if window.x < 0 || window.y < 0 {
			pos_x, pos_y = calculate_center_position(win_width, win_height)
		}
		cmd_args << '--window-position=${pos_x},${pos_y}'

		// Headless mode for testing
		if browser_config.headless {
			cmd_args << '--headless=new'
		}

		// DevTools
		if browser_config.devtools {
			cmd_args << '--auto-open-devtools-for-tabs'
		}

		// No sandbox (for root/CI environments)
		if browser_config.no_sandbox {
			cmd_args << '--no-sandbox'
			cmd_args << '--disable-setuid-sandbox'
		}

		cmd_args << '--force-app-mode'
		cmd_args << '--new-window'
		cmd_args << '--app=file://${abs_path}?${url_params}'
	} else {
		// Firefox uses different approach
		if window.width > 0 && window.height > 0 {
			cmd_args << '--width=${window.width}'
			cmd_args << '--height=${window.height}'
		}
		cmd_args << 'file://${abs_path}?${url_params}'
	}

	// Start browser process
	$if windows {
		// On Windows, use spawn to avoid blocking
		os.execute('start "" "${browser_path}" ' + cmd_args.join(' '))
	} $else {
		pid := os.fork()
		if pid == 0 {
			// Child process
			os.execvp(browser_path, cmd_args) or {
				eprintln('Failed to start browser: ${err}')
				exit(1)
			}
		} else if pid < 0 {
			return error('Failed to fork process')
		}
	}

	return
}

// find_browser_path finds browser path based on current platform
fn find_browser_path() string {
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
