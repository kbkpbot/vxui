module vxui

fn test_new_display_browser_returns_backend() {
	d := new_display(.browser, &BrowserConfig{}) or { panic(err.msg()) }
	match d {
		BrowserDisplay { assert true }
		else { assert false, 'expected BrowserDisplay' }
	}
}

fn test_new_display_webview_errors() {
	if disp := new_display(.webview, &BrowserConfig{}) {
		assert false, 'expected new_display(.webview) to error, got ${disp}'
	} else {
		assert true
	}
}

fn test_browser_display_build_launch_url() {
	b := BrowserDisplay{
		config: &BrowserConfig{}
	}
	url := b.build_launch_url('/tmp/index.html', 8080, 'secret')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080&vxui_token=secret'
}

fn test_browser_display_build_launch_url_no_token() {
	b := BrowserDisplay{
		config: &BrowserConfig{}
	}
	url := b.build_launch_url('/tmp/index.html', 8080, '')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080'
}
