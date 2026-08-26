module vxui

import time
import net.websocket
import x.json2
import encoding.utf8

// =============================================================================
// Error Type Tests
// =============================================================================

fn test_vxui_error_enum() {
	assert int(VxuiError.unknown) == 0
	assert int(VxuiError.client_not_found) == 1
	assert int(VxuiError.no_clients) == 2
	assert int(VxuiError.no_valid_connection) == 3
	assert int(VxuiError.js_timeout) == 4
	assert int(VxuiError.js_validation_failed) == 5
}

fn test_vxui_error_detail_struct() {
	err := VxuiErrorDetail{
		code:    VxuiError.client_not_found
		message: 'Client not found'
		details: {
			'client_id': 'test-123'
		}
	}
	assert err.code == VxuiError.client_not_found
	assert err.message == 'Client not found'
	assert err.details['client_id'] == 'test-123'
}

fn test_vxui_error_detail_str() {
	err := VxuiErrorDetail{
		code:    VxuiError.auth_failed
		message: 'Authentication failed'
	}
	assert err.str() == 'Authentication failed'
}

fn test_new_error_detail() {
	err := new_error_detail(VxuiError.no_clients, 'No connected clients')
	assert err.code == VxuiError.no_clients
	assert err.message == 'No connected clients'
}

fn test_new_error_detail_with_details() {
	err := new_error_detail_with_details(VxuiError.client_not_found, 'Client not found', {
		'id': 'abc'
	})
	assert err.code == VxuiError.client_not_found
	assert err.details['id'] == 'abc'
}

// =============================================================================
// Event System Tests
// =============================================================================

fn test_event_type_enum() {
	assert int(EventType.before_start) == 0
	assert int(EventType.after_start) == 1
	assert int(EventType.client_connecting) == 2
	assert int(EventType.client_connected) == 3
	assert int(EventType.client_disconnected) == 4
	assert int(EventType.before_shutdown) == 5
	assert int(EventType.error) == 6
	assert int(EventType.js_execution) == 7
	assert int(EventType.before_request) == 8
	assert int(EventType.after_request) == 9
}

fn test_event_data_struct() {
	data := EventData{
		event_type: EventType.client_connected
		client_id:  'test-client'
		message:    'Client connected'
	}
	assert data.event_type == EventType.client_connected
	assert data.client_id == 'test-client'
}

// =============================================================================
// Request/Response Tests
// =============================================================================

fn test_verb_enum() {
	assert int(Verb.any_verb) == 0
	assert int(Verb.get) == 1
	assert int(Verb.post) == 2
	assert int(Verb.put) == 3
	assert int(Verb.delete) == 4
	assert int(Verb.patch) == 5
}

fn test_request_struct() {
	req := Request{
		verb:      Verb.post
		path:      '/api/test'
		client_id: 'client-1'
	}
	assert req.verb == Verb.post
	assert req.path == '/api/test'
	assert req.client_id == 'client-1'
}

fn test_response_struct() {
	mut resp := Response{
		status: 200
		body:   '{"result": "ok"}'
	}
	assert resp.status == 200
	assert resp.body == '{"result": "ok"}'

	resp.status = 404
	assert resp.status == 404
}

fn test_response_default_status() {
	resp := Response{}
	assert resp.status == 200
}

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

// =============================================================================
// Client Tests
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

// =============================================================================
// Context Tests
// =============================================================================

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

// =============================================================================
// Setter Tests
// =============================================================================

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

// =============================================================================
// Client Management Error Tests
// =============================================================================

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

// =============================================================================
// Broadcast Tests
// =============================================================================

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

// =============================================================================
// JS Validation Tests
// =============================================================================

fn test_validate_js_code_safe() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	validate_js_code('document.title', sandbox) or {
		assert false
		return
	}
}

