module vxui

// vxui = browser + htmx/webui + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import net
import net.websocket
import time
import log
import x.json2
import rand
import sync

// Client represents a connected browser client
pub struct Client {
pub:
	id        string
	token     string
	connected time.Time
pub mut:
	connection &websocket.Client = unsafe { nil }
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

// Config holds vxui runtime configuration
pub struct Config {
pub mut:
	// Connection settings
	close_timer         int = 50   // Close app after N cycles with no browser (each cycle is ~1ms)
	ws_ping_interval    int = 10   // WebSocket ping interval in seconds
	
	// Security settings
	token               string // Security token (auto-generated if empty)
	require_auth        bool = true // Require token authentication
	
	// Client settings
	multi_client        bool   // Allow multiple browser clients
	max_clients         int = 10 // Maximum number of concurrent clients (0 = unlimited)
	
	// JavaScript execution settings
	js_timeout_default  int = 5000 // Default timeout for run_js() in milliseconds
	js_poll_interval    int = 10   // Polling interval for JS result in milliseconds
	
	// Window settings
	window              WindowConfig
}

// Context is the main struct of vxui
pub struct Context {
mut:
	ws_port      u16
	ws           websocket.Server
	routes       map[string]Route
	clients      map[string]Client // client_id -> Client
	mu           sync.RwMutex
	js_callbacks map[string]chan string // JS execution callbacks
pub mut:
	close_timer  int      = 50 // close app after `close_timer` cycles with no browser
	logger       &log.Log = &log.Log{}
	token        string // Security token for client authentication
	multi_client bool   // Allow multiple clients
	window       WindowConfig
}

// init initializes the vxui framework
fn init[T](mut app T) ! {
	app.ws_port = get_free_port()!
	// Generate security token if not set
	if app.token == '' {
		app.token = generate_token()
	}
	// Initialize maps
	app.clients = map[string]Client{}
	app.js_callbacks = map[string]chan string{}
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

// startup_ws_server starts the websocket server at `listen_port`
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut s := websocket.new_server(family, listen_port, '')
	s.set_ping_interval(10)

	s.on_connect(fn [mut app] [T](mut s websocket.ServerClient) !bool {
		app.logger.info('Client connecting...')

		// Check if multi-client is disabled and we already have a client
		app.mu.rlock()
		client_count := app.clients.len
		app.mu.runlock()

		if !app.multi_client && client_count > 0 {
			app.logger.warn('Rejecting connection: multi_client is disabled')
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
							app.logger.error('Auth failed: ${err}')
							ws.close(1008, 'Authentication failed')!
						}
						return
					}
					if cmd.str() == 'js_result' {
						// JavaScript execution result from frontend
						handle_js_result(mut app, message)
						return
					}
				}

				// Verify token for regular messages
				if client_token := message['token'] {
					if client_token.str() != app.token {
						app.logger.warn('Invalid token from client')
						ws.close(1008, 'Invalid token')!
						return
					}
				}

				if rpc_id := message['rpcID'] {
					response := handle_message(mut app, message)!
					json_response := '{"rpcID":"${rpc_id.i64()}", "data":${json2.encode(response)}}'
					ws.write(json_response.bytes(), msg.opcode)!
				}
			}
		}
	})

	s.on_close(fn [mut app] [T](mut ws websocket.Client, code int, reason string) ! {
		app.logger.info('Client disconnected: code=${code}, reason=${reason}')
		// Remove client from map
		app.mu.lock()
		mut client_id_to_remove := ''
		for id, client in app.clients {
			if client.connection == ws {
				client_id_to_remove = id
				break
			}
		}
		if client_id_to_remove != '' {
			app.clients.delete(client_id_to_remove)
			app.logger.info('Removed client: ${client_id_to_remove}')
		}
		app.mu.unlock()
	})

	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut s)
	return s
}

// handle_auth processes client authentication
fn handle_auth[T](mut app T, mut ws websocket.Client, message map[string]json2.Any) ! {
	client_token := message['token'] or { json2.Null{} }

	// Verify token
	if client_token.str() != app.token {
		return error('Invalid token')
	}

	// Generate client ID
	client_id := generate_client_id()

	// Register client
	app.mu.lock()
	app.clients[client_id] = Client{
		id:         client_id
		token:      app.token
		connected:  time.now()
		connection: ws
	}
	app.mu.unlock()

	app.logger.info('Client authenticated: ${client_id}')

	// Send auth success response
	mut response := map[string]json2.Any{}
	response['cmd'] = json2.Any('auth_ok')
	response['client_id'] = json2.Any(client_id)
	ws.write(json2.encode(response).bytes(), .text_frame)!
}

// handle_js_result processes JavaScript execution results from frontend
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

// start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections spawns the server in a new thread
fn start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut ws websocket.Server) {
	spawn fn [mut ws] () {
		ws.listen() or { eprintln('WebSocket server error: ${err}') }
	}()

	// Wait for server to be ready (with timeout)
	mut attempts := 0
	max_attempts := 500 // 5 seconds timeout (500 * 10ms)
	for ws.get_state() != .open && attempts < max_attempts {
		time.sleep(10 * time.millisecond)
		attempts++
	}
}

