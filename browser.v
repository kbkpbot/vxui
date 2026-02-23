module vxui

import os

// BrowserConfig holds browser path and arguments
pub struct BrowserConfig {
	path string
	args []string
}

// detect_browser detects available browser on the system
pub fn detect_browser() !BrowserConfig {
	// Platform-specific browser detection
	$if linux {
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
				return BrowserConfig{
					path: path
					args: get_browser_args(os.base(path))
				}
			}
		}
	} $else $if macos {
		paths := [
			'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
			'/Applications/Chromium.app/Contents/MacOS/Chromium',
			'/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
			'/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
			'/Applications/Firefox.app/Contents/MacOS/Firefox',
		]
		for path in paths {
			if os.exists(path) {
				return BrowserConfig{
					path: path
					args: get_browser_args(os.base(path))
				}
			}
		}
	} $else $if windows {
		// Windows common paths
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
				return BrowserConfig{
					path: path
					args: get_browser_args(os.base(path))
				}
			}
		}
	}
	return error('No supported browser found. Please install Chrome, Chromium, Edge, or Firefox.')
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
	// Sanitize the filename
	safe_filename := sanitize_path(filename)!
	abs_path := os.abs_path(safe_filename)

	// Ensure the file exists
	if !os.exists(abs_path) {
		return error('HTML file not found: ${abs_path}')
	}

	// Detect browser
	browser := detect_browser()!

	// Create profile directory
	profile_path := os.join_path(os.home_dir(), '.vxui', 'browser_profile')
	os.mkdir_all(profile_path) or { return error('Failed to create profile directory: ${err}') }

	// Build command arguments
	mut cmd_args := browser.args.clone()
	cmd_args << '--user-data-dir=${profile_path}'

	// Add app-mode argument for Chrome/Chromium/Edge
	is_firefox := browser.path.to_lower().contains('firefox')
	if !is_firefox {
		cmd_args << '--force-app-mode'
		cmd_args << '--new-window'
		cmd_args << '--app=file://${abs_path}?vxui_ws_port=${vxui_ws_port}'
	} else {
		// Firefox uses different approach
		cmd_args << 'file://${abs_path}?vxui_ws_port=${vxui_ws_port}'
	}

	// Start browser process
	$if windows {
		// On Windows, use spawn to avoid blocking
		os.execute('start "" "${browser.path}" ' + cmd_args.join(' '))
	} $else {
		pid := os.fork()
		if pid == 0 {
			// Child process
			os.execvp(browser.path, cmd_args) or {
				eprintln('Failed to start browser: ${err}')
				exit(1)
			}
		} else if pid < 0 {
			return error('Failed to fork process')
		}
	}

	return
}
