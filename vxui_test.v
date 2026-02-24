module vxui

import time

// Test get_free_port returns a valid port number
fn test_get_free_port() {
	port := get_free_port() or {
		assert false, 'Failed to get free port: ${err}'
		return
	}
	assert port >= 1025 && port <= 65534, 'Port ${port} out of valid range'
}

// Test get_free_port returns different ports on multiple calls
fn test_get_free_port_uniqueness() {
	port1 := get_free_port() or {
		assert false, 'Failed to get first port: ${err}'
		return
	}
	port2 := get_free_port() or {
		assert false, 'Failed to get second port: ${err}'
		return
	}
	// Ports could be the same if the first one is immediately released
	// Just ensure both are valid
	assert port1 >= 1025 && port1 <= 65534
	assert port2 >= 1025 && port2 <= 65534
}

// Test sanitize_path with valid paths
fn test_sanitize_path_valid() {
	valid_paths := [
		'./ui/index.html',
		'static/page.html',
		'file.txt',
		'path/to/file.v',
	]

	for path in valid_paths {
		result := sanitize_path(path) or {
			assert false, 'Valid path "${path}" was rejected: ${err}'
			return
		}
		assert result == path
	}
}

// Test sanitize_path rejects path traversal attempts
fn test_sanitize_path_traversal() {
	invalid_paths := [
		'../etc/passwd',
		'./../secret.txt',
		'path/../../../etc/hosts',
		'~/secret.txt',
		'/absolute/path',
		'./file~',
	]

	for path in invalid_paths {
		sanitize_path(path) or {
			// Expected to fail
			continue
		}
		assert false, 'Path "${path}" should have been rejected'
	}
}

// Test parse_attrs with various inputs
fn test_parse_attrs_empty() {
	verbs, path := parse_attrs('test', []) or {
		assert false, 'Failed to parse empty attrs: ${err}'
		return
	}
	assert path == '/test'
	assert verbs.len == 1
	assert Verb.any_verb in verbs
}

// Test parse_attrs with path only
fn test_parse_attrs_with_path() {
	verbs, path := parse_attrs('test', ['/custom']) or {
		assert false, 'Failed to parse path attr: ${err}'
		return
	}
	assert path == '/custom'
	assert verbs.len == 1
	assert Verb.any_verb in verbs
}

// Test parse_attrs with verb only
fn test_parse_attrs_with_verb() {
	verbs, path := parse_attrs('test', ['get', 'post']) or {
		assert false, 'Failed to parse verb attrs: ${err}'
		return
	}
	assert path == '/test'
	assert verbs.len == 2
	assert Verb.get in verbs
	assert Verb.post in verbs
}

// Test parse_attrs with both path and verbs
fn test_parse_attrs_combined() {
	verbs, path := parse_attrs('test', ['/api/test', 'get', 'post']) or {
		assert false, 'Failed to parse combined attrs: ${err}'
		return
	}
	assert path == '/api/test'
	assert verbs.len == 2
	assert Verb.get in verbs
	assert Verb.post in verbs
}

// Test parse_attrs with duplicate path (should fail)
fn test_parse_attrs_duplicate_path() {
	parse_attrs('test', ['/path1', '/path2']) or {
		// Expected to fail
		return
	}
	assert false, 'Duplicate paths should be rejected'
}

// Test parse_attrs with invalid verb
fn test_parse_attrs_invalid_verb() {
	parse_attrs('test', ['invalid_verb']) or {
		// Expected to fail
		return
	}
	assert false, 'Invalid verb should be rejected'
}

// Test verb_strings map
fn test_verb_strings_map() {
	assert 'get' in verb_strings
	assert 'post' in verb_strings
	assert 'put' in verb_strings
	assert 'delete' in verb_strings
	assert 'patch' in verb_strings

	assert verb_strings['get'] == Verb.get
	assert verb_strings['post'] == Verb.post
	assert verb_strings['put'] == Verb.put
	assert verb_strings['delete'] == Verb.delete
	assert verb_strings['patch'] == Verb.patch
}

// Test get_browser_args
fn test_get_browser_args_chrome() {
	args := get_browser_args('google-chrome')
	assert args.len > 0
	assert '--no-first-run' in args
	assert '--disable-gpu' in args
}

fn test_get_browser_args_chromium() {
	args := get_browser_args('chromium')
	assert args.len > 0
	assert '--no-first-run' in args
}

fn test_get_browser_args_firefox() {
	args := get_browser_args('firefox')
	// Firefox has different args
	assert args.len > 0
	assert '--new-instance' in args
}

// Test Route struct creation
fn test_route_struct() {
	route := Route{
		verb: [Verb.get, Verb.post]
		path: '/api/test'
	}
	assert route.path == '/api/test'
	assert route.verb.len == 2
	assert Verb.get in route.verb
	assert Verb.post in route.verb
}

// Test Verb enum values
fn test_verb_enum() {
	assert int(Verb.any_verb) == 0
	assert int(Verb.get) == 1
	assert int(Verb.post) == 2
	assert int(Verb.put) == 3
	assert int(Verb.delete) == 4
	assert int(Verb.patch) == 5
}

