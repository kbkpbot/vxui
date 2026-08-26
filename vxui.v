module vxui

// vxui = browser + htmx + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import net
import net.websocket
import os
import time
import log
import x.json2
import rand
import sync

// =============================================================================
// Error Types - Structured Error Handling
// =============================================================================

// VxuiError represents error codes
pub enum VxuiError {
	unknown
	client_not_found
	no_clients
	no_valid_connection
	js_timeout
	js_validation_failed
	js_result_too_large
	auth_failed
	auth_invalid_token
	connection_error
	connection_closed
	port_not_available
	browser_not_found
	file_not_found
	path_traversal
	route_not_found
	invalid_message
	request_timeout
	// Additional error codes for unified error handling
	profile_create_failed
	process_fork_failed
	hidden_file_access
	null_byte_detected
	absolute_path_not_allowed
	invalid_method
	method_not_allowed
	attribute_parse_error
}

// VxuiErrorDetail represents a structured error with code and details
pub struct VxuiErrorDetail {
pub:
	code    VxuiError
	message string
	details map[string]string
	cause   ?IError // Underlying error that caused this error
}

// msg returns the error message (implements IError interface)
pub fn (e VxuiErrorDetail) msg() string {
	mut result := e.message
	if cause := e.cause {
		result += ': ${cause.msg()}'
	}
	return result
}

// code returns the error code (implements IError interface)
pub fn (e VxuiErrorDetail) code() int {
	return int(e.code)
}

// str returns the error message
pub fn (e VxuiErrorDetail) str() string {
	return e.msg()
}

// with_cause creates a new error with an underlying cause
pub fn (e VxuiErrorDetail) with_cause(cause IError) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    e.code
		message: e.message
		details: e.details
		cause:   cause
	}
}

// with_detail adds a detail to the error
pub fn (e VxuiErrorDetail) with_detail(key string, value string) VxuiErrorDetail {
	mut new_details := e.details.clone()
	new_details[key] = value
	return VxuiErrorDetail{
		code:    e.code
		message: e.message
		details: new_details
		cause:   e.cause
	}
}

// new_error_detail creates a new VxuiErrorDetail
pub fn new_error_detail(code VxuiError, message string) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: {}
	}
}

// new_error_detail_with_details creates a new VxuiErrorDetail with details
pub fn new_error_detail_with_details(code VxuiError, message string, details map[string]string) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: details
	}
}

// new_error_detail_with_cause creates a new VxuiErrorDetail with an underlying cause
pub fn new_error_detail_with_cause(code VxuiError, message string, cause IError) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: {}
		cause:   cause
	}
}

// =============================================================================
// Event System - Lifecycle Hooks
// =============================================================================

// EventType represents different lifecycle events
pub enum EventType {
	before_start
	after_start
	client_connecting
	client_connected
	client_disconnected
	before_shutdown
	error
	js_execution
	before_request
	after_request
}

// EventData contains event information
pub struct EventData {
pub:
	event_type EventType
	client_id  string
	message    string
	data       map[string]json2.Any
	request    ?Request
	response   ?Response
	err        ?VxuiErrorDetail
}

// EventHandler is a callback function type for events
pub type EventHandler = fn (EventData)

// =============================================================================
// Request/Response - Type-Safe Message Handling
// =============================================================================

// Verb represents HTTP methods
pub enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}

// Request represents a type-safe request
pub struct Request {
pub:
	id          string
	verb        Verb
	path        string
	parameters  map[string]string
	headers     map[string]string
	body        string
	client_id   string
	timestamp   time.Time
	raw_message map[string]json2.Any // Original message for compatibility
}

// Response represents a type-safe response
pub struct Response {
pub mut:
	status  int               = 200
	headers map[string]string = {}
	body    string
}

// =============================================================================
// Configuration Structures
// =============================================================================

// JsSandboxConfig controls JavaScript execution security
pub struct JsSandboxConfig {
pub mut:
	enabled            bool = true        // Enable sandbox restrictions
	timeout_ms         int  = 5000        // Max execution time
	max_result_size    int  = 1024 * 1024 // Max result size in bytes (1MB)
	allow_eval         bool // Allow eval() in frontend (dangerous!)
	forbidden_patterns []string = [// Forbidden patterns
		'eval(',
		'Function(',
		'setTimeout(',
		'setInterval(',
		'XMLHttpRequest',
		'fetch(',
		'WebSocket',
		'import(',
	]
}

// WindowConfig holds window configuration.
// NOTE: only size/position/title are actually enforced by the browser launch;
// the previous resizable/min-size/frameless fields never had any effect and
// were removed (see CHANGELOG).
pub struct WindowConfig {
pub mut:
	width  int = 800
	height int = 600
	x      int = -1 // -1 means center
	y      int = -1 // -1 means center
	title  string // window/page title; falls back to config.app_name when set
}

// WindowMode selects how the page window is presented. Only meaningful for
// Chromium-family browsers; Firefox/Safari open a normal tab regardless.
pub enum WindowMode {
	app    // standalone window WITHOUT address bar/tab strip (default)
	kiosk  // borderless fullscreen
	normal // an ordinary browser tab
}

// BrowserConfig holds browser startup configuration
@[heap]
pub struct BrowserConfig {
pub mut:
	custom_args       []string // Additional custom arguments
	profile_dir       string   // Custom profile directory (empty = default)
	headless          bool     // Run in headless mode (for testing)
	devtools          bool     // Open DevTools automatically
	no_sandbox        bool     // Disable sandbox (for root/CI)
	window_mode       WindowMode = .app // presentation of the app window (see WindowMode)
	user_data_dir     string // Custom user data directory
	preferred_path    string // Preferred browser path (skip detection)
	remote_debug_port int    // Chrome remote debugging port (0 = disabled)
}

// LogConfig holds logging settings.
// `output` accepts 'stderr' (default), 'stdout', or a file path.
// The previous max_file_size/rotate_files/show_* fields never had any
// effect and were removed (see CHANGELOG).
pub struct LogConfig {
pub mut:
	level  log.Level = .info
	output string    = 'stderr'
}

// Config is the unified configuration for vxui
pub struct Config {
pub mut:
	// Application settings
	app_name string = default_app_name

