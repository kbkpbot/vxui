module vxui

fn test_new_display_browser_returns_backend() {
	d := new_display('browser', &Config{
		browser: BrowserConfig{}
	}) or { panic(err.msg()) }
	match d {
		ProcessDisplay { assert true }
		else { assert false, 'expected ProcessDisplay' }
	}
}

fn test_new_display_webview_constructs() {
	d := new_display('webview2', &Config{}) or { panic(err.msg()) }
	match d {
		WebViewDisplay { assert true }
		else { assert false, 'expected WebViewDisplay' }
	}
}

fn test_launch_url_with_token() {
	url := launch_url('/tmp/index.html', 8080, 'secret')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080&vxui_token=secret'
}

fn test_launch_url_no_token() {
	url := launch_url('/tmp/index.html', 8080, '')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080'
}

fn test_resolve_backend_id_passthrough_and_auto() {
	// Explicit id passes through untouched.
	cfg := Config{
		display: DisplayConfig{ id: 'webkitgtk' }
	}
	assert resolve_backend_id(&cfg, '') == 'webkitgtk'
	assert resolve_backend_id(&cfg, 'chrome') == 'chrome'
	// Empty/'auto' prefers this platform's native WebView when the build has
	// one (Linux: webkitgtk); otherwise it falls back to a browser backend.
	mut auto_cfg := Config{}
	resolved := resolve_backend_id(&auto_cfg, '')
	native := embedded_native_id()
	if native != '' {
		assert resolved == native
		assert backend_family(resolved) == .embedded
	} else {
		assert resolved != '' && resolved != 'auto'
		assert backend_family(resolved) == .process
	}
}

fn test_embedded_spawn_unsupported_id_errors() {
	// An embedded id this platform does not implement must error clearly,
	// never attempt to open a window.
	cfg := DisplaySessionConfig{}
	embedded_spawn('definitely-not-a-backend', '/nonexistent.html', cfg) or { return }
	assert false, 'expected embedded_spawn to fail for an unsupported id'
}