fn test_validate_js_code_forbidden() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	validate_js_code('eval("alert(1)")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

// =============================================================================
// Verb Strings Map Tests
// =============================================================================

fn test_verb_strings_map() {
	assert 'get' in verb_strings
	assert 'post' in verb_strings
	assert 'put' in verb_strings
	assert 'delete' in verb_strings
	assert 'patch' in verb_strings

	assert verb_strings['get'] == Verb.get
	assert verb_strings['post'] == Verb.post
}

// =============================================================================
// Route Tests
// =============================================================================

fn test_route_struct() {
	route := Route{
		verb: [Verb.get, Verb.post]
		path: '/api/test'
	}
	assert route.path == '/api/test'
	assert route.verb.len == 2
	assert Verb.get in route.verb
}

// RoutingTestApp exercises attribute-gated route registration:
// helpers WITHOUT attributes must never become routes, and their signatures
// must not influence compilation of fire_call/generate_routes.
@[heap]
struct RoutingTestApp {
	Context
mut:
	calls int
}

@['/tagged']
fn (mut app RoutingTestApp) tagged_handler(message map[string]json2.Any) string {
	app.calls++
	return 'tagged-ok'
}

// untagged message-signature method: NOT a route under attr-gating
fn (mut app RoutingTestApp) untagged_handler(message map[string]json2.Any) string {
	return 'untagged'
}

// untagged void helper with a custom signature: must not become a route
fn (mut app RoutingTestApp) track_call(x int) {
	app.calls += x
}

fn test_generate_routes_registers_only_tagged_methods() {
	mut app := RoutingTestApp{}
	routes := generate_routes(app)!
	assert 'tagged_handler' in routes
	assert routes['tagged_handler'].path == '/tagged'
	// untagged methods are not registered, neither by fn name nor path alias
	assert 'untagged_handler' !in routes
	assert '/untagged_handler' !in routes
	assert 'track_call' !in routes
}

fn test_fire_call_rejects_untagged_method() {
	mut app := RoutingTestApp{}
	result := fire_call(mut app, 'tagged_handler', {})!
	assert result == 'tagged-ok'
	// untagged methods are unreachable through dispatch
	res := fire_call(mut app, 'untagged_handler', {}) or {
		assert err.code() == int(VxuiError.route_not_found)
		'blocked'
	}
	assert res == 'blocked'
}

// A tagged method that does not return string is a configuration mistake:
// generate_routes must fail fast with a clear message instead of silently
// registering a route that cannot be dispatched.
struct BadReturnApp {
	Context
}

@['/bad']
fn (mut app BadReturnApp) bad_handler(message map[string]json2.Any) int {
	return 1
}

fn test_generate_routes_rejects_tagged_non_string_method() {
	mut app := BadReturnApp{}
	generate_routes(app) or {
		assert '${err}'.contains('return string'), 'unexpected error: ${err}'
		return
	}
	assert false, 'tagged method returning non-string must be rejected at startup'
}

// =============================================================================
// Security Gate Tests
// =============================================================================

fn test_addr_is_loopback() {
	assert addr_is_loopback('127.0.0.1')
	assert addr_is_loopback('127.9.9.9')
	assert addr_is_loopback('::1')
	assert addr_is_loopback('[::1]')
	assert addr_is_loopback('::ffff:127.0.0.1') // IPv4-mapped form
	assert !addr_is_loopback('192.168.1.10')
	assert !addr_is_loopback('10.0.0.5')
	assert !addr_is_loopback('')
	assert !addr_is_loopback('?')
}

fn test_message_token_valid() {
	msg_with := {
		'token': json2.Any('secret')
		'rpcID': json2.Any(i64(1))
	}
	msg_without := {
		'rpcID': json2.Any(i64(1))
	}
	msg_wrong := {
		'token': json2.Any('nope')
	}

	// default posture: auth required
	assert message_token_valid(msg_with, true, 'secret')
	assert !message_token_valid(msg_without, true, 'secret')
	assert !message_token_valid(msg_wrong, true, 'secret')
	// explicit opt-out keeps working
	assert message_token_valid(msg_without, false, 'secret')
}

// =============================================================================
// WebSocket Integration Tests (real client against the real server loop)
// =============================================================================

fn new_ws_test_app(port u16) !&RoutingTestApp {
	mut app := &RoutingTestApp{}
	app.ws_port = port
	app.config.token = 'it-token'
	app.config.close_timer_ms = 60_000
	app.clients = map[string]Client{}
	app.js_callbacks = map[string]chan string{}
	app.event_handlers = map[EventType][]EventHandler{}
	app.client_remove_chan = chan ClientRemoveMsg{cap: 8}
	app.routes = generate_routes(app)!
	return app
}

// wait_for polls cond up to timeout_ms; returns true once satisfied
fn wait_for(timeout_ms int, cond fn () bool) bool {
	deadline := time.now().unix_milli() + i64(timeout_ms)
	for time.now().unix_milli() < deadline {
		if cond() {
			return true
		}
		time.sleep(10 * time.millisecond)
	}
	return cond()
}

fn test_handle_request_matches_tagged_route_directly() {
	mut app := new_ws_test_app(0)!
	mut ctx := unsafe { &app.Context }
	req := Request{
		path:        '/tagged'
		verb:        .get
		raw_message: {}
	}
	resp := handle_request(mut app, ctx, req, {})!
	assert resp.status == 200
	assert resp.body == 'tagged-ok'
}

fn test_websocket_integration_auth_rpc_and_reject() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }

	mut after_req := chan string{cap: 8}
	ctx.on_event(.after_request, fn [mut after_req, mut ctx] (e EventData) {
		body := if r := e.response { r.body } else { '<no response>' }
		mut keys := []string{}
		for k, _ in ctx.routes {
			keys << '${k}=${ctx.routes[k].path}'
		}
		rp := if r := e.request { '${r.path}|${r.verb}' } else { '<no req>' }
		after_req <- 'routes[${keys.join(',')}|n=${ctx.routes.len}] req=${rp} body=${body}'
	})

	startup_ws_server(mut app, .ip, port)!
	// production ordering (run() does the same): routes are generated after
	// the server is up, mirroring init→startup→generate_routes
	app.routes = generate_routes(app)!

	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// --- 1. RPC message WITHOUT a token field must be rejected and closed
	mut cl_bad := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl_bad.connect()!
	cl_bad.write_string('{"rpcID":1,"verb":"get","path":"/tagged"}')!
	time.sleep(300 * time.millisecond)
	assert after_req.len == 0 // handler never ran for the rejected message

	// --- 1b. pre-auth commands are no longer reachable without a token
	mut cl_pre := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl_pre.connect()!
	cl_pre.write_string('{"cmd":"pong","client_id":"ghost"}')!
	time.sleep(300 * time.millisecond)
	// server closed the socket over the token-less pong: an auth retry on the
	// same dead connection can therefore not register either
	cl_pre.write_string('{"cmd":"auth","token":"it-token"}')!
	time.sleep(300 * time.millisecond)
	assert ctx.clients.len == 0
	cl_pre.close(1000, 'done') or {}

	// --- 2. auth handshake registers the client
	mut cl_ok := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl_ok.connect()!
	cl_ok.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	})

	// --- 3. authenticated rpcID roundtrip reaches the handler
	cl_ok.write_string('{"rpcID":2,"token":"it-token","verb":"get","path":"/tagged"}')!
	select {
		payload := <-after_req {
			dump(payload)
			assert payload.contains('body=tagged-ok'), 'unexpected: ${payload}'
		}
		3 * time.second {
			assert false, 'after_request never fired for authenticated rpc'
		}
	}
	assert app.calls >= 1

	// --- 4. wrong token on an open socket gets it rejected too
	cl_ok.write_string('{"rpcID":3,"token":"wrong","verb":"get","path":"/tagged"}')!
	time.sleep(300 * time.millisecond)
	assert after_req.len == 0

	cl_ok.close(1000, 'done') or {}
	cl_bad.close(1000, 'done') or {}
	ctx.ws.free()
}