	// Development settings
	dev DevConfig // Development mode settings

	// Connection settings
	close_timer_ms      int = 5000  // Close app after N ms with no browser
	ws_ping_interval_ms int = 30000 // WebSocket ping interval
	ws_pong_timeout_ms  int = 60000 // Timeout for pong response

	// Security settings
	token        string // Security token (auto-generated if empty)
	require_auth bool = true // Require token authentication
	allow_remote bool // Accept connections from non-loopback interfaces (default false)

	// Client settings
	multi_client bool // Allow multiple browser clients
	// When multi_client is off, let a NEW successful authentication evict
	// stale sessions instead of letting a restored/crashed browser tab hold
	// the single slot forever. Defaults to true: without it, a simple F5
	// reload races the async client cleanup and the fresh connection gets
	// rejected — the app appears dead after a refresh.
	evict_on_new bool = true
	max_clients  int  = 10 // Maximum concurrent clients (0 = unlimited)

	// JavaScript execution settings
	js_timeout int = 5000 // Default timeout for run_js()
	js_poll_ms int = 10   // Polling interval for JS result
	js_sandbox JsSandboxConfig // JS execution sandbox

	// Window settings
	window WindowConfig

	// Browser settings
	browser BrowserConfig

	// Display backend selection
	display DisplayConfig

	// Logging settings
	log LogConfig
}

// DevConfig holds development mode settings
pub struct DevConfig {
pub mut:
	enabled       bool // Enable development mode
	hot_reload    bool = true // Enable hot reload (refresh browser on file change)
	watch_dirs    []string // Directories to watch for changes (default: html file dir)
	watch_ms      int  = 500  // File watch interval in milliseconds
	auto_devtools bool = true // Auto-open DevTools in dev mode
	show_errors   bool = true // Show error overlay in browser
}

// =============================================================================
// Client Management
// =============================================================================

// Client represents a connected browser client
pub struct Client {
pub:
	id            string
	token         string
	connected     time.Time
	request_count int
	last_request  time.Time
pub mut:
	connection ?&websocket.Client
	last_ping  time.Time
}

// =============================================================================
// Context - Main Application Struct
// =============================================================================

// verb_strings maps string to Verb enum
// default_app_name is the fallback window/page title marker; a user-changed
// app_name (or an explicit window.title) is pushed to connected clients
const default_app_name = 'vxui-app'

const verb_strings = {
	'get':    Verb.get
	'post':   .post
	'put':    .put
	'delete': .delete
	'patch':  .patch
}

// Route represents a registered route
pub struct Route {
	verb []Verb
	path string
}

// Context is the main struct of vxui
// ClientRemoveMsg is a message for the client removal channel
struct ClientRemoveMsg {
	client_id string
	from_msg  string // for debugging: 'client_close' or 'on_close'
}

pub struct Context {
mut:
	ws_port            u16
	ws                 websocket.Server
	display            Display
	display_session    ?DisplaySession
	display_sessions   []DisplaySession
	routes             map[string]Route
	clients            map[string]Client
	mu                 sync.RwMutex
	js_callbacks       map[string]chan string
	event_handlers     map[EventType][]EventHandler
	client_remove_chan chan ClientRemoveMsg // channel for serialized client removal
pub mut:
	config Config
	logger &log.Log = &log.Log{}
}

// =============================================================================
// Initialization
// =============================================================================

// context_of returns the embedded Context of a user app struct.
// The embedded field name `Context` is public, so this works across module
// boundaries while the Context internals stay private. Callers always pass
// `mut app`, so the reference is guaranteed to outlive the call.
fn context_of[T](mut app T) &Context {
	return unsafe { &app.Context }
}

// init initializes the vxui framework
fn init[T](mut app T) ! {
	mut ctx := context_of(mut app)
	ctx.ws_port = get_free_port()!

	// Generate security token if not set
	if ctx.config.token == '' {
		ctx.config.token = generate_token()
	}

	// Initialize maps
	ctx.clients = map[string]Client{}
	ctx.js_callbacks = map[string]chan string{}
	ctx.client_remove_chan = chan ClientRemoveMsg{cap: 100}

	// Setup logger (level + output destination)
	ctx.logger.set_level(ctx.config.log.level)
	match ctx.config.log.output {
		'stderr' {
			ctx.logger.set_output_stream(os.stderr())
		}
		'stdout', '' {
			// library default writes to the console
		}
		else {
			// treat anything else as a file path
			ctx.logger.set_output_path(ctx.config.log.output)
		}
	}

	ctx.ws = startup_ws_server(mut app, .ip, ctx.ws_port)!

	ctx.display = new_display(ctx.config.display.kind, &ctx.config.browser) or { return err }
}

// generate_token creates a random security token
fn generate_token() string {
	mut bytes := []u8{cap: 32}
	for _ in 0 .. 32 {
		bytes << rand.u8()
	}
	return bytes.hex()
}

// generate_client_id creates a unique client identifier
fn generate_client_id() string {
	return '${time.now().unix_milli()}-${rand.u32()}'
}

// generate_request_id creates a unique request identifier
fn generate_request_id() string {
	return 'req-${time.now().unix_milli()}-${rand.u32()}'
}

// =============================================================================
// WebSocket Server
// =============================================================================

