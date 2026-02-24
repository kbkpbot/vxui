module vxui

// vxui = browser + htmx/webui + websocket + v

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
	middleware_rejected
	request_timeout
	rate_limited
}

// VxuiErrorDetail represents a structured error with code and details
pub struct VxuiErrorDetail {
pub:
	code    VxuiError
	message string
	details map[string]string
	cause   ?IError // Underlying error that caused this error
}

// str returns the error message
pub fn (e VxuiErrorDetail) str() string {
	mut result := e.message
	if cause := e.cause {
		result += ': ${cause.msg()}'
	}
	return result
}

// err returns this as an IError
pub fn (e VxuiErrorDetail) err() IError {
	return error(e.str())
}

// full_message returns the full error message including cause chain
pub fn (e VxuiErrorDetail) full_message() string {
	mut result := e.message
	if cause := e.cause {
		result += '\n  Caused by: ${cause.msg()}'
	}
	return result
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
	middleware_error
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
	status  int = 200
	headers map[string]string
	body    string
}

// ResponseOption is a function that modifies Response
pub type ResponseOption = fn (mut Response)

// =============================================================================
// Middleware System
// =============================================================================

// MiddlewareResult represents the result of middleware execution
pub enum MiddlewareResult {
	continue_
	stop
	error
}

// MiddlewareContext holds context for middleware execution
pub struct MiddlewareContext {
pub mut:
	request  Request
	response Response
	err      ?VxuiErrorDetail
}

// Middleware is a function that processes requests
pub type Middleware = fn (mut MiddlewareContext) MiddlewareResult

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
	allowed_apis       []string = [// Allowed API patterns
	'document.*',
	'window.location.*',
	'console.*',
	'localStorage.*',
	'sessionStorage.*',
]
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

// WindowConfig holds window configuration
pub struct WindowConfig {
pub mut:
	width       int  = 800
	height      int  = 600
	x           int  = -1 // -1 means center
	y           int  = -1
	min_width   int  = 100
	min_height  int  = 100
	resizable   bool = true
	frameless   bool
	transparent bool
	title       string
}

// BrowserConfig holds browser startup configuration
pub struct BrowserConfig {
pub mut:
	custom_args    []string // Additional custom arguments
	profile_dir    string   // Custom profile directory (empty = default)
	headless       bool     // Run in headless mode (for testing)
	devtools       bool     // Open DevTools automatically
	no_sandbox     bool     // Disable sandbox (for root/CI)
	user_data_dir  string   // Custom user data directory
	preferred_path string   // Preferred browser path (skip detection)
}

// BackoffStrategy for reconnection
pub enum BackoffStrategy {
	constant
	linear
	exponential
	full_jitter
}

// ReconnectConfig holds WebSocket reconnection settings
pub struct ReconnectConfig {
pub mut:
	enabled       bool            = true
	max_attempts  int             = 5
	base_delay_ms int             = 1000
	max_delay_ms  int             = 30000
	strategy      BackoffStrategy = .full_jitter
}

// RateLimitConfig holds rate limiting settings
pub struct RateLimitConfig {
pub mut:
	enabled        bool = true
	max_requests   int  = 100   // Max requests per window
	window_ms      int  = 60000 // Window in milliseconds (1 minute)
	block_duration int  = 30000 // Block duration in ms when limit exceeded
}

// RequestConfig holds per-request settings
pub struct RequestConfig {
pub mut:
	timeout_ms     int = 30000 // Request timeout in milliseconds
	retry_count    int // Number of retries on failure
	retry_delay_ms int = 1000 // Delay between retries
}

// LogConfig holds logging settings
pub struct LogConfig {
pub mut:
	level          log.Level = .info
	output         string    = 'stderr' // 'stderr', 'stdout', or file path
	max_file_size  int       = 10485760 // 10MB
	rotate_files   int       = 5
	show_timestamp bool      = true
	show_level     bool      = true
}

// Config is the unified configuration for vxui
pub struct Config {
pub mut:
	// Application settings
	app_name string = 'vxui-app'