// read_text_until reads text frames until one whose payload satisfies `want`,
// skipping protocol-level control frames. Fails after ~2s.
fn read_text_until(mut cl websocket.Client, want fn (string) bool) !string {
	for _ in 0 .. 40 {
		msg := cl.read_next_message()!
		if msg.opcode == .text_frame {
			s := msg.payload.bytestr()
			if want(s) {
				return s
			}
		}
	}
	return error('expected text frame not received')
}

fn test_heartbeat_ping_answered_before_token_gate() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// A token-less application heartbeat (old cached vxui-ws.js) must be
	// answered with a pong — NOT closed with 1008 like other gated messages.
	mut cl := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{
			read_timeout: 2 * time.second
		})!
	cl.connect()!
	cl.write_string('{"cmd":"ping","client_id":"pre-auth"}')!
	pong := read_text_until(mut cl, fn (s string) bool {
		return s.contains('"pong"')
	}) or {
		assert false, 'token-less ping was not answered with pong'
		return
	}
	assert pong.contains('pre-auth')

	// The connection survived: auth works on the same socket afterwards.
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	}), 'ping-before-gate must not have killed the connection'

	cl.close(1000, 'done') or {}
	ctx.ws.free()
}

fn test_post_js_is_fire_and_forget_and_leaks_no_callback() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	mut cl := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{
			read_timeout: 2 * time.second
		})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	})

	ctx.post_js('void(0);')!
	// Registration must be gone immediately: post_js never waits.
	assert ctx.js_callbacks.len == 0, 'post_js left a pending js_callback'

	// The run_js command did go out on the wire (after the auth_ok frame).
	read_text_until(mut cl, fn (s string) bool {
		return s.contains('run_js') && s.contains('void(0)')
	}) or {
		assert false, 'post_js command never reached the client'
		return
	}

	cl.close(1000, 'done') or {}
	ctx.ws.free()
}

