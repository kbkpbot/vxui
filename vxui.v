module vxui

// vxui = browser + htmx/webui + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import rand
import net
import net.websocket
import time
import os
import x.json2
import log

// Context is the main struct of vxui
pub struct Context {
mut:
	ws_port u16
	ws      websocket.Server
	routes  map[string]Route
pub mut:
	logger &log.Logger = &log.Logger(&log.Log{
	level: .debug
})
}

enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}

const (
	verb_strings = {
		'get':    Verb.get
		'post':   .post
		'put':    .put
		'delete': .delete
		'patch':  .patch
	}
)

struct Route {
	verb []Verb
	path string
}

// start_google_chrome start google chrome and open the `filename`
fn start_google_chrome(filename string) {
	real_path := os.home_dir() + '/.vxui/ChromeProfile'
	cmd := [
		'--user-data-dir=${real_path}',
		'--no-first-run',
		'--disable-gpu',
		'--disable-software-rasterizer',
		'--no-proxy-server',
		'--safe-mode',
		'--disable-extensions',
		'--disable-background-mode',
		'--disable-plugins',
		'--disable-plugins-discovery',
		'--disable-translate',
		'--bwsi',
		'--disable-sync',
		'--disable-sync-preferences',
		//'--force-app-mode',
		//'--new-window',
		//'--app="https://baidu.com"',
		filename,
	]
	if os.fork() == 0 {
		os.execvp('/usr/bin/google-chrome', cmd) or { panic(err) }
	}
	return
}

// get_free_port try to get a free port to websocket listen to
fn get_free_port() u16 {
	mut port := u32(0)
	for {
		// we don't need to be root to access this ports
		port = rand.u32_in_range(1025, 65534) or { panic(err) }
		if mut server := net.listen_tcp(.ip, 'localhost:${port}') {
			server.close() or { panic(err) }
			return u16(port)
		} else {
			continue
		}
	}
	return u16(port)
}

// init vxui framework, it will modify the `js_filename` to the correct vxui_ws_port
fn init[T](mut app T, js_filename string) ! {
	app.ws_port = get_free_port()
	app.ws = startup_ws_server(mut app, .ip, app.ws_port) or { panic(err) }
	vxui_htmx_string := os.read_file(js_filename) or { panic(err) }
	pos := vxui_htmx_string.index('const vxui_ws_port =') or {
		return error('Can\'t find `const vxui_ws_port =` in file ${js_filename}, please check!')
	}

	mut tmp_vxui_file := os.open_file(js_filename, 'w') or { panic(err) }
	tmp_vxui_file.write_string(vxui_htmx_string[..pos]) or { panic(err) }
	tmp_vxui_file.write_string('const vxui_ws_port = ${app.ws_port};\n') or { panic(err) }
	tmp_vxui_file.close()
}

// startup_ws_server start the websocket server at `listen_port`
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut s := websocket.new_server(family, listen_port, '')
	s.set_ping_interval(10)

	s.on_connect(fn [mut app] [T](mut s websocket.ServerClient) !bool {
		// here you can look att the client info and accept or not accept
		// just returning a true/false
		// if s.resource_name != '/' {
		//        panic('unexpected resource name in test')
		//        return false
		//}
		app.logger.info('on_connect done...')
		return true
	})!
	s.on_message(fn [mut app] [T](mut ws websocket.Client, msg &websocket.Message) ! {
		match msg.opcode {
			.pong {
				ws.write_string('pong')!
			}
			else {
				raw_message := json2.fast_raw_decode(msg.payload.bytestr())!
				message := raw_message.as_map()
				app.logger.debug('${message}')
				response := handle_message(mut app, message)!
				ws.write(response.bytes(), msg.opcode)!
			}
		}
	})

	s.on_close(fn (mut ws websocket.Client, code int, reason string) ! {
	})
	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut app, mut
		s)
	return s
}

// start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections spawn to listen
fn start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections[T](mut app T, mut ws websocket.Server) {
	spawn fn [mut ws] () {
		ws.listen() or { panic('websocket server could not listen, err: ${err}') }
	}()
	for ws.get_state() != .open {
		time.sleep(10 * time.millisecond)
	}
}

// handle_message check routes and call the handler
fn handle_message[T](mut app T, message map[string]json2.Any) !string {
	mut tmp := message['path'] or { json2.Null{} }
	mut path := ''
	if tmp is json2.Null {
		return error("Can't parse path [null]")
	} else {
		path = tmp.str()
	}
	if !path.starts_with('/') {
		return error('Can\'t parse path [${path}]')
	}

	tmp = message['verb'] or { json2.Null{} }
	mut verb_str := ''
	mut verb := Verb.get
	if tmp is json2.Null {
		return error("Can't parse verb [null]")
	} else {
		verb_str = tmp.str().to_lower()
	}
	if verb_str !in vxui.verb_strings.keys() {
		return error('Unknown verb [${verb}]')
	} else {
		verb = vxui.verb_strings[verb_str]
	}

	for key, val in app.routes {
		if val.path == path && (verb in val.verb || Verb.any_verb in val.verb) {
			return fire_call[T](mut app, key, message)
		}
	}
	return error('No handler for message ${path} ${verb}')
}

// fire_call call the method
fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
	$for method in T.methods {
		if method.name == method_name {
			if method.return_type == 20 {
				return app.$method(message)
			} else {
				return error('[${method_name}] should return string.')
			}
		}
	}
	return error('Can\'t find method [${method_name}]')
}

// Parsing function attributes for verbs and path.
fn parse_attrs(name string, attrs []string) !([]Verb, string) {
	if attrs.len == 0 {
		return [Verb.any_verb], '/${name}'
	}

	mut verbs := []Verb{}
	mut path := ''

	for x in attrs {
		if x.starts_with('/') {
			if path != '' {
				return error('[${name}]:Can\'t assign multiply path for a route.')
			} else {
				path = x
			}
		} else {
			if x.to_lower() in vxui.verb_strings.keys() {
				verbs << vxui.verb_strings[x.to_lower()]
			} else {
				return error('[${name}]:Unknown verb: ${x}')
			}
		}
	}
	if verbs.len == 0 {
		verbs << Verb.any_verb
	}
	// Make path lowercase for case-insensitive comparisons
	return verbs, path.to_lower()
}

// Generate route structs for an app
fn generate_routes[T](app &T) !map[string]Route {
	// Parsing methods attributes
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

// run open the `html_filename` and modify the `js_filename`(vxui-htmx.js)
pub fn run[T](mut app T, html_filename string, js_filename string) ! {
	init(mut app, js_filename)!
	app.routes = generate_routes(app)!
	start_google_chrome(html_filename)
	mut ws_state := websocket.State.open
	mut client_num := int(0)
	mut close_timer := int(0)
	for {
		ws_state = app.ws.get_state()

		rlock app.ws.server_state {
			client_num = app.ws.server_state.clients.len
		}
		if ws_state == .closed {
			break
		}

		// if we have no client, just wait for sometime, and quit
		// because when page change, it have a small time gap between close old page and open new page
		if client_num == 0 {
			close_timer++
		} else {
			close_timer = 0
		}
		if close_timer > 50 {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	app.ws.free()
}