	// Development settings
	dev DevConfig // Development mode settings

	// Connection settings
	close_timer_ms      int = 5000  // Close app after N ms with no browser
	ws_ping_interval_ms int = 30000 // WebSocket ping interval
	ws_pong_timeout_ms  int = 60000 // Timeout for pong response
	reconnect           ReconnectConfig // Reconnection settings

	// Security settings
	token        string // Security token (auto-generated if empty)
	require_auth bool = true // Require token authentication

	// Client settings
	multi_client bool // Allow multiple browser clients
	max_clients  int = 10 // Maximum concurrent clients (0 = unlimited)
	rate_limit   RateLimitConfig // Rate limiting settings

	// JavaScript execution settings
	js_timeout int = 5000 // Default timeout for run_js()
	js_poll_ms int = 10   // Polling interval for JS result
	js_sandbox JsSandboxConfig // JS execution sandbox

	// Request settings
	request RequestConfig // Per-request configuration

	// Window settings
	window WindowConfig

	// Browser settings
	browser BrowserConfig

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
pub struct Context {
mut:
	ws_port        u16
	ws             websocket.Server
	routes         map[string]Route
	clients        map[string]Client
	mu             sync.RwMutex
	js_callbacks   map[string]chan string
	event_handlers map[EventType][]EventHandler
	middlewares    []Middleware
	rate_counters  map[string]RateCounter
pub mut:
	config Config
	logger &log.Log = &log.Log{}
	// Backward compatibility aliases - these delegate to config
	// Deprecated: Use config.token directly
	token string @[deprecated: 'Use config.token instead'; deprecated_after: 'v0.5.0']
	// Deprecated: Use config.multi_client directly
	multi_client bool @[deprecated: 'Use config.multi_client instead'; deprecated_after: 'v0.5.0']
}

// RateCounter tracks request rates per client
struct RateCounter {
mut:
	count         int
	window_start  time.Time
	blocked_until time.Time
}

// =============================================================================
// Initialization
// =============================================================================

// init initializes the vxui framework
fn init[T](mut app T) ! {
	app.ws_port = get_free_port()!

	// Generate security token if not set
	if app.config.token == '' {
		app.config.token = generate_token()
	}
	// Backward compatibility
	app.token = app.config.token

	// Initialize maps
	app.clients = map[string]Client{}
	app.js_callbacks = map[string]chan string{}
	app.event_handlers = map[EventType][]EventHandler{}
	app.middlewares = []Middleware{}
	app.rate_counters = map[string]RateCounter{}

	// Setup logger
	app.logger.set_level(app.config.log.level)

	app.ws = startup_ws_server(mut app, .ip, app.ws_port)!
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

// startup_ws_server starts the websocket server at `listen_port`
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut s := websocket.new_server(family, listen_port, '')
	s.set_ping_interval(30)

	s.on_connect(fn [mut app] [T](mut s websocket.ServerClient) !bool {
		app.trigger_event(EventType.client_connecting, '', 'Client connecting...', {},
			none, none, none)

		// Check client limit
		app.mu.rlock()
		client_count := app.clients.len
		app.mu.runlock()

		if !app.config.multi_client && client_count > 0 {
			app.logger.warn('Rejecting connection: multi_client is disabled')
			return false
		}

		if app.config.max_clients > 0 && client_count >= app.config.max_clients {
			app.logger.warn('Rejecting connection: max_clients limit reached')
			return false
		}

		return true
	})!

	s.on_message(fn [mut app] [T](mut ws websocket.Client, msg &websocket.Message) ! {
		match msg.opcode {
			.pong {
				ws.write_string('pong')!
			}
			else {
				raw_message := json2.decode[json2.Any](msg.payload.bytestr())!
				message := raw_message.as_map()
				app.logger.debug('Received message: ${message}')

				// Handle authentication
				if cmd := message['cmd'] {
					if cmd.str() == 'auth' {
						handle_auth(mut app, mut ws, message) or {
							auth_err := new_error_detail(.auth_failed, 'Auth failed: ${err}')
							app.logger.error(auth_err.message)
							app.trigger_event(EventType.error, '', auth_err.message, message,
								none, none, auth_err)
							ws.close(1008, 'Authentication failed')!
						}
						return
					}
					if cmd.str() == 'js_result' {
						handle_js_result(mut app, message)
						return
					}
					if cmd.str() == 'pong' {
						handle_pong(mut app, message)
						return
					}
					if cmd.str() == 'client_close' {
						// Client is closing, remove it immediately
						client_id := message['client_id'] or { json2.Any('') }.str()
						app.mu.lock()
						app.clients.delete(client_id)
						app.mu.unlock()
						app.logger.info('Client closed: ${client_id}')
						app.trigger_event(EventType.client_disconnected, client_id, 'Client closed',
							message, none, none, none)
						return
					}
				}

				// Verify token for regular messages
				if client_token := message['token'] {
					if client_token.str() != app.config.token {
						app.logger.warn('Invalid token from client')
						ws.close(1008, 'Invalid token')!
						return
					}
				}

				if rpc_id := message['rpcID'] {
					// Get client_id for rate limiting
					client_id := find_client_id_by_connection(mut app, ws)

					// Check rate limit
					if app.config.rate_limit.enabled && client_id != '' {
						if !app.check_rate_limit(client_id) {
							app.trigger_event(EventType.middleware_error, client_id, 'Rate limit exceeded',
								message, none, none, new_error_detail(.rate_limited, 'Rate limit exceeded'))
							err_resp := '{"rpcID":"${rpc_id.i64()}", "error":"rate_limited", "message":"Rate limit exceeded"}'
							ws.write(err_resp.bytes(), .text_frame)!
							return
						}
					}

					// Build type-safe request
					req := build_request(message, client_id)

					// Execute middlewares
					mut ctx := MiddlewareContext{
						request:  req
						response: Response{}
					}

					mut middleware_passed := true
					for middleware in app.middlewares {
						result := middleware(mut ctx)
						if result != .continue_ {
							middleware_passed = false
							if result == .error {
								app.trigger_event(EventType.middleware_error, client_id,
									'Middleware rejected', message, req, ctx.response,
									ctx.err)
							}
							break
						}
					}

					if !middleware_passed {
						err_resp := '{"rpcID":"${rpc_id.i64()}", "error":"middleware_rejected"}'
						ws.write(err_resp.bytes(), .text_frame)!
						return
					}

					// Trigger before_request event
					app.trigger_event(EventType.before_request, client_id, '', message,
						req, none, none)

					// Handle message
					response := handle_request(mut app, ctx.request, message)!

					// Trigger after_request event
					app.trigger_event(EventType.after_request, client_id, '', message,
						req, response, none)

					json_response := '{"rpcID":"${rpc_id.i64()}", "data":${json2.encode(response.body)}}'
					ws.write(json_response.bytes(), .text_frame)!
				}
			}
		}
	})

	s.on_close(fn [mut app] [T](mut ws websocket.Client, code int, reason string) ! {
		app.logger.info('Client disconnected: code=${code}, reason=${reason}')

		app.mu.lock()
		mut client_id_to_remove := ''
		for id, client in app.clients {
			if client.connection or { unsafe { nil } } == ws {
				client_id_to_remove = id
				break
			}
		}
		// Only delete if client still exists (may have been removed by client_close message)
		if client_id_to_remove != '' && client_id_to_remove in app.clients {
			app.clients.delete(client_id_to_remove)
			app.logger.info('Removed client: ${client_id_to_remove}')
			app.trigger_event(EventType.client_disconnected, client_id_to_remove, 'Client disconnected',
				{}, none, none, none)
		}
		app.mu.unlock()
	})

	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut s)
	return s
}

