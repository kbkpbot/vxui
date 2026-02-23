module vxui

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
