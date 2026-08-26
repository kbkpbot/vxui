module vxui

fn test_new_display_browser_returns_backend() {
	d := new_display(.browser) or { panic(err.msg()) }
	match d {
		BrowserDisplay { assert true }
		else { assert false, 'expected BrowserDisplay' }
	}
}

fn test_new_display_webview_errors() {
	if disp := new_display(.webview) {
		assert false, 'expected new_display(.webview) to error, got ${disp}'
	} else {
		assert true
	}
}