// startup_ws_server starts the websocket server at `listen_port`.
// Callbacks derive the Context from the captured app on every invocation so
// they can never observe a stale/aliased Context instance.
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut ctx := context_of(mut app)
	mut s := websocket.new_server(family, listen_port, '')
	// The library's ping thread also WATCHDOGS clients: it closes any
	// connection whose pong is older than 2x this interval. A 1-second
	// interval killed clients whenever a route handler (e.g. a multi-MB
	// upload) blocked the read loop for more than 2 seconds. Drive it from
	// the documented config instead: interval = ws_ping_interval_ms, so the
	// effective watchdog threshold matches ws_pong_timeout_ms semantics.
	ping_secs := ctx.config.ws_ping_interval_ms / 1000
	s.set_ping_interval(if ping_secs < 1 { 1 } else { ping_secs })

	s.on_connect(fn [mut app] [T](mut s websocket.ServerClient) !bool {
		mut ctx := context_of(mut app)
		ctx.trigger_event(EventType.client_connecting, '', 'Client connecting...', {}, none, none,
			none)

		// Loopback gate: the server binds all interfaces, so unless the user
		// explicitly opted in, only local processes may connect. Use the PEER
		// address — sock.address() is the local endpoint we were dialed on.
		if !ctx.config.allow_remote {
			mut peer := '?'
			if a := s.client.conn.peer_addr() {
				peer = a.str().all_before_last(':')
			}
			if !addr_is_loopback(peer) {
				ctx.logger.warn('Rejecting non-loopback connection from ${peer} (set config.allow_remote = true to permit)')
				return false
			}
		}

		// Check client limit
		ctx.mu.rlock()
		client_count := ctx.clients.len
		ctx.mu.runlock()

		if !ctx.config.multi_client && !ctx.config.evict_on_new && client_count > 0 {
			ctx.logger.warn('Rejecting connection: multi_client is disabled')
			return false
		}

		if ctx.config.max_clients > 0 && client_count >= ctx.config.max_clients {
			ctx.logger.warn('Rejecting connection: max_clients limit reached')
			return false
		}

		return true
	})!

	s.on_message(fn [mut app] [T](mut ws websocket.Client, msg &websocket.Message) ! {
		mut ctx := context_of(mut app)
		if msg.opcode == .pong {
			// protocol-level pong: the websocket library answers control
			// pings itself; nothing to do here. Application liveness uses
			// the JSON cmd ping/pong in handle_control_message.
			return
		}
		raw_payload := msg.payload.bytestr()
		raw_message := json2.decode[json2.Any](raw_payload)!
		mut message := raw_message.as_map()
		ctx.logger.debug('Received message: ${message}')

		handled := ctx.handle_control_message(mut ws, message, raw_payload)!
		if handled {
			return
		}

		if rpc_id := message['rpcID'] {
			dispatch_rpc(mut app, mut ctx, mut ws, rpc_id.i64(), mut message)!
		}
	})

	s.on_close(fn [mut app] [T](mut ws websocket.Client, code int, reason string) ! {
		mut ctx := context_of(mut app)
		ctx.logger.info('Client disconnected: code=${code}, reason=${reason}')

		// Send removal request to channel (serialized processing)
		client_id_to_remove := ctx.find_client_id_by_connection(ws)
		if client_id_to_remove != '' {
			ctx.client_remove_chan <- ClientRemoveMsg{client_id_to_remove, 'on_close'}
		}
	})

	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut s)
	return s
}

// handle_control_message answers the framework-level commands carried by a
// control-channel text frame: auth, heartbeat ping, js_result, pong,
// client_close and get_clients. It also enforces the token gate.
// Returns true when the message was a control command and is fully handled;
// false means the caller should try rpc dispatch.
fn (mut ctx Context) handle_control_message(mut ws websocket.Client, message map[string]json2.Any, raw_payload string) !bool {
	// The auth handshake is the ONLY command reachable without a token.
	// Everything else — including js_result/pong/client_close, which used
	// to bypass the gate — requires a valid token; otherwise any local
	// web page could drive-by connect to the loopback port and forge
	// results, keep zombie clients alive or evict real ones.
	if cmd := message['cmd'] {
		if cmd.str() == 'auth' {
			ctx.handle_auth(mut ws, message) or {
				auth_err := new_error_detail(.auth_failed, 'Auth failed: ${err}')
				ctx.logger.error(auth_err.message)
				ctx.trigger_event(EventType.error, '', auth_err.message, message, none, none,
					auth_err)
				ws.close(1008, 'Authentication failed')!
			}
			return true
		}
	}

	// Application-level heartbeats carry no token on older cached
	// vxui-ws.js copies; answer them BEFORE the token gate so a session
	// can never be killed by its own keep-alive mechanism. Liveness
	// bookkeeping still requires a valid token.
	if cmd := message['cmd'] {
		if cmd.str() == 'ping' {
			if message_token_valid(message, ctx.config.require_auth, ctx.config.token) {
				ctx.handle_pong(message)
			}
			mut pong := map[string]json2.Any{}
			pong['cmd'] = json2.Any('pong')
			pong['client_id'] = message['client_id'] or { json2.Any('') }
			pong['timestamp'] = json2.Any(time.now().unix_milli())
			ws.write(json2.encode(pong).bytes(), .text_frame)!
			return true
		}
	}

	// Verify token for every non-auth message. When require_auth is on
	// (the default) a missing token is rejected just like a wrong one.
	if !message_token_valid(message, ctx.config.require_auth, ctx.config.token) {
		rejected_cmd := message['cmd'] or { json2.Any('') }.str()
		mut keys := []string{}
		for k, _ in message {
			keys << k
		}
		keys.sort()
		mut preview := raw_payload.replace('\n', ' ')
		if preview.runes().len > 96 {
			preview = preview.runes()[..96].map(it.str()).join('') + '…'
		}
		ctx.logger.warn('Unauthorized message rejected (missing or invalid token): cmd=${rejected_cmd} keys=[${keys.join(',')}] payload="${preview}"')
		ws.close(1008, 'Invalid token')!
		return true
	}

	if cmd := message['cmd'] {
		if cmd.str() == 'js_result' {
			ctx.handle_js_result(message)
			return true
		}
		if cmd.str() == 'pong' {
			ctx.handle_pong(message)
			return true
		}
		if cmd.str() == 'client_close' {
			// Client is closing, send removal request to channel
			client_id := message['client_id'] or { json2.Any('') }.str()
			ctx.client_remove_chan <- ClientRemoveMsg{client_id, 'client_close'}
			return true
		}
		// Authenticated utility command: enumerate connected clients
		if cmd.str() == 'get_clients' {
			mut ids := []json2.Any{}
			for id in ctx.get_clients() {
				ids << json2.Any(id)
			}
			mut resp := map[string]json2.Any{}
			resp['cmd'] = json2.Any('clients')
			resp['ids'] = json2.Any(ids)
			ws.write(json2.encode(resp).bytes(), .text_frame)!
			return true
		}
	}

	return false
}