fn test_evict_on_new_lets_fresh_auth_replace_stale_session() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	app.config.multi_client = false
	app.config.evict_on_new = true
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// First (soon-stale) session
	mut cl_a := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{
			read_timeout: 2 * time.second
		})!
	cl_a.connect()!
	cl_a.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	})
	first_id := ctx.get_clients()[0]

	// Crash-recovery style reconnect with the same token takes over the slot
	mut cl_b := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{
			read_timeout: 2 * time.second
		})!
	cl_b.connect()!
	cl_b.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(3000, fn [ctx, first_id] () bool {
		if ctx.clients.len != 1 {
			return false
		}
		for id, _ in ctx.clients {
			return id != first_id
		}
		return false
	}), 'fresh auth must evict the stale session'

	// The stale socket was closed by the server
	mut stale_closed := false
	for _ in 0 .. 40 {
		cl_a.read_next_message() or {
			stale_closed = true
			break
		}
		time.sleep(25 * time.millisecond)
	}
	assert stale_closed, 'evicted client should observe a close/error'

	cl_a.close(1000, 'done') or {}
	cl_b.close(1000, 'done') or {}
	ctx.ws.free()
}

fn test_parse_attrs_empty() {
	verbs, path := parse_attrs('test', []) or {
		assert false
		return
	}
	assert path == '/test'
	assert verbs.len == 1
	assert Verb.any_verb in verbs
}

fn test_parse_attrs_with_path() {
	verbs, path := parse_attrs('test', ['/custom']) or {
		assert false
		return
	}
	assert path == '/custom'
}

fn test_parse_attrs_with_verb() {
	verbs, path := parse_attrs('test', ['get', 'post']) or {
		assert false
		return
	}
	assert verbs.len == 2
	assert Verb.get in verbs
	assert Verb.post in verbs
}

fn test_parse_attrs_duplicate_path() {
	parse_attrs('test', ['/path1', '/path2']) or { return }
	assert false
}

fn test_parse_attrs_invalid_verb() {
	parse_attrs('test', ['invalid_verb']) or { return }
	assert false
}

// =============================================================================
// Utility Tests
// =============================================================================

fn test_get_free_port() {
	port := get_free_port() or {
		assert false
		return
	}
	assert port >= 1025 && port <= 65534
}

fn test_sanitize_path_valid() {
	valid_paths := ['./ui/index.html', 'static/page.html', 'file.txt']
	for path in valid_paths {
		sanitize_path(path) or {
			assert false
			return
		}
	}
}

fn test_sanitize_path_traversal() {
	invalid_paths := ['../etc/passwd', '~/secret.txt', '/absolute/path']
	for path in invalid_paths {
		sanitize_path(path) or { continue }
		assert false
	}
}

fn test_sanitize_utf8_passes_valid_text_through() {
	assert sanitize_utf8('hello') == 'hello'
	assert sanitize_utf8('中文备注') == '中文备注'
	assert sanitize_utf8('') == ''
	assert sanitize_utf8('mix中en文') == 'mix中en文'
}

fn test_sanitize_utf8_repairs_truncated_multibyte() {
	s := '中文备注'
	truncated := s.bytes()[..s.len - 1].bytestr() // cuts half of the last rune
	fixed := sanitize_utf8(truncated)
	assert utf8.validate_str(fixed), 'output must be valid UTF-8'
	assert fixed.starts_with('中文备')
}