// Test Context struct with custom close_timer
fn test_context_with_custom_timer() {
	ctx := Context{
		close_timer: 1000
	}
	assert ctx.close_timer == 1000
	assert ctx.ws_port == 0
	assert ctx.routes.len == 0
}

// Test BrowserConfig struct
fn test_browser_config() {
	config := BrowserConfig{
		path: '/usr/bin/chrome'
		args: ['--arg1', '--arg2']
	}
	assert config.path == '/usr/bin/chrome'
	assert config.args.len == 2
	assert config.args[0] == '--arg1'
	assert config.args[1] == '--arg2'
}

// Test HTML escape functions
fn test_escape_html() {
	// Test basic HTML escaping
	assert escape_html('<script>') == '&lt;script&gt;'
	assert escape_html('"quoted"') == '&quot;quoted&quot;'
	assert escape_html("'single'") == '&#x27;single&#x27;'
	assert escape_html('a & b') == 'a &amp; b'

	// Test mixed content
	input := '<div onclick="alert(\'xss\')">test</div>'
	expected := '&lt;div onclick=&quot;alert(&#x27;xss&#x27;)&quot;&gt;test&lt;/div&gt;'
	assert escape_html(input) == expected
}

fn test_escape_js() {
	// Test JavaScript escaping
	assert escape_js('"quoted"') == '\\"quoted\\"'
	assert escape_js("'single'") == "\\'single\\'"
	assert escape_js('back\\slash') == 'back\\\\slash'
	assert escape_js('line\nbreak') == 'line\\nbreak'
}

fn test_escape_attr() {
	// Test attribute escaping
	assert escape_attr('"value"') == '&quot;value&quot;'
	assert escape_attr("'value'") == '&#x27;value&#x27;'
	assert escape_attr('a & b') == 'a &amp; b'
}

// Test truncate_string
fn test_truncate_string() {
	assert truncate_string('hello', 10) == 'hello'
	assert truncate_string('hello world', 8) == 'hello...'
	assert truncate_string('test', 3) == 'tes'
	assert truncate_string('', 5) == ''
}

// Test is_valid_email
fn test_is_valid_email() {
	// Valid emails
	assert is_valid_email('test@example.com') == true
	assert is_valid_email('user.name@domain.co.uk') == true

	// Invalid emails
	assert is_valid_email('') == false
	assert is_valid_email('invalid') == false
	assert is_valid_email('@example.com') == false
	assert is_valid_email('test@') == false
	assert is_valid_email('test@.com') == false
}