// dispatch_rpc routes an rpcID-bearing message to its tagged route handler
// and writes the JSON response back on the same connection.
fn dispatch_rpc[T](mut app T, mut ctx Context, mut ws websocket.Client, rpc_id i64, mut message map[string]json2.Any) ! {
	client_id := ctx.find_client_id_by_connection(ws)
	// Make the caller's identity available to handlers: multi-player apps
	// (games, collaborative tools) need to know WHO issued a request, not
	// just what was requested.
	if client_id != '' {
		message['client_id'] = json2.Any(client_id)
	}

	// Build type-safe request
	req := build_request(message, client_id)

	// Trigger before_request event
	ctx.trigger_event(EventType.before_request, client_id, '', message, req, none, none)

	// Handle message
	response := handle_request(mut app, ctx, req, message) or {
		// unknown route: previously a completely silent 404 — the player
		// clicks a button and nothing happens, no trace anywhere
		ctx.logger.warn('rpc 404: no route for ${req.verb} ${req.path} (client ${client_id})')
		err_resp := '{"rpcID":"${rpc_id}", "error":"route_not_found", "message":"no route for ${req.path}"}'
		ws.write(err_resp.bytes(), .text_frame)!
		return
	}

	// Trigger after_request event
	ctx.trigger_event(EventType.after_request, client_id, '', message, req, response, none)

	json_response := '{"rpcID":"${rpc_id}", "data":${json2.encode(response.body)}}'
	ws.write(json_response.bytes(), .text_frame) or {
		ctx.log_write_failure(req.path, rpc_id, json_response, err)
		return
	}
}

// find_client_id_by_connection finds client ID by WebSocket connection
fn (ctx &Context) find_client_id_by_connection(ws websocket.Client) string {
	ctx.mu.rlock()

	for id, client in ctx.clients {
		// Compare the underlying TCP connection POINTER, not the whole
		// websocket.Client value: Client carries volatile fields
		// (last_pong_ut, ...), so value equality fails after the first pong
		// and every lookup would return '' (breaking caller-identity
		// injection, send_to_client, and anything else that resolves a
		// connection back to its client id).
		mut stored_conn := &net.TcpConn(unsafe { nil })
		if stored := client.connection {
			stored_conn = stored.conn
		}
		// SAFETY: pointer comparison only, no dereference
		if stored_conn != unsafe { nil } && stored_conn == ws.conn {
			ctx.mu.runlock()
			return id
		}
	}
	ctx.mu.runlock()
	return ''
}

// build_request creates a type-safe Request from raw message
fn build_request(message map[string]json2.Any, client_id string) Request {
	mut verb := Verb.get
	if v := message['verb'] {
		verb_str := v.str().to_lower()
		if verb_str in verb_strings {
			verb = verb_strings[verb_str]
		}
	}

	mut path := '/'
	if p := message['path'] {
		path = p.str()
	}

	mut parameters := map[string]string{}
	if params := message['parameters'] {
		for k, v in params.as_map() {
			parameters[k] = v.str()
		}
	}

	mut headers := map[string]string{}
	if h := message['headers'] {
		for k, v in h.as_map() {
			headers[k] = v.str()
		}
	}

	mut body := ''
	if b := message['body'] {
		body = b.str()
	}

	return Request{
		id:          generate_request_id()
		verb:        verb
		path:        path
		parameters:  parameters
		headers:     headers
		body:        body
		client_id:   client_id
		timestamp:   time.now()
		raw_message: message
	}
}

// addr_is_loopback reports whether the peer address is a loopback interface
fn addr_is_loopback(addr string) bool {
	return addr == '::1' || addr == '[::1]' || addr.starts_with('127.')
		|| addr.starts_with('::ffff:127.')
}

// message_token_valid decides whether a regular (non-cmd) message may pass.
// With require_auth enabled (default) a missing token is a rejection, not a bypass.
fn message_token_valid(message map[string]json2.Any, require_auth bool, token string) bool {
	if !require_auth {
		return true
	}
	t := message['token'] or { return false }
	return t.str() == token
}

// handle_auth processes client authentication
fn (mut ctx Context) handle_auth(mut ws websocket.Client, message map[string]json2.Any) ! {
	client_token := message['token'] or { json2.Null{} }

	if client_token is json2.Null {
		return new_error_detail(.auth_invalid_token, 'missing token')
	}
	if client_token.str() == '' {
		return new_error_detail(.auth_invalid_token, 'missing token')
	}
	if client_token.str() != ctx.config.token {
		return new_error_detail(.auth_invalid_token, 'invalid token')
	}

	// evict_on_new: a fresh successful auth takes over the single client
	// slot; older sessions are closed so a restored tab cannot lock out
	// the real page.
	if ctx.config.evict_on_new && !ctx.config.multi_client {
		current_id := ctx.find_client_id_by_connection(ws)
		ctx.mu.rlock()
		mut stale_ids := []string{}
		for id, _ in ctx.clients {
			if id != current_id {
				stale_ids << id
			}
		}
		ctx.mu.runlock()
		for id in stale_ids {
			ctx.logger.info('Evicting stale client ${id} for new session')
			ctx.close_client(id) or {}
		}
	}

	client_id := generate_client_id()

	ctx.mu.lock()
	ctx.clients[client_id] = Client{
		id:            client_id
		token:         ctx.config.token
		connected:     time.now()
		last_ping:     time.now()
		request_count: 0
		connection:    ws
	}
	ctx.mu.unlock()

	ctx.logger.info('Client authenticated: ${client_id}')
	ctx.trigger_event(EventType.client_connected, client_id, 'Client authenticated', {}, none,
		none, none)

	mut response := map[string]json2.Any{}
	response['cmd'] = json2.Any('auth_ok')
	response['client_id'] = json2.Any(client_id)
	if ctx.config.js_sandbox.enabled {
		response['js_sandbox'] = json2.encode(ctx.config.js_sandbox)
	}
	ws.write(json2.encode(response).bytes(), .text_frame)!

	// Apply the configured window/page title on the freshly connected client
	effective_title := if ctx.config.window.title != '' {
		ctx.config.window.title
	} else if ctx.config.app_name != default_app_name {
		ctx.config.app_name
	} else {
		''
	}
	if effective_title != '' {
		mut title_cmd := map[string]json2.Any{}
		title_cmd['cmd'] = json2.Any('run_js')
		title_cmd['js_id'] = json2.Any('title-${client_id}')
		title_cmd['script'] = json2.Any("document.title = '${escape_js(effective_title)}'")
		ws.write(json2.encode(title_cmd).bytes(), .text_frame)!
	}
}