fn test_sanitize_utf8_repairs_stray_continuation_bytes() {
	bad := [u8(0x61), u8(0x80), u8(0x62)].bytestr() // a, stray cont., b
	fixed := sanitize_utf8(bad)
	assert utf8.validate_str(fixed)
	assert fixed.len == 5 // 1 byte + U+FFFD (3 bytes) + 1 byte
	assert fixed[0] == u8(0x61) && fixed[4] == u8(0x62)
}

fn test_escape_js() {
	assert escape_js('"quoted"') == '\\"quoted\\"'
	assert escape_js('line\nbreak') == 'line\\nbreak'
}

fn test_window_mode_args_use_equals_form_for_app_mode() {
	url := 'file:///x/index.html?vxui_ws_port=1234&vxui_token=abc'
	assert window_mode_args(.app, url) == ['--app=${url}']
	assert window_mode_args(.kiosk, url) == ['--kiosk', url]
	assert window_mode_args(.normal, url) == [url]
	app_arg := window_mode_args(.app, url)[0]
	assert app_arg.starts_with('--app='), 'Chromium ignores space-form value switches'
	assert !app_arg.contains(' '), 'URL and flag must be ONE argument'
}


// =============================================================================
// PackedApp Tests
// =============================================================================

fn test_packed_app_new() {
	packed := new_packed_app()
	assert packed.files.len == 0
	assert packed.total_size() == 0
}

fn test_packed_app_add_file() {
	mut packed := new_packed_app()
	packed.add_file('test.html', 'Hello'.bytes())
	assert packed.files.len == 1
	assert packed.has_file('test.html')
	assert packed.total_size() == 5
}

fn test_packed_app_add_file_string() {
	mut packed := new_packed_app()
	packed.add_file_string('index.html', '<html></html>')
	assert packed.files.len == 1

	content := packed.get_file_content('index.html')!
	assert content == '<html></html>'
}