// find_client_id_by_connection finds client ID by WebSocket connection
fn find_client_id_by_connection[T](mut app T, ws websocket.Client) string {
	app.mu.rlock()

	for id, client in app.clients {
		if client.connection or { unsafe { nil } } == ws {
			app.mu.runlock()
			return id
		}
	}
	app.mu.runlock()
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

// check_rate_limit checks if client is within rate limits
fn (mut ctx Context) check_rate_limit(client_id string) bool {
	if ctx.config.rate_limit.max_requests <= 0 {
		return true
	}

	ctx.mu.lock()

	now := time.now()
	mut counter := ctx.rate_counters[client_id] or { RateCounter{} }

	// Check if blocked
	if now.unix_milli() < counter.blocked_until.unix_milli() {
		ctx.mu.unlock()
		return false
	}

	// Reset window if expired
	if now.unix_milli() - counter.window_start.unix_milli() > ctx.config.rate_limit.window_ms {
		counter.count = 0
		counter.window_start = now
	}

	counter.count++

	// Check limit
	if counter.count > ctx.config.rate_limit.max_requests {
		counter.blocked_until = now.add(ctx.config.rate_limit.block_duration * time.millisecond)
		ctx.rate_counters[client_id] = counter
		ctx.mu.unlock()
		return false
	}

	ctx.rate_counters[client_id] = counter
	ctx.mu.unlock()
	return true
}

// handle_auth processes client authentication
fn handle_auth[T](mut app T, mut ws websocket.Client, message map[string]json2.Any) ! {
	client_token := message['token'] or { json2.Null{} }

	if client_token.str() != app.config.token {
		return new_error_detail(.auth_invalid_token, 'Invalid token').err()
	}

	client_id := generate_client_id()

	app.mu.lock()
	app.clients[client_id] = Client{
		id:            client_id
		token:         app.config.token
		connected:     time.now()
		last_ping:     time.now()
		request_count: 0
		connection:    ws
	}
	app.mu.unlock()

	app.logger.info('Client authenticated: ${client_id}')
	app.trigger_event(EventType.client_connected, client_id, 'Client authenticated', {},
		none, none, none)

	mut response := map[string]json2.Any{}
	response['cmd'] = json2.Any('auth_ok')
	response['client_id'] = json2.Any(client_id)
	if app.config.js_sandbox.enabled {
		response['js_sandbox'] = json2.encode(app.config.js_sandbox)
	}
	ws.write(json2.encode(response).bytes(), .text_frame)!
}

// handle_pong processes heartbeat pong responses
fn handle_pong[T](mut app T, message map[string]json2.Any) {
	client_id := message['client_id'] or { json2.Any('') }.str()
	app.mu.lock()
	if client := app.clients[client_id] {
		mut updated_client := client
		updated_client.last_ping = time.now()
		app.clients[client_id] = updated_client
	}
	app.mu.unlock()
	app.logger.debug('Received pong from client: ${client_id}')
}

// handle_js_result processes JavaScript execution results
fn handle_js_result[T](mut app T, message map[string]json2.Any) {
	js_id := message['js_id'] or { return }.str()
	result := message['result'] or { json2.Any('') }.str()

	app.mu.lock()
	if ch := app.js_callbacks[js_id] {
		ch <- result
		app.js_callbacks.delete(js_id)
	}
	app.mu.unlock()
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

	if handlers := ctx.event_handlers[event_type] {
		for handler in handlers {
			handler(event)
		}
	}
}

// on_event registers an event handler
pub fn (mut ctx Context) on_event(event_type EventType, handler EventHandler) {
	if event_type !in ctx.event_handlers {
		ctx.event_handlers[event_type] = []
	}
	ctx.event_handlers[event_type] << handler
}

// =============================================================================
// Middleware System
// =============================================================================

// use adds a middleware to the chain
pub fn (mut ctx Context) use(middleware Middleware) {
	ctx.middlewares << middleware
}

// use_logger adds a logging middleware
pub fn (mut ctx Context) use_logger() {
	ctx.use(fn (mut mctx MiddlewareContext) MiddlewareResult {
		t := time.now()
		println('[${t.year}-${t.month:02}-${t.day:02} ${t.hour:02}:${t.minute:02}:${t.second:02}] ${mctx.request.verb} ${mctx.request.path}')
		return .continue_
	})
}

// use_auth adds an authentication middleware
pub fn (mut ctx Context) use_auth(check_fn fn (string) bool) {
	ctx.use(fn [check_fn] (mut mctx MiddlewareContext) MiddlewareResult {
		if mctx.request.client_id == '' {
			mctx.err = new_error_detail(.auth_failed, 'No client ID')
			return .error
		}
		if !check_fn(mctx.request.client_id) {
			mctx.err = new_error_detail(.auth_failed, 'Authentication failed')
			return .stop
		}
		return .continue_
	})
}

// =============================================================================
// Route Handling
// =============================================================================

// handle_request processes a request through routes
fn handle_request[T](mut app T, req Request, message map[string]json2.Any) !Response {
	for key, val in app.routes {
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
pub fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
	$for method in T.methods {
		if method.name == method_name {
			$if method.return_type is string {
				return app.$method(message)
			} $else {
				return error('[${method_name}] should return string.(${method.return_type})')
			}
		}
	}
	return error("Can't find method [${method_name}]")
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
				return error("[${name}]:Can't assign multiply path for a route.")
			} else {
				path = x
			}
		} else {
			if x.to_lower() in verb_strings.keys() {
				verbs << verb_strings[x.to_lower()]
			} else {
				return error('[${name}]:Unknown verb: ${x}')
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
		verbs, route_path := parse_attrs(method.name, method.attrs) or {
			return error('error parsing method attributes: ${err}')
		}
		routes[method.name] = Route{
			verb: verbs
			path: route_path
		}
	}
	return routes
}

// =============================================================================
// Main Entry Points
// =============================================================================

// run opens the `html_filename` in browser and starts the event loop
pub fn run[T](mut app T, html_filename string) ! {
	app.trigger_event(EventType.before_start, '', 'Starting application', {}, none, none,
		none)

	init(mut app)!

	app.routes = generate_routes(app)!

	// Sync backward compatibility fields
	app.token = app.config.token
	app.multi_client = app.config.multi_client

	// Apply dev mode settings
	if app.config.dev.enabled {
		app.config.browser.devtools = app.config.dev.auto_devtools
		app.logger.info('Development mode enabled')
	}

	start_browser_with_config(html_filename, app.ws_port, app.config.token, app.config.window,
		app.config.browser)!

	app.logger.info('Browser started, waiting for connections on port ${app.ws_port}...')
	app.logger.debug('Token: ${app.config.token}')

	app.trigger_event(EventType.after_start, '', 'Application started', {}, none, none,
		none)

	// Hot reload: track file modification times
	mut file_mtimes := map[string]time.Time{}
	mut watch_dirs := app.config.dev.watch_dirs.clone()
	if watch_dirs.len == 0 {
		// Default to the directory containing the HTML file
		watch_dirs << os.dir(os.abs_path(html_filename))
	}

	if app.config.dev.enabled && app.config.dev.hot_reload {
		app.logger.info('Hot reload watching: ${watch_dirs}')
		file_mtimes = scan_file_mtimes(watch_dirs)
	}

	mut ws_state := websocket.State.open

	mut last_client_time := time.now()

	mut last_hot_reload_check := time.now()

	mut last_ping_time := time.now()

	mut had_clients := false // Track if we ever had clients

	for {
		ws_state = app.ws.get_state()

		app.mu.rlock()

		client_count := app.clients.len

		app.mu.runlock()

		if ws_state == .closed {
			app.logger.info('WebSocket server closed')

			break
		}

		if client_count == 0 {
			// If we had clients before and now none, exit immediately

			if had_clients {
				app.logger.info('All clients disconnected, shutting down')

				break
			}

			// Never had clients, wait for timeout

			elapsed_ms := time.now().unix_milli() - last_client_time.unix_milli()

			if elapsed_ms > app.config.close_timer_ms {
				app.logger.info('No clients connected for ${app.config.close_timer_ms}ms, shutting down')

				break
			}
		} else {
			had_clients = true

			last_client_time = time.now()
		}

		app.check_client_timeouts()

		// Heartbeat: send ping to all clients periodically

		now := time.now()

		if client_count > 0
			&& now.unix_milli() - last_ping_time.unix_milli() >= app.config.ws_ping_interval_ms {
			last_ping_time = now

			app.ping_all_clients()

			app.logger.debug('Sent heartbeat ping to all clients')
		}

		// Hot reload check

		if app.config.dev.enabled && app.config.dev.hot_reload && client_count > 0 {
			if now.unix_milli() - last_hot_reload_check.unix_milli() >= app.config.dev.watch_ms {
				last_hot_reload_check = now
				new_mtimes := scan_file_mtimes(watch_dirs)
				if has_files_changed(file_mtimes, new_mtimes) {
					app.logger.info('Files changed, triggering hot reload')
					file_mtimes = new_mtimes.clone()
					app.trigger_hot_reload() or { app.logger.warn('Hot reload failed: ${err}') }
				}
			}
		}

		time.sleep(10 * time.millisecond)
	}

	app.trigger_event(EventType.before_shutdown, '', 'Application shutting down', {},
		none, none, none)

	app.ws.free()
	app.logger.info('vxui shutdown complete')
}

// run_with_config runs the app with unified configuration
pub fn run_with_config[T](mut app T, html_filename string, config Config) ! {
	// Apply configuration
	app.config = config
	// Sync backward compatibility fields
	app.token = config.token
	app.multi_client = config.multi_client

	run(mut app, html_filename)!
}

// check_client_timeouts removes clients that haven't responded to pings
fn (mut ctx Context) check_client_timeouts() {
	ctx.mu.lock()
	mut stale_clients := []string{}
	now := time.now()

	for id, client in ctx.clients {
		if now.unix_milli() - client.last_ping.unix_milli() > 60000 {
			stale_clients << id
		}
	}

	for id in stale_clients {
		ctx.clients.delete(id)
		ctx.logger.warn('Removed stale client: ${id}')
		ctx.trigger_event(EventType.client_disconnected, id, 'Client timeout', {}, none,
			none, none)
	}
	ctx.mu.unlock()
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

// run_embedded is a convenience function for running with embedded HTML
pub fn run_embedded[T](mut app T, html_data []u8, filename string) ! {
	temp_dir := os.join_path(os.temp_dir(), 'vxui_${os.now_unix()}')
	os.mkdir_all(temp_dir)!

	html_path := os.join_path(temp_dir, filename)
	os.write_file(html_path, html_data.bytestr())!

	run(mut app, html_path) or {
		os.rmdir_all(temp_dir) or {}
		return err
	}

	os.rmdir_all(temp_dir) or {}
}

// =============================================================================
// JavaScript Execution
// =============================================================================

// execute_js is the internal implementation for JS execution
fn (mut ctx Context) execute_js(client_id string, js_code string, timeout_ms int) !string {
	ctx.mu.rlock()
	if ctx.clients.len == 0 {
		ctx.mu.runlock()
		return new_error_detail(.no_clients, 'No connected clients').err()
	}

	mut client_conn := &websocket.Client(unsafe { nil })
	if client_id == '' {
		for _, c in ctx.clients {
			client_conn = c.connection or { unsafe { nil } }
			break
		}
	} else {
		client := ctx.clients[client_id] or {
			ctx.mu.runlock()
			return new_error_detail(.client_not_found, 'Client not found: ${client_id}').err()
		}
		client_conn = client.connection or { unsafe { nil } }
	}
	ctx.mu.runlock()

	if client_conn == unsafe { nil } {
		return new_error_detail(.no_valid_connection, 'No valid client connection').err()
	}

	if ctx.config.js_sandbox.enabled {
		validate_js_code(js_code, ctx.config.js_sandbox) or {
			return new_error_detail(.js_validation_failed, 'JS validation failed: ${err}').err()
		}
	}

	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()

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

		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
		ch.close()

		if !got_result {
			return new_error_detail(.js_timeout, 'JavaScript execution timeout').err()
		}

		if ctx.config.js_sandbox.enabled && result.len > ctx.config.js_sandbox.max_result_size {
			return new_error_detail(.js_result_too_large, 'Result exceeds maximum size').err()
		}

		return result
	}
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
			return new_error_detail(.js_validation_failed, 'Forbidden pattern found: ${pattern}').err()
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
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}').err()
	}
	mut conn := client.connection or {
		ctx.mu.unlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection').err()
	}

	ctx.clients.delete(client_id)
	ctx.mu.unlock()

	conn.close(1000, 'Closed by server')!
	ctx.logger.info('Closed client: ${client_id}')
	ctx.trigger_event(EventType.client_disconnected, client_id, 'Closed by server', {},
		none, none, none)
}

