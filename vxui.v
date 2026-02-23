module vxui

// vxui = browser + htmx/webui + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import net
import net.websocket
import time
import log
import x.json2

// Context is the main struct of vxui
pub struct Context {
mut:
	ws_port u16
	ws      websocket.Server
	routes  map[string]Route
pub mut:
	close_timer int      = 50 // close app after `close_timer` cycles with no browser
	logger      &log.Log = &log.Log{}
}

// init initializes the vxui framework
fn init[T](mut app T) ! {
	app.ws_port = get_free_port()!
	app.ws = startup_ws_server(mut app, .ip, app.ws_port)!
}

// startup_ws_server starts the websocket server at `listen_port`
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut s := websocket.new_server(family, listen_port, '')
	s.set_ping_interval(10)

	s.on_connect(fn [mut app] [T](mut s websocket.ServerClient) !bool {
		app.logger.info('Client connected')
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
	})

	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut app, mut
		s)
	return s
}

// start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections spawns the server in a new thread
fn start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections[T](mut app T, mut ws websocket.Server) {
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

	// Start the browser
	start_browser(html_filename, app.ws_port)!

	app.logger.info('Browser started, waiting for connections on port ${app.ws_port}...')

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