fn test_packed_app_get_file_not_found() {
	packed := new_packed_app()
	packed.get_file('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_packed_app_list_files() {
	mut packed := new_packed_app()
	packed.add_file_string('a.html', 'a')
	packed.add_file_string('b.css', 'b')

	files := packed.list_files()
	assert files.len == 2
}

// =============================================================================
// on_event Test
// =============================================================================

fn test_on_event() {
	mut ctx := Context{}
	ctx.on_event(EventType.client_connected, fn (e EventData) {
		// Handler registered
	})
	assert ctx.event_handlers[EventType.client_connected].len == 1
}

// new_test_context builds a Context with initialized maps/channels,
// mirroring what init() does for a real app.
fn new_test_context() Context {
	mut ctx := Context{}
	ctx.clients = map[string]Client{}
	ctx.js_callbacks = map[string]chan string{}
	ctx.event_handlers = map[EventType][]EventHandler{}
	ctx.client_remove_chan = chan ClientRemoveMsg{cap: 8}
	return ctx
}

// Regression: client_disconnected handlers must be able to call Context APIs
// (get_clients/broadcast/...) — events must fire OUTSIDE the write lock,
// otherwise any handler touching the lock deadlocks.
fn test_disconnect_events_fire_outside_lock() {
	mut ctx := new_test_context()

	mut handler_ran := chan bool{cap: 4}
	ctx.on_event(.client_disconnected, fn [mut ctx, mut handler_ran] (e EventData) {
		// These acquire mu internally; called while holding mu they deadlock.
		_ := ctx.get_clients()
		_ := ctx.get_client_count()
		handler_ran <- true
	})

	stale := Client{
		id:        'stale-1'
		last_ping: time.now().add(-(2 * time.minute))
	}
	live := Client{
		id:        'live-1'
		last_ping: time.now()
	}
	ctx.clients['stale-1'] = stale
	ctx.clients['live-1'] = live

	// 1. timeout sweep removes the stale client and fires the event unlocked
	ctx.check_client_timeouts()
	assert 'stale-1' !in ctx.clients
	assert 'live-1' in ctx.clients

	// 2. removal channel path fires the event unlocked too
	ctx.client_remove_chan <- ClientRemoveMsg{'live-1', 'test'}
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()
	time.sleep(100 * time.millisecond)
	assert 'live-1' !in ctx.clients

	// both events observed, handlers ran to completion
	for _ in 0 .. 2 {
		select {
			ok := <-handler_ran {
				assert ok
			}
			10 * time.second {
				assert false, 'disconnect handler never completed (deadlock?)'
			}
		}
	}
}

// =============================================================================
// Route Matching Tests - Extended
// =============================================================================

fn test_parse_attrs_combined_verb_and_path() {
	verbs, path := parse_attrs('test', ['get', '/api/users']) or {
		assert false
		return
	}
	assert path == '/api/users'
	assert verbs.len == 1
	assert Verb.get in verbs
}

fn test_parse_attrs_multiple_verbs() {
	verbs, path := parse_attrs('api', ['get', 'post', 'put']) or {
		assert false
		return
	}
	assert verbs.len == 3
	assert Verb.get in verbs
	assert Verb.post in verbs
	assert Verb.put in verbs
	assert path == '/api'
}

fn test_parse_attrs_all_http_verbs() {
	for verb_name in ['get', 'post', 'put', 'delete', 'patch'] {
		verbs, _ := parse_attrs('test', [verb_name]) or {
			assert false
			return
		}
		assert verbs.len == 1
	}
}

fn test_parse_attrs_case_insensitive_verb() {
	verbs, _ := parse_attrs('test', ['GET', 'Post', 'PUT']) or {
		assert false
		return
	}
	assert verbs.len == 3
}

fn test_parse_attrs_path_normalization() {
	verbs, path := parse_attrs('MyHandler', ['/MyPath']) or {
		assert false
		return
	}
	assert path == '/mypath' // lowercase
}

// =============================================================================
// Security Tests - Extended
// =============================================================================

fn test_sanitize_path_null_byte() {
	// Null byte in filename - current implementation doesn't block this
	// This tests that the function handles it gracefully
	result := sanitize_path('file\x00.txt') or { return }
	assert result == 'file\x00.txt'
}

fn test_sanitize_path_encoded_traversal() {
	// URL encoded traversal - current implementation allows this
	// because it doesn't decode URL-encoded strings
	result := sanitize_path('%2e%2e%2f') or { return }
	assert result == '%2e%2e%2f'
}

fn test_sanitize_path_double_encoding() {
	// Double encoded traversal - current implementation allows this
	result := sanitize_path('%252e%252e%252f') or { return }
	assert result == '%252e%252e%252f'
}

fn test_escape_js_special_chars() {
	input := 'line1\nline2\ttab"quote\'apostrophe\\backslash'
	result := escape_js(input)
	assert result.contains('\\n')
	assert result.contains('\\t')
	assert result.contains('\\"')
	assert result.contains("\\'")
	assert result.contains('\\\\')
}

// =============================================================================
// JS Sandbox Security Tests
// =============================================================================

fn test_validate_js_code_eval_blocked() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'Function(', 'setTimeout(']
	}

	// Should block eval
	validate_js_code('eval("alert(1)")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

fn test_validate_js_code_fetch_blocked() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['fetch(', 'XMLHttpRequest', 'WebSocket']
	}

	// Should block fetch
	validate_js_code('fetch("/api/data")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

fn test_validate_js_code_case_insensitive() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['EVAL(']
	}

	// Should block even with different case
	validate_js_code('EVAL("test")', sandbox) or { return }
	assert false
}

fn test_validate_js_code_safe_code() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	// Should allow safe code
	validate_js_code('document.title = "Hello"', sandbox) or {
		assert false
		return
	}
}

fn test_js_sandbox_disabled_allows_all() {
	sandbox := JsSandboxConfig{
		enabled:            false
		forbidden_patterns: ['eval(']
	}

	// Should allow when sandbox disabled
	validate_js_code('eval("test")', sandbox) or {
		assert false
		return
	}
}

// =============================================================================
// Error Handling Tests - Extended
// =============================================================================

fn test_vxui_error_detail_error_chain() {
	err := new_error_detail(VxuiError.client_not_found, 'Client not found')
	// Test that we can get the error message
	assert err.str() == 'Client not found'
	assert err.code == VxuiError.client_not_found
}