// handle_pong processes heartbeat pong responses
fn (mut ctx Context) handle_pong(message map[string]json2.Any) {
	client_id := message['client_id'] or { json2.Any('') }.str()
	ctx.mu.lock()
	if client := ctx.clients[client_id] {
		mut updated_client := client
		updated_client.last_ping = time.now()
		ctx.clients[client_id] = updated_client
	}
	ctx.mu.unlock()
	ctx.logger.debug('Received pong from client: ${client_id}')
}

// handle_js_result processes JavaScript execution results
fn (mut ctx Context) handle_js_result(message map[string]json2.Any) {
	js_id := message['js_id'] or { return }.str()
	result := message['result'] or { json2.Any('') }.str()

	ctx.mu.lock()
	if js_id in ctx.js_callbacks {
		mut ch := ctx.js_callbacks[js_id]
		ch <- result
		ctx.js_callbacks.delete(js_id)
	}
	ctx.mu.unlock()
}

// start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections spawns the server
fn start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut ws websocket.Server) {
	spawn fn [mut ws] () {
		ws.listen() or { eprintln('WebSocket server error: ${err}') }
	}()

	mut attempts := 0
	max_attempts := 500
	for ws.get_state() != .open && attempts < max_attempts {
		time.sleep(10 * time.millisecond)
		attempts++
	}
}

// =============================================================================
// Event System
// =============================================================================

// trigger_event fires an event to all registered handlers
fn (mut ctx Context) trigger_event(event_type EventType, client_id string, message string, data map[string]json2.Any, request ?Request, response ?Response, err ?VxuiErrorDetail) {
	event := EventData{
		event_type: event_type
		client_id:  client_id
		message:    message
		data:       data
		request:    request
		response:   response
		err:        err
	}

	// NOTE: deliberately NOT `if handlers := m[key]` — that or-init form
	// silently skipped existing array values in this V build (0.5.2).
	mut handlers := []EventHandler{}
	if event_type in ctx.event_handlers {
		handlers = ctx.event_handlers[event_type]
	}
	for handler in handlers {
		handler(event)
	}
}

// on_event registers an event handler
pub fn (mut ctx Context) on_event(event_type EventType, handler EventHandler) {
	if ctx.event_handlers.len == 0 {
		// nil-map guard: handlers may be registered before init() runs
		ctx.event_handlers = map[EventType][]EventHandler{}
	}
	if event_type !in ctx.event_handlers {
		ctx.event_handlers[event_type] = []
	}
	ctx.event_handlers[event_type] << handler
}

// =============================================================================
// Route Handling
// =============================================================================

// handle_request processes a request through routes
fn handle_request[T](mut app T, ctx &Context, req Request, message map[string]json2.Any) !Response {
	for key, val in ctx.routes {
		if val.path == req.path && (req.verb in val.verb || Verb.any_verb in val.verb) {
			result := fire_call[T](mut app, key, message) or {
				return Response{
					status: 500
					body:   '{"error": "${err}"}'
				}
			}
			return Response{
				status: 200
				body:   result
			}
		}
	}
	return Response{
		status: 404
		body:   '{"error": "Route not found"}'
	}
}

// fire_call calls the method
// Only methods carrying route attributes (@['/path'] and/or a verb) are
// dispatchable; untagged helper methods are invisible to routing.
//
// NOTE on V comptime limits (tested on V 0.5.2 / 9142d68): the dispatch call
// below is instantiated ONCE FOR EVERY string-returning method of T,
// regardless of attributes — runtime `if` guards do not gate comptime
// instantiation, `$for attr in method.attributes` nesting parses but does
// not gate it either, and `continue` is illegal inside `$for`. Helpers on
// the app struct must therefore return void/non-string types (or take no
// parameters): a string-returning helper with custom parameters will not
// compile. generate_routes fails fast when a TAGGED method has the wrong
// return type, which keeps this constraint discoverable at startup.
pub fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
	$for method in T.methods {
		if method.attrs.len > 0 && method.name == method_name {
			$if method.return_type is string {
				return app.$method(message)
			}
			// Method found but doesn't return string - compile time error would be better
			// but we handle it gracefully at runtime
			return error('Method ${method_name} must return string')
		}
	}
	return new_error_detail_with_details(VxuiError.route_not_found, 'Method not found', {
		'method': method_name
	})
}

// parse_attrs parses function attributes for verbs and path
pub fn parse_attrs(name string, attrs []string) !([]Verb, string) {
	if attrs.len == 0 {
		return [Verb.any_verb], '/${name}'
	}

	mut verbs := []Verb{}
	mut path := ''

	for x in attrs {
		if x.starts_with('/') {
			if path != '' {
				return new_error_detail_with_details(VxuiError.route_not_found,
					'Cannot assign multiple paths to a route', {
					'function': name
				})
			} else {
				path = x
			}
		} else {
			if x.to_lower() in verb_strings.keys() {
				verbs << verb_strings[x.to_lower()]
			} else {
				return new_error_detail_with_details(VxuiError.invalid_method, 'Unknown verb', {
					'function': name
					'verb':     x
				})
			}
		}
	}
	if verbs.len == 0 {
		verbs << Verb.any_verb
	}
	if path == '' {
		path = '/${name}'
	}
	return verbs, path.to_lower()
}

// generate_routes generates route structs for an app
pub fn generate_routes[T](app &T) !map[string]Route {
	mut routes := map[string]Route{}
	$for method in T.methods {
		$if method.return_type is string {
			// Only attribute-tagged methods become routes; untagged methods
			// are plain helpers and must not be reachable from the frontend.
			if method.attrs.len > 0 {
				verbs, route_path := parse_attrs(method.name, method.attrs) or {
					return new_error_detail_with_cause(VxuiError.attribute_parse_error,
						'Error parsing method attributes', err)
				}
				routes[method.name] = Route{
					verb: verbs
					path: route_path
				}
			}
		} $else {
			// Tagged methods are dispatched with (mut app, message) and MUST
			// return string; anything else tagged is a configuration mistake
			// worth failing fast on (mirrors veb's route validation).
			if method.attrs.len > 0 {
				return new_error_detail_with_details(VxuiError.attribute_parse_error,
					'method `${method.name}` has route attributes but must return string', {
					'method':      method.name
					'return_type': '${method.return_type}'
				})
			}
		}
	}
	return routes
}

