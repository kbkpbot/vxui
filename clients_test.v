module vxui

import time

// =============================================================================
// Client & Context Tests
// =============================================================================

fn test_client_struct() {
	now := time.now()
	client := Client{
		id:        'test-client-123'
		token:     'secret-token'
		last_ping: now
	}
	assert client.id == 'test-client-123'
	assert client.token == 'secret-token'
	assert client.connection == none
}

fn test_context_defaults() {
	ctx := Context{}
	assert ctx.config.close_timer_ms == 5000
	assert ctx.config.js_poll_ms == 10
	assert ctx.config.multi_client == false
	assert ctx.clients.len == 0
}

fn test_context_with_config() {
	mut ctx := Context{}
	ctx.config = Config{
		app_name:       'test-app'
		close_timer_ms: 8000
	}
	assert ctx.config.app_name == 'test-app'
	assert ctx.config.close_timer_ms == 8000
}

fn test_get_clients_empty() {
	mut ctx := Context{}
	clients := ctx.get_clients()
	assert clients.len == 0
}

fn test_get_client_count_empty() {
	mut ctx := Context{}
	count := ctx.get_client_count()
	assert count == 0
}

fn test_get_port_initial() {
	ctx := Context{}
	assert ctx.get_port() == 0
}

fn test_get_token_initial() {
	ctx := Context{}
	assert ctx.get_token() == ''
}

fn test_get_token_custom() {
	mut ctx := Context{}
	ctx.config.token = 'my-secret-token'
	assert ctx.get_token() == 'my-secret-token'
}

fn test_get_config() {
	mut ctx := Context{}
	ctx.config = Config{
		app_name: 'test'
	}
	config := ctx.get_config()
	assert config.app_name == 'test'
}

fn test_set_js_sandbox() {
	mut ctx := Context{}
	config := JsSandboxConfig{
		timeout_ms: 3000
	}
	ctx.set_js_sandbox(config)
	assert ctx.config.js_sandbox.timeout_ms == 3000
}

fn test_set_browser_config() {
	mut ctx := Context{}
	config := BrowserConfig{
		headless: true
	}
	ctx.set_browser_config(config)
	assert ctx.config.browser.headless == true
}

fn test_close_client_not_found() {
	mut ctx := Context{}
	ctx.close_client('non-existent-id') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_send_to_client_not_found() {
	mut ctx := Context{}
	ctx.send_to_client('non-existent-id', 'test') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_ping_client_not_found() {
	mut ctx := Context{}
	ctx.ping_client('non-existent-id') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_run_js_no_clients() {
	mut ctx := Context{}
	ctx.run_js('alert(1)', 1000) or {
		assert err.msg().contains('No connected clients')
		return
	}
	assert false
}

fn test_run_js_client_not_found() {
	mut ctx := Context{}
	ctx.run_js_client('non-existent-id', 'alert(1)', 1000) or {
		assert err.msg().contains('No connected clients') || err.msg().contains('not found')
		return
	}
	assert false
}

fn test_get_client_not_found() {
	mut ctx := Context{}
	client := ctx.get_client('non-existent-id')
	assert client == none
}

fn test_broadcast_no_clients() {
	mut ctx := Context{}
	ctx.broadcast('test message') or { return }
}

fn test_broadcast_except_no_clients() {
	mut ctx := Context{}
	ctx.broadcast_except('test message', 'client-1') or { return }
}

fn test_ping_all_clients_no_clients() {
	mut ctx := Context{}
	ctx.ping_all_clients()
}