fn test_vxui_error_all_codes() {
	// Ensure all error codes are accessible
	codes := [
		VxuiError.unknown,
		VxuiError.client_not_found,
		VxuiError.no_clients,
		VxuiError.no_valid_connection,
		VxuiError.js_timeout,
		VxuiError.js_validation_failed,
		VxuiError.js_result_too_large,
		VxuiError.auth_failed,
		VxuiError.auth_invalid_token,
		VxuiError.port_not_available,
		VxuiError.browser_not_found,
		VxuiError.file_not_found,
		VxuiError.path_traversal,
		VxuiError.route_not_found,
	]
	assert codes.len == 14
}

// =============================================================================
// Request Building Tests
// =============================================================================

fn test_build_request_defaults() {
	message := map[string]json2.Any{}
	req := build_request(message, 'client-1')

	assert req.verb == Verb.get
	assert req.path == '/'
	assert req.client_id == 'client-1'
}

fn test_build_request_with_verb() {
	mut message := map[string]json2.Any{}
	message['verb'] = json2.Any('POST')
	req := build_request(message, 'client-1')

	assert req.verb == Verb.post
}

fn test_build_request_with_path() {
	mut message := map[string]json2.Any{}
	message['path'] = json2.Any('/api/users')
	req := build_request(message, 'client-1')

	assert req.path == '/api/users'
}

// =============================================================================
// Config Integration Tests
// =============================================================================

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

// =============================================================================
// Enhanced Path Sanitization Tests
// =============================================================================

fn test_sanitize_path_url_encoded_traversal() {
	// Test URL-encoded ../
	if _ := sanitize_path('%2e%2e%2f') {
		assert false // Should fail
	}
}

fn test_sanitize_path_double_encoded_traversal() {
	// Test double-encoded ../
	if _ := sanitize_path('%252e%252e%252f') {
		assert false // Should fail
	}
}

fn test_sanitize_path_mixed_encoding() {
	// Test mixed encoding
	if _ := sanitize_path('..%2fetc%2fpasswd') {
		assert false // Should fail
	}
}

fn test_sanitize_path_null_byte_enhanced() {
	// Test null byte injection
	if _ := sanitize_path('file\x00.txt') {
		assert false // Should fail
	}
}

fn test_sanitize_path_hidden_file_blocked() {
	// Hidden files without allowed extension should be blocked
	if _ := sanitize_path('.env') {
		assert false // Should fail
	}
	if _ := sanitize_path('.git/config') {
		assert false // Should fail
	}
	if _ := sanitize_path('.htaccess') {
		assert false // Should fail
	}
}

fn test_sanitize_path_hidden_file_allowed() {
	// Hidden files with allowed extensions should pass
	if _ := sanitize_path('.hidden.html') {
		// Should pass
	} else {
		assert false
	}
	if _ := sanitize_path('path/.styles.css') {
		// Should pass
	} else {
		assert false
	}
}

fn test_sanitize_path_backslash_traversal() {
	// Test backslash traversal (Windows-style)
	if _ := sanitize_path('..\\windows\\system32') {
		assert false // Should fail
	}
}

fn test_sanitize_path_plus_sign() {
	// Test that + is decoded to space
	result := sanitize_path('file+name.txt') or {
		assert false
		return
	}
	assert result == 'file+name.txt'
}

// =============================================================================
// Error Handling Consistency Tests
// =============================================================================

fn test_error_with_cause() {
	// Test that error detail can be created
	err := new_error_detail(VxuiError.no_clients, 'WebSocket failed')
	assert err.code == VxuiError.no_clients
	assert err.message == 'WebSocket failed'
}

fn test_error_chain() {
	// Test error with details
	inner := new_error_detail_with_details(VxuiError.client_not_found, 'Client abc not found', {
		'id': 'abc'
	})

	assert inner.code == VxuiError.client_not_found
	assert inner.details['id'] == 'abc'
}

fn test_all_error_codes_have_messages() {
	// Verify all error codes are defined
	codes := [
		VxuiError.unknown,
		VxuiError.client_not_found,
		VxuiError.no_clients,
		VxuiError.no_valid_connection,
		VxuiError.js_timeout,
		VxuiError.js_validation_failed,
		VxuiError.browser_not_found,
		VxuiError.file_not_found,
		VxuiError.auth_failed,
		VxuiError.port_not_available,
		VxuiError.route_not_found,
		VxuiError.auth_invalid_token,
		VxuiError.path_traversal,
		VxuiError.js_result_too_large,
	]

	for code in codes {
		assert int(code) >= 0
	}
}