// =============================================================================
// Broadcasting
// =============================================================================

// broadcast sends a message to all connected clients
pub fn (mut ctx Context) broadcast(message string) ! {
	ctx.mu.rlock()
	mut connections := []&websocket.Client{}
	for _, client in ctx.clients {
		if conn := client.connection {
			connections << conn
		}
	}
	ctx.mu.runlock()

	for mut conn in connections {
		conn.write_string(message)!
	}
}

// broadcast_except sends a message to all clients except one
pub fn (mut ctx Context) broadcast_except(message string, except_client_id string) ! {
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

	for mut conn in connections {
		conn.write_string(message)!
	}
}

// send_to_client sends a message to a specific client
pub fn (mut ctx Context) send_to_client(client_id string, message string) ! {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}').err()
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection').err()
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
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}').err()
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection').err()
	}

	ctx.mu.runlock()

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('ping')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	conn.write(json2.encode(cmd).bytes(), .text_frame)!
}

// ping_all_clients sends a ping to all connected clients
pub fn (mut ctx Context) ping_all_clients() {
	ctx.mu.rlock()
	mut connections := []&websocket.Client{}
	for _, client in ctx.clients {
		if conn := client.connection {
			connections << conn
		}
	}
	ctx.mu.runlock()

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('ping')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	msg := json2.encode(cmd)

	for mut conn in connections {
		conn.write(msg.bytes(), .text_frame) or {}
	}
}