// =============================================================================
// Main Entry Points
// =============================================================================

// run opens the `html_filename` in browser and starts the event loop
pub fn run[T](mut app T, html_filename string) ! {
	mut ctx := context_of(mut app)

	ctx.trigger_event(EventType.before_start, '', 'Starting application', {}, none, none, none)

	init(mut app)!

	ctx.routes = generate_routes(app)!

	// Start client removal handler goroutine (serializes removal to prevent races)
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// Apply dev mode settings
	if ctx.config.dev.enabled {
		ctx.config.browser.devtools = ctx.config.dev.auto_devtools
		ctx.logger.info('Development mode enabled')
	}

	session_cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  ctx.config.window.width
		height: ctx.config.window.height
		x:      ctx.config.window.x
		y:      ctx.config.window.y
		title:  ctx.config.window.title
	}
	ctx.display_session = ctx.display.spawn(html_filename, session_cfg)!

	ctx.logger.info('Browser started, waiting for connections on port ${ctx.ws_port}...')
	ctx.logger.debug('Token: ${ctx.config.token}')

	ctx.trigger_event(EventType.after_start, '', 'Application started', {}, none, none, none)

	// Hot reload: track file modification times
	mut file_mtimes := map[string]time.Time{}
	mut watch_dirs := ctx.config.dev.watch_dirs.clone()
	if watch_dirs.len == 0 {
		// Default to the directory containing the HTML file
		watch_dirs << os.dir(os.abs_path(html_filename))
	}

	if ctx.config.dev.enabled && ctx.config.dev.hot_reload {
		ctx.logger.info('Hot reload watching: ${watch_dirs}')
		file_mtimes = scan_file_mtimes(watch_dirs)
	}

	mut ws_state := websocket.State.open

	mut last_client_time := time.now()

	mut last_hot_reload_check := time.now()

	mut last_ping_time := time.now()

	mut had_clients := false // Track if we ever had clients

	mut empty_since := time.Time{} // when the last client left (grace window)

	for {
		ws_state = ctx.ws.get_state()

		ctx.mu.rlock()

		client_count := ctx.clients.len

		ctx.mu.runlock()

		if ws_state == .closed {
			ctx.logger.info('WebSocket server closed')

			break
		}

		if client_count == 0 {
			if had_clients {
				// Grace window: a page RELOAD delivers client_close / FIN for
				// the old connection and reconnects a moment later. Exiting
				// immediately here turned every F5 into an app suicide.
				// Wait ~1.5s; a reconnecting client clears empty_since.
				if empty_since.is_zero() {
					empty_since = time.now()
				}

				if time.now().unix_milli() - empty_since.unix_milli() > 1500 {
					ctx.logger.info('All clients disconnected, shutting down')

					break
				}
			} else {
				// Never had clients, wait for timeout

				elapsed_ms := time.now().unix_milli() - last_client_time.unix_milli()

				if elapsed_ms > ctx.config.close_timer_ms {
					ctx.logger.info('No clients connected for ${ctx.config.close_timer_ms}ms, shutting down')

					break
				}
			}
		} else {
			had_clients = true

			empty_since = time.Time{}

			last_client_time = time.now()
		}

		app.check_client_timeouts()

		// Heartbeat: send ping to all clients periodically

		now := time.now()

		if client_count > 0
			&& now.unix_milli() - last_ping_time.unix_milli() >= ctx.config.ws_ping_interval_ms {
			last_ping_time = now

			app.ping_all_clients()

			ctx.logger.debug('Sent heartbeat ping to all clients')
		}

		// Hot reload check

		if ctx.config.dev.enabled && ctx.config.dev.hot_reload && client_count > 0 {
			if now.unix_milli() - last_hot_reload_check.unix_milli() >= ctx.config.dev.watch_ms {
				last_hot_reload_check = now
				new_mtimes := scan_file_mtimes(watch_dirs)
				if has_files_changed(file_mtimes, new_mtimes) {
					ctx.logger.info('Files changed, triggering hot reload')
					file_mtimes = new_mtimes.clone()
					app.trigger_hot_reload() or { ctx.logger.warn('Hot reload failed: ${err}') }
				}
			}
		}

		time.sleep(10 * time.millisecond)
	}

	ctx.trigger_event(EventType.before_shutdown, '', 'Application shutting down', {}, none, none,
		none)

	ctx.ws.free()
	ctx.logger.info('vxui shutdown complete')
}

// check_client_timeouts removes clients that haven't responded to pings
fn (mut ctx Context) check_client_timeouts() {
	ctx.mu.lock()
	mut stale_clients := []string{}
	now := time.now()

	for id, client in ctx.clients {
		if now.unix_milli() - client.last_ping.unix_milli() > ctx.config.ws_pong_timeout_ms {
			stale_clients << id
		}
	}

	for id in stale_clients {
		ctx.clients.delete(id)
		ctx.logger.warn('Removed stale client: ${id}')
	}
	ctx.mu.unlock()

	// Fire events AFTER releasing the lock: handlers may call back into
	// Context APIs (broadcast/get_clients/...) and do network IO.
	for id in stale_clients {
		ctx.trigger_event(EventType.client_disconnected, id, 'Client timeout', {}, none, none, none)
	}
}

// =============================================================================
// Packed/Embedded App Support
// =============================================================================

// run_packed runs the app with packed (embedded) resources
pub fn run_packed[T](mut app T, mut packed PackedApp, entry_file string) ! {
	temp_dir := packed.extract_to_temp()!
	app.logger.info('Extracted packed files to: ${temp_dir}')

	entry_path := os.join_path(temp_dir, entry_file)

	run(mut app, entry_path) or {
		packed.cleanup(temp_dir)
		return err
	}

	packed.cleanup(temp_dir)
}

// =============================================================================
// JavaScript Execution
// =============================================================================