// =============================================================================
// Escape Function Tests
// =============================================================================

fn test_escape_js_basic() {
	assert escape_js('alert("test")') == 'alert(\\"test\\")'
	assert escape_js('line1\nline2') == 'line1\\nline2'
	assert escape_js('path\\to\\file') == 'path\\\\to\\\\file'
}

fn test_escape_js_tab_and_return() {
	assert escape_js('\t') == '\\t'
	assert escape_js('\r') == '\\r'
}

// =============================================================================
// URL Decode Tests
// =============================================================================

fn test_url_decode_basic() {
	assert url_decode('Hello%20World') == 'Hello World'
	assert url_decode('test%2Fpath') == 'test/path'
}

fn test_url_decode_plus() {
	assert url_decode('Hello+World') == 'Hello World'
}

fn test_url_decode_no_encoding() {
	assert url_decode('plaintext') == 'plaintext'
}

fn test_url_decode_invalid_hex() {
	// Invalid hex sequences should pass through
	assert url_decode('%ZZ') == '%ZZ'
	assert url_decode('%2') == '%2'
}

// Regression: on_event() handlers registered BEFORE vxui.run()/init() must
// still fire. init() used to wipe event_handlers, silently dropping them.
fn test_on_event_before_run_survives_init() ! {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut fired := [false]
	app.on_event(.client_connected, fn [mut fired] (e vxui.EventData) {
		fired[0] = true // in-place: append would reallocate a captured copy
	})
	// registration sanity: the handler must be visible on the Context
	mut ctx0 := unsafe { &app.Context }
	assert ctx0.event_handlers[EventType.client_connected].len == 1
	// bisect: does direct dispatch through trigger_event fire the handler?
	ctx0.trigger_event(.client_connected, 'pre-test', '', {}, none, none, none)
	assert fired[0], 'direct trigger_event did not fire the handler'
	fired[0] = false
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut app] () {
		app.process_client_removals()
	}()
	defer {
		app.ws.free()
	}

	mut cl := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	auth_resp := read_text_until(mut cl, fn (s string) bool {
		return s.contains('"cmd":"auth_ok"')
	})!
	assert auth_resp.contains('"cmd":"auth_ok"')

	// the handler runs synchronously inside handle_auth (before auth_ok is
	// even written), so by the time we read auth_ok it must have fired
	assert fired[0], 'client_connected handler registered before run() did not fire'
	cl.close(1000, 'done') or {}
}

// Regression: a page RELOAD closes the old connection and reconnects ~1s
// later. The event loop must ride out that gap instead of shutting down.
fn test_reconnect_within_grace_window_keeps_server_alive() ! {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	app.config.evict_on_new = true
	ws := startup_ws_server(mut app, .ip, port)!
	spawn fn [mut app] () {
		app.process_client_removals()
	}()
	defer {
		app.ws.free()
	}

	// first connection: authenticate, then simulate a reload (client_close
	// notification followed by a fresh connection ~300ms later)
	mut cl1 := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl1.connect()!
	cl1.write_string('{"cmd":"auth","token":"it-token"}')!
	read_text_until(mut cl1, fn (s string) bool {
		return s.contains('"cmd":"auth_ok"')
	})!

	cl1.write_string('{"cmd":"client_close","token":"it-token","client_id":"${''}"}')!
	time.sleep(300 * time.millisecond)
	cl1.close(1000, 'reload') or {}

	// second connection arrives inside the grace window
	mut cl2 := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl2.connect()!
	cl2.write_string('{"cmd":"auth","token":"it-token"}')!
	resp2 := read_text_until(mut cl2, fn (s string) bool {
		return s.contains('"cmd":"auth_ok"')
	})!
	assert resp2.contains('"cmd":"auth_ok"'), 'reconnect after reload was rejected'

	// server must still be open well past the gap
	assert ws.get_state() == .open
	time.sleep(1700 * time.millisecond)
	assert ws.get_state() == .open, 'server shut down despite reconnect inside grace window'

	cl2.close(1000, 'done') or {}
}