// run opens the `html_filename` in browser and starts the event loop
pub fn run[T](mut app T, html_filename string) ! {
	// Initialize the framework
	init(mut app)!

	// Generate routes from method attributes
	app.routes = generate_routes(app)!

	// Start the browser with token
	start_browser_with_token(html_filename, app.ws_port, app.token, app.window)!

	app.logger.info('Browser started, waiting for connections on port ${app.ws_port}...')
	app.logger.debug('Token: ${app.token}')

	mut ws_state := websocket.State.open
	mut client_num := int(0)
	mut close_timer := int(0)

	// Main event loop
	for {
		ws_state = app.ws.get_state()

		rlock app.ws.server_state {
			client_num = app.ws.server_state.clients.len
		}

		if ws_state == .closed {
			app.logger.info('WebSocket server closed')
			break
		}

		// If we have no client, just wait for sometime, and quit
		// because when page change, it have a small time gap between close old page and open new page
		if client_num == 0 {
			close_timer++
		} else {
			close_timer = 0
		}

		if close_timer > app.close_timer {
			app.logger.info('No clients connected for ${app.close_timer} cycles, shutting down')
			break
		}

		time.sleep(1 * time.millisecond)
	}

	// Cleanup
	app.ws.free()
	app.logger.info('vxui shutdown complete')
}

// run_js executes JavaScript in the frontend and returns the result
// timeout is in milliseconds, 0 means no wait
pub fn (mut ctx Context) run_js(js_code string, timeout_ms int) !string {
	ctx.mu.rlock()
	if ctx.clients.len == 0 {
		ctx.mu.runlock()
		return error('No connected clients')
	}

	// Get first client
	mut client_conn := &websocket.Client(unsafe { nil })
	for _, c in ctx.clients {
		client_conn = c.connection
		break
	}
	ctx.mu.runlock()

	// Generate unique JS ID
	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	// Create response channel
	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()

	// Send JS command to frontend
	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('run_js')
	cmd['js_id'] = json2.Any(js_id)
	cmd['script'] = json2.Any(js_code)
	client_conn.write(json2.encode(cmd).bytes(), .text_frame)!

	// Wait for result with polling
	if timeout_ms > 0 {
		mut result := ''
		mut got_result := false
		deadline := time.now().unix_milli() + timeout_ms

		for time.now().unix_milli() < deadline {
			// Try to receive from channel (non-blocking)
			select {
				r := <-ch {
					result = r
					got_result = true
				}
				else {
					time.sleep(10 * time.millisecond)
				}
			}
			if got_result {
				break
			}
		}

		// Cleanup: remove from map and close channel
		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
		ch.close()

		if !got_result {
			return error('JavaScript execution timeout')
		}
		return result
	}
	return ''
}

// run_js_client executes JavaScript on a specific client
pub fn (mut ctx Context) run_js_client(client_id string, js_code string, timeout_ms int) !string {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return error('Client not found: ${client_id}')
	}
	mut client_conn := client.connection
	ctx.mu.runlock()

	js_id := '${time.now().unix_milli()}-${rand.u32()}'
	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('run_js')
	cmd['js_id'] = json2.Any(js_id)
	cmd['script'] = json2.Any(js_code)
	client_conn.write(json2.encode(cmd).bytes(), .text_frame)!

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
					time.sleep(10 * time.millisecond)
				}
			}
			if got_result {
				break
			}
		}

		// Cleanup: remove from map and close channel
		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
		ch.close()

		if !got_result {
			return error('JavaScript execution timeout')
		}
		return result
	}
	return ''
}

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

// close_client disconnects a specific client
pub fn (mut ctx Context) close_client(client_id string) ! {
	ctx.mu.lock()
	client := ctx.clients[client_id] or {
		ctx.mu.unlock()
		return error('Client not found: ${client_id}')
	}
	mut conn := client.connection
	ctx.clients.delete(client_id)
	ctx.mu.unlock()

	conn.close(1000, 'Closed by server')!
	ctx.logger.info('Closed client: ${client_id}')
}

// broadcast sends a message to all connected clients
pub fn (mut ctx Context) broadcast(message string) ! {
	ctx.mu.rlock()
	// Collect connections first to avoid holding lock during IO
	mut connections := []&websocket.Client{}
	for _, client in ctx.clients {
		connections << client.connection
	}
	ctx.mu.runlock()

	for mut conn in connections {
		conn.write_string(message)!
	}
}

// set_window_size sets the window dimensions
pub fn (mut ctx Context) set_window_size(width int, height int) {
	ctx.window.width = width
	ctx.window.height = height
}

// set_window_position sets the window position (-1 for center)
pub fn (mut ctx Context) set_window_position(x int, y int) {
	ctx.window.x = x
	ctx.window.y = y
}

// set_window_title sets the window title
pub fn (mut ctx Context) set_window_title(title string) {
	ctx.window.title = title
}

// set_resizable sets whether the window can be resized
pub fn (mut ctx Context) set_resizable(resizable bool) {
	ctx.window.resizable = resizable
}

// get_port returns the WebSocket port
pub fn (ctx Context) get_port() u16 {
	return ctx.ws_port
}

// get_token returns the security token
pub fn (ctx Context) get_token() string {
	return ctx.token
}