// =============================================================================
// Configuration Setters
// =============================================================================

// set_window_size sets the window dimensions
pub fn (mut ctx Context) set_window_size(width int, height int) {
	ctx.config.window.width = width
	ctx.config.window.height = height
}

// set_window_position sets the window position
pub fn (mut ctx Context) set_window_position(x int, y int) {
	ctx.config.window.x = x
	ctx.config.window.y = y
}

// set_window_title sets the window title
pub fn (mut ctx Context) set_window_title(title string) {
	ctx.config.window.title = title
}

// set_resizable sets whether the window can be resized
pub fn (mut ctx Context) set_resizable(resizable bool) {
	ctx.config.window.resizable = resizable
}

// set_js_sandbox configures JavaScript execution security
pub fn (mut ctx Context) set_js_sandbox(config JsSandboxConfig) {
	ctx.config.js_sandbox = config
}

// set_browser_config configures browser startup options
pub fn (mut ctx Context) set_browser_config(config BrowserConfig) {
	ctx.config.browser = config
}

// set_rate_limit configures rate limiting
pub fn (mut ctx Context) set_rate_limit(config RateLimitConfig) {
	ctx.config.rate_limit = config
}

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

// trigger_hot_reload sends a reload command to all connected clients
pub fn (mut ctx Context) trigger_hot_reload() ! {
	ctx.mu.rlock()
	mut connections := []&websocket.Client{}
	for _, client in ctx.clients {
		if conn := client.connection {
			connections << conn
		}
	}
	ctx.mu.runlock()

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('reload')
	cmd['timestamp'] = json2.Any(time.now().unix_milli())
	msg := json2.encode(cmd)

	for mut conn in connections {
		conn.write(msg.bytes(), .text_frame)!
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