// execute_js is the internal implementation for JS execution
fn (mut ctx Context) execute_js(client_id string, js_code string, timeout_ms int) !string {
	ctx.mu.rlock()
	if ctx.clients.len == 0 {
		ctx.mu.runlock()
		return new_error_detail(.no_clients, 'No connected clients')
	}

	// SAFETY: nil is used as sentinel value for optional pointer
	mut client_conn := &websocket.Client(unsafe { nil })
	if client_id == '' {
		for _, c in ctx.clients {
			// SAFETY: nil comparison only, no dereference
			client_conn = c.connection or { unsafe { nil } }
			break
		}
	} else {
		client := ctx.clients[client_id] or {
			ctx.mu.runlock()
			return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
		}
		// SAFETY: nil comparison only, no dereference
		client_conn = client.connection or { unsafe { nil } }
	}
	ctx.mu.runlock()

	// SAFETY: nil comparison only, no dereference
	if client_conn == unsafe { nil } {
		return new_error_detail(.no_valid_connection, 'No valid client connection')
	}

	if ctx.config.js_sandbox.enabled {
		validate_js_code(js_code, ctx.config.js_sandbox) or {
			return new_error_detail(.js_validation_failed, 'JS validation failed: ${err}')
		}
	}

	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()
	defer {
		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
	}

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('run_js')
	cmd['js_id'] = json2.Any(js_id)
	cmd['script'] = json2.Any(js_code)
	cmd['timeout'] = json2.Any(timeout_ms)
	client_conn.write(json2.encode(cmd).bytes(), .text_frame)!

	ctx.trigger_event(EventType.js_execution, client_id, js_code, {
		'js_id': json2.Any(js_id)
	}, none, none, none)

	if timeout_ms > 0 {
		mut result := ''
		mut got_result := false
		deadline := time.now().unix_milli() + timeout_ms

		for time.now().unix_milli() < deadline {
			select {
				r := <-ch {
					result = r
					got_result = true
				}
				else {
					time.sleep(ctx.config.js_poll_ms * time.millisecond)
				}
			}
			if got_result {
				break
			}
		}

		ch.close()

		if !got_result {
			return new_error_detail(.js_timeout, 'JavaScript execution timeout')
		}

		if ctx.config.js_sandbox.enabled && result.len > ctx.config.js_sandbox.max_result_size {
			return new_error_detail(.js_result_too_large, 'Result exceeds maximum size')
		}

		return result
	}
	// timeout_ms <= 0: fire-and-forget; the result channel is dropped with
	// the registration removed by the defer above.
	return ''
}

// validate_js_code checks JS code against sandbox rules
fn validate_js_code(code string, sandbox JsSandboxConfig) ! {
	// Skip validation if sandbox is disabled
	if !sandbox.enabled {
		return
	}

	code_lower := code.to_lower()
	for pattern in sandbox.forbidden_patterns {
		if code_lower.contains(pattern.to_lower()) {
			return new_error_detail(.js_validation_failed, 'Forbidden pattern found: ${pattern}')
		}
	}
}

// run_js executes JavaScript in the frontend and returns the result
pub fn (mut ctx Context) run_js(js_code string, timeout_ms int) !string {
	return ctx.execute_js('', js_code, timeout_ms)
}

// run_js_client executes JavaScript on a specific client
pub fn (mut ctx Context) run_js_client(client_id string, js_code string, timeout_ms int) !string {
	return ctx.execute_js(client_id, js_code, timeout_ms)
}

// post_js executes JavaScript in the frontend fire-and-forget: the result
// (or error) is discarded and the pending callback is unregistered
// immediately. Safe to call from INSIDE route handlers, unlike
// run_js(timeout_ms > 0), which deadlocks there: a handler runs on the
// connection read loop, the very goroutine that would deliver js_result.
pub fn (mut ctx Context) post_js(js_code string) ! {
	ctx.execute_js('', js_code, 0)!
}

// post_js_client is post_js targeting one specific client.
pub fn (mut ctx Context) post_js_client(client_id string, js_code string) ! {
	ctx.execute_js(client_id, js_code, 0)!
}

// =============================================================================
// Client Management
// =============================================================================

// get_clients returns list of connected client IDs
pub fn (mut ctx Context) get_clients() []string {
	ctx.mu.rlock()
	mut ids := []string{}
	for id, _ in ctx.clients {
		ids << id
	}
	ctx.mu.runlock()
	return ids
}

// get_client_count returns the number of connected clients
pub fn (mut ctx Context) get_client_count() int {
	ctx.mu.rlock()
	count := ctx.clients.len
	ctx.mu.runlock()
	return count
}

// get_client returns client info by ID
pub fn (mut ctx Context) get_client(client_id string) ?Client {
	ctx.mu.rlock()
	result := ctx.clients[client_id] or { Client{} }
	ctx.mu.runlock()
	if result.id == '' {
		return none
	}
	return result
}

