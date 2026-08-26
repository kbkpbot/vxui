module vxui

import os
import time

fn test_apply_config_file_overlays_settings() {
	mut cfg := Config{}
	// sanity defaults
	assert cfg.display.id == 'auto'
	assert cfg.browser.engine == .auto

	content := '{"display":{"id":"firefox"},"browser":{"engine":"firefox","headless":true,"no_sandbox":true,"window_mode":"kiosk","remote_debug_port":9222,"custom_args":["--foo","--bar"]},"window":{"width":1024,"height":768,"title":"CfgApp","x":10,"y":20},"dev":{"auto_devtools":false},"token":"sec","multi_client":true,"evict_on_new":false,"close_timer_ms":1234}'
	tmp := os.join_path('/tmp', 'vxui-test-${time.now().unix()}.json')
	os.write_file(tmp, content)!
	defer {
		os.rm(tmp) or {}
	}

	apply_config_file(mut cfg, tmp) or { assert false, 'apply_config_file failed: ${err}' }

	assert cfg.display.id == 'firefox'
	assert cfg.browser.engine == .firefox
	assert cfg.browser.headless == true
	assert cfg.browser.no_sandbox == true
	assert cfg.browser.window_mode == .kiosk
	assert cfg.browser.remote_debug_port == 9222
	assert cfg.browser.custom_args == ['--foo', '--bar']
	assert cfg.window.width == 1024
	assert cfg.window.height == 768
	assert cfg.window.title == 'CfgApp'
	assert cfg.window.x == 10
	assert cfg.window.y == 20
	assert cfg.dev.auto_devtools == false
	assert cfg.token == 'sec'
	assert cfg.multi_client == true
	assert cfg.evict_on_new == false
	assert cfg.close_timer_ms == 1234
}
