module vxui

// =============================================================================
// Configuration Tests
// =============================================================================

fn test_config_defaults() {
	config := Config{}
	assert config.close_timer_ms == 5000
	assert config.ws_ping_interval_ms == 30000
	assert config.ws_pong_timeout_ms == 60000
	assert config.require_auth == true
	assert config.multi_client == false
	assert config.max_clients == 10
	assert config.js_timeout == 5000
	assert config.js_poll_ms == 10
	assert config.app_name == 'vxui-app'
}

fn test_config_custom() {
	config := Config{
		app_name:       'my-app'
		close_timer_ms: 10000
		multi_client:   true
		max_clients:    5
		window:         WindowConfig{
			width:  1920
			height: 1080
		}
	}
	assert config.app_name == 'my-app'
	assert config.close_timer_ms == 10000
	assert config.multi_client == true
	assert config.max_clients == 5
	assert config.window.width == 1920
}

fn test_js_sandbox_config_defaults() {
	config := JsSandboxConfig{}
	assert config.enabled == true
	assert config.timeout_ms == 5000
	assert config.max_result_size == 1048576
	assert config.allow_eval == false
	assert config.forbidden_patterns.len > 0
}

fn test_js_sandbox_config_custom() {
	config := JsSandboxConfig{
		enabled:         false
		timeout_ms:      10000
		max_result_size: 2097152
		allow_eval:      true
	}
	assert config.enabled == false
	assert config.timeout_ms == 10000
	assert config.max_result_size == 2097152
	assert config.allow_eval == true
}

fn test_window_config_defaults() {
	config := WindowConfig{}
	assert config.width == 800
	assert config.height == 600
	assert config.x == -1
	assert config.y == -1
}

fn test_window_config_custom() {
	config := WindowConfig{
		width:  1920
		height: 1080
		x:      100
		y:      50
		title:  'My App'
	}
	assert config.width == 1920
	assert config.height == 1080
	assert config.title == 'My App'
}

fn test_browser_config_defaults() {
	config := BrowserConfig{}
	assert config.custom_args.len == 0
	assert config.headless == false
	assert config.devtools == false
	assert config.no_sandbox == false
}

fn test_browser_config_custom() {
	config := BrowserConfig{
		custom_args: ['--test-arg']
		headless:    true
		devtools:    true
		no_sandbox:  true
	}
	assert config.custom_args.len == 1
	assert config.headless == true
	assert config.devtools == true
	assert config.no_sandbox == true
}

fn test_log_config_defaults() {
	config := LogConfig{}
	assert config.level == .info
	assert config.output == 'stderr'
}

fn test_config_full_setup() {
	config := Config{
		app_name:            'test-app'
		close_timer_ms:      10000
		ws_ping_interval_ms: 15000
		ws_pong_timeout_ms:  30000
		require_auth:        true
		multi_client:        true
		max_clients:         5
		js_timeout:          3000
		js_poll_ms:          20
		window:              WindowConfig{
			width:  1920
			height: 1080
			title:  'Test App'
		}
		browser:             BrowserConfig{
			headless:   true
			devtools:   true
			no_sandbox: true
		}
		js_sandbox:          JsSandboxConfig{
			enabled:    true
			timeout_ms: 3000
			allow_eval: false
		}
	}

	assert config.app_name == 'test-app'
	assert config.window.width == 1920
	assert config.browser.headless == true
	assert config.js_sandbox.enabled == true
}