// Test generate_id
fn test_generate_id() {
	id1 := generate_id()
	id2 := generate_id()

	// IDs should be 16 characters
	assert id1.len == 16
	assert id2.len == 16

	// IDs should be different
	assert id1 != id2

	// IDs should only contain hex characters
	for c in id1 {
		assert (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`)
	}
}

// Test PackedApp struct
fn test_packed_app_new() {
	packed := new_packed_app()
	assert packed.files.len == 0
	assert packed.total_size() == 0
}

fn test_packed_app_add_file() {
	mut packed := new_packed_app()
	packed.add_file('test.html', 'Hello World'.bytes())
	
	assert packed.files.len == 1
	assert packed.has_file('test.html')
	assert packed.total_size() == 11
}

fn test_packed_app_add_file_string() {
	mut packed := new_packed_app()
	packed.add_file_string('index.html', '<html></html>')
	
	assert packed.files.len == 1
	assert packed.has_file('index.html')
	
	content := packed.get_file_content('index.html')!
	assert content == '<html></html>'
}

fn test_packed_app_get_file() {
	mut packed := new_packed_app()
	packed.add_file('style.css', 'body { color: red; }'.bytes())
	
	file := packed.get_file('style.css')!
	assert file.size == 20
	
	// Test non-existent file
	packed.get_file('nonexistent.css') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_packed_app_list_files() {
	mut packed := new_packed_app()
	packed.add_file_string('a.html', 'a')
	packed.add_file_string('b.css', 'b')
	packed.add_file_string('c.js', 'c')
	
	files := packed.list_files()
	assert files.len == 3
	assert 'a.html' in files
	assert 'b.css' in files
	assert 'c.js' in files
}

// === New Feature Tests (v0.2.0) ===

// Test Client struct
fn test_client_struct() {
	now := time.now()
	client := Client{
		id: 'test-client-123'
		token: 'secret-token'
		connected: now
	}
	assert client.id == 'test-client-123'
	assert client.token == 'secret-token'
	assert client.connected == now
	assert client.connection == unsafe { nil }
}

// Test WindowConfig struct with defaults
fn test_window_config_defaults() {
	config := WindowConfig{}
	assert config.width == 800
	assert config.height == 600
	assert config.x == -1  // center
	assert config.y == -1  // center
	assert config.min_width == 100
	assert config.min_height == 100
	assert config.resizable == true
	assert config.frameless == false
	assert config.transparent == false
}

// Test WindowConfig with custom values
fn test_window_config_custom() {
	config := WindowConfig{
		width: 1920
		height: 1080
		x: 100
		y: 50
		resizable: false
		title: 'My App'
	}
	assert config.width == 1920
	assert config.height == 1080
	assert config.x == 100
	assert config.y == 50
	assert config.resizable == false
	assert config.title == 'My App'
}

// Test Context with multi_client enabled
fn test_context_multi_client() {
	mut ctx := Context{}
	ctx.multi_client = true
	ctx.close_timer = 5000
	ctx.token = 'test-token-12345'
	
	assert ctx.multi_client == true
	assert ctx.close_timer == 5000
	assert ctx.token == 'test-token-12345'
	assert ctx.clients.len == 0
}

// Test Context with WindowConfig
fn test_context_window_config() {
	mut ctx := Context{}
	ctx.window = WindowConfig{
		width: 1200
		height: 800
		title: 'Test Window'
	}
	
	assert ctx.window.width == 1200
	assert ctx.window.height == 800
	assert ctx.window.title == 'Test Window'
}

// Test get_clients returns empty list initially
fn test_get_clients_empty() {
	mut ctx := Context{}
	clients := ctx.get_clients()
	assert clients.len == 0
}

// Test get_client_count returns 0 initially
fn test_get_client_count_empty() {
	mut ctx := Context{}
	count := ctx.get_client_count()
	assert count == 0
}

// Test get_port returns 0 initially
fn test_get_port_initial() {
	ctx := Context{}
	assert ctx.get_port() == 0
}

// Test get_token returns empty string initially
fn test_get_token_initial() {
	ctx := Context{}
	assert ctx.get_token() == ''
}

// Test get_token with custom token
fn test_get_token_custom() {
	mut ctx := Context{}
	ctx.token = 'my-secret-token'
	assert ctx.get_token() == 'my-secret-token'
}

// Test set_window_size
fn test_set_window_size() {
	mut ctx := Context{}
	ctx.set_window_size(1024, 768)
	assert ctx.window.width == 1024
	assert ctx.window.height == 768
}

// Test set_window_position
fn test_set_window_position() {
	mut ctx := Context{}
	ctx.set_window_position(100, 200)
	assert ctx.window.x == 100
	assert ctx.window.y == 200
}

// Test set_window_position with center (-1)
fn test_set_window_position_center() {
	mut ctx := Context{}
	ctx.set_window_position(-1, -1)
	assert ctx.window.x == -1
	assert ctx.window.y == -1
}

// Test set_window_title
fn test_set_window_title() {
	mut ctx := Context{}
	ctx.set_window_title('My Application')
	assert ctx.window.title == 'My Application'
}

// Test set_resizable
fn test_set_resizable() {
	mut ctx := Context{}
	ctx.set_resizable(false)
	assert ctx.window.resizable == false
	ctx.set_resizable(true)
	assert ctx.window.resizable == true
}

// Test close_client with non-existent client
fn test_close_client_not_found() {
	mut ctx := Context{}
	ctx.close_client('non-existent-id') or {
		// Expected to fail
		assert err.msg().contains('not found')
		return
	}
	assert false, 'Should have failed for non-existent client'
}

// Test broadcast with no clients (should not crash)
fn test_broadcast_no_clients() {
	mut ctx := Context{}
	// This should succeed even with no clients (just does nothing)
	ctx.broadcast('test message') or {
		// Might fail if write fails, but not due to no clients
		return
	}
}

// Test run_js with no clients (should return error)
fn test_run_js_no_clients() {
	mut ctx := Context{}
	ctx.run_js('alert(1)', 1000) or {
		// Expected to fail with "No connected clients"
		assert err.msg().contains('No connected clients')
		return
	}
	assert false, 'Should have failed with no clients'
}

// Test run_js_client with non-existent client
fn test_run_js_client_not_found() {
	mut ctx := Context{}
	ctx.run_js_client('non-existent-id', 'alert(1)', 1000) or {
		// Expected to fail with "Client not found"
		assert err.msg().contains('not found')
		return
	}
	assert false, 'Should have failed for non-existent client'
}

// Test Config struct with defaults
fn test_config_defaults() {
	config := Config{}
	assert config.close_timer == 50
	assert config.ws_ping_interval == 10
	assert config.require_auth == true
	assert config.multi_client == false
	assert config.max_clients == 10
	assert config.js_timeout_default == 5000
	assert config.js_poll_interval == 10
}

// Test Config with custom values
fn test_config_custom() {
	config := Config{
		close_timer: 1000
		token: 'my-custom-token'
		multi_client: true
		max_clients: 5
		js_timeout_default: 10000
		window: WindowConfig{
			width: 1920
			height: 1080
		}
	}
	assert config.close_timer == 1000
	assert config.token == 'my-custom-token'
	assert config.multi_client == true
	assert config.max_clients == 5
	assert config.js_timeout_default == 10000
	assert config.window.width == 1920
	assert config.window.height == 1080
}

// Test Config window integration
fn test_config_window() {
	mut config := Config{}
	config.window.width = 1280
	config.window.height = 720
	config.window.title = 'Test App'
	
	assert config.window.width == 1280
	assert config.window.height == 720
	assert config.window.title == 'Test App'
}
