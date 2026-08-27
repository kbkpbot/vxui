module vxui

// =============================================================================
// Display / Window Launch Tests (display-adjacent, moved from vxui_test.v)
// =============================================================================

fn test_window_mode_args_use_equals_form_for_app_mode() {
	url := 'file:///x/index.html?vxui_ws_port=1234&vxui_token=abc'
	assert window_mode_args(.app, url) == ['--app=${url}']
	assert window_mode_args(.kiosk, url) == ['--kiosk', url]
	assert window_mode_args(.normal, url) == [url]
	app_arg := window_mode_args(.app, url)[0]
	assert app_arg.starts_with('--app='), 'Chromium ignores space-form value switches'
	assert !app_arg.contains(' '), 'URL and flag must be ONE argument'
}