// close_client disconnects a specific client
pub fn (mut ctx Context) close_client(client_id string) ! {
	ctx.mu.lock()
	client := ctx.clients[client_id] or {
		ctx.mu.unlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.unlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.clients.delete(client_id)
	ctx.mu.unlock()

	conn.close(1000, 'Closed by server')!
	ctx.logger.info('Closed client: ${client_id}')
	ctx.trigger_event(EventType.client_disconnected, client_id, 'Closed by server', {}, none, none,
		none)
}

// =============================================================================
// Broadcasting
// =============================================================================

// client_connections returns the connections of all clients except `except_client_id`
// (pass '' to include everyone). The lock is released before writing.
fn (mut ctx Context) client_connections(except_client_id string) []&websocket.Client {
	ctx.mu.rlock()
	mut connections := []&websocket.Client{}
	for id, client in ctx.clients {
		if id != except_client_id {
			if conn := client.connection {
				connections << conn
			}
		}
	}
	ctx.mu.runlock()
	return connections
}

// broadcast sends a message to all connected clients.
// A write failure on one client (e.g. a stale connection) is skipped
// so the remaining clients still receive the message.
pub fn (mut ctx Context) broadcast(message string) ! {
	for mut conn in ctx.client_connections('') {
		conn.write_string(message) or {
			ctx.logger.debug('broadcast: client write failed, skipped: ${err}')
			continue
		}
	}
}

// broadcast_except sends a message to all clients except one.
// Per-client write failures are skipped, see broadcast().
pub fn (mut ctx Context) broadcast_except(message string, except_client_id string) ! {
	for mut conn in ctx.client_connections(except_client_id) {
		conn.write_string(message) or {
			ctx.logger.debug('broadcast_except: client write failed, skipped: ${err}')
			continue
		}
	}
}

// send_to_client sends a message to a specific client
pub fn (mut ctx Context) send_to_client(client_id string, message string) ! {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.mu.runlock()

	conn.write_string(message)!
}

// =============================================================================
// Heartbeat
// =============================================================================

// ping_client sends a ping to a specific client
pub fn (mut ctx Context) ping_client(client_id string) ! {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.mu.runlock()

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('ping')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	conn.write(json2.encode(cmd).bytes(), .text_frame)!
}

// ping_all_clients sends a ping to all connected clients
pub fn (mut ctx Context) ping_all_clients() {
	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('ping')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	msg := json2.encode(cmd)

	for mut conn in ctx.client_connections('') {
		conn.write(msg.bytes(), .text_frame) or {}
	}
}

// process_client_removals handles client removal requests from the channel
// This should be run in a separate goroutine to serialize removal operations
pub fn (mut ctx Context) process_client_removals() {
	for {
		msg := <-ctx.client_remove_chan or { break }
		ctx.mu.lock()
		existed := msg.client_id in ctx.clients
		if existed {
			ctx.clients.delete(msg.client_id)
			ctx.logger.info('Client removed (${msg.from_msg}): ${msg.client_id}')
		} else {
			ctx.logger.debug('Client already removed (${msg.from_msg}): ${msg.client_id}')
		}
		ctx.mu.unlock()

		// Fire the event AFTER releasing the lock: handlers may call back
		// into Context APIs (broadcast/get_clients/...) and do network IO.
		if existed {
			ctx.trigger_event(EventType.client_disconnected, msg.client_id, 'Client disconnected',
				{}, none, none, none)
		}
	}
}

// =============================================================================
// Configuration Setters
// =============================================================================

// set_window_size sets the window dimensions
pub fn (mut ctx Context) set_window_size(width int, height int) {
	ctx.config.window.width = width
	ctx.config.window.height = height
	if mut s := ctx.display_session {
		s.set_size(width, height)
	}
}

// set_window_position sets the window position
pub fn (mut ctx Context) set_window_position(x int, y int) {
	ctx.config.window.x = x
	ctx.config.window.y = y
	if mut s := ctx.display_session {
		s.set_position(x, y)
	}
}

// set_window_title sets the window title
pub fn (mut ctx Context) set_window_title(title string) {
	ctx.config.window.title = title
	if mut s := ctx.display_session {
		s.set_title(title)
	}
}

// open_window opens an additional display window using the current window
// configuration and security token.
pub fn (mut ctx Context) open_window(html_filename string) ! {
	ctx.open_window_with(html_filename, ctx.config.window) or { return err }
}

// open_window_with opens an additional display window with an explicit window
// configuration. Backend-specific options come from ctx.config.browser.
pub fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) ! {
	cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  window.width
		height: window.height
		x:      window.x
		y:      window.y
		title:  window.title
	}
	sess := ctx.display.spawn(html_filename, cfg)!
	ctx.display_sessions << sess
	if ctx.display_session == none {
		ctx.display_session = sess
	}
}

// set_js_sandbox configures JavaScript execution security
pub fn (mut ctx Context) set_js_sandbox(config JsSandboxConfig) {
	ctx.config.js_sandbox = config
}

// set_browser_config configures browser startup options
pub fn (mut ctx Context) set_browser_config(config BrowserConfig) {
	ctx.config.browser = config
}

// set_rate_limit was removed along with the rate-limiting subsystem:
// a loopback desktop UI has no caller to throttle.

// get_port returns the WebSocket port
pub fn (ctx Context) get_port() u16 {
	return ctx.ws_port
}

// get_token returns the security token
pub fn (ctx Context) get_token() string {
	return ctx.config.token
}

// get_config returns the current configuration
pub fn (ctx Context) get_config() Config {
	return ctx.config
}

// =============================================================================
// Hot Reload Support
// =============================================================================

// trigger_hot_reload sends a reload command to all connected clients.
// Per-client write failures are skipped, see broadcast().
pub fn (mut ctx Context) trigger_hot_reload() ! {
	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('reload')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	msg := json2.encode(cmd)

	for mut conn in ctx.client_connections('') {
		conn.write(msg.bytes(), .text_frame) or {
			ctx.logger.debug('hot reload: client write failed, skipped: ${err}')
			continue
		}
	}
}

// scan_file_mtimes scans directories and returns file modification times
fn scan_file_mtimes(dirs []string) map[string]time.Time {
	mut mtimes := map[string]time.Time{}
	for dir in dirs {
		scan_dir_mtimes(dir, mut mtimes)
	}
	return mtimes
}

// scan_dir_mtimes recursively scans a directory for file modification times
fn scan_dir_mtimes(dir string, mut mtimes map[string]time.Time) {
	files := os.ls(dir) or { return }
	for file in files {
		path := os.join_path(dir, file)
		if os.is_dir(path) {
			// Skip hidden directories and common ignore patterns
			if !file.starts_with('.') && file != 'node_modules' && file != 'dist' && file != 'build' {
				scan_dir_mtimes(path, mut mtimes)
			}
		} else {
			// Only watch relevant file types
			ext := file.all_after_last('.').to_lower()
			if ext in ['html', 'htm', 'css', 'js', 'ts', 'vue', 'svelte', 'json', 'svg', 'png',
				'jpg', 'gif'] {
				info := os.stat(path) or { continue }
				mtimes[path] = time.unix(info.mtime)
			}
		}
	}
}

// has_files_changed compares two mtimes maps and returns true if any file changed
fn has_files_changed(old map[string]time.Time, new map[string]time.Time) bool {
	// Check for new or modified files
	for path, new_time in new {
		old_time := old[path] or { return true } // New file
		if new_time.unix_milli() != old_time.unix_milli() {
			return true
		}
	}
	// Check for deleted files (only if old had more files)
	if old.len > new.len {
		return true
	}
	return false
}
