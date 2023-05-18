module vxui
/*
	vxui = browser + htmx/webui + websocket + v
	vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
*/
import rand
import net
import net.websocket
import time
import os

// VXUI is the main struct of vxui
pub struct VXUI {
mut:
	ws_port u16
	ws      websocket.Server
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
		'--force-app-mode',
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
fn (mut vv VXUI) init(js_filename string) {
	vv.ws_port = get_free_port()
	vv.ws = startup_ws_server(.ip, vv.ws_port) or { panic(err) }
	vxui_htmx_string := os.read_file(js_filename) or { panic(err) }
	pos := vxui_htmx_string.index('const vxui_ws_port =') or {
		println('Can\'t find `const vxui_ws_port =` in file ${js_filename}, please check!')
		panic(err)
	}

	mut tmp_vxui_file := os.open_file(js_filename, 'w') or { panic(err) }
	tmp_vxui_file.write_string(vxui_htmx_string[..pos]) or { panic(err) }
	tmp_vxui_file.write_string('const vxui_ws_port = ${vv.ws_port};\n') or { panic(err) }
	tmp_vxui_file.close()
	println('VXUI init at ws_port=${vv.ws_port}')
}

// startup_ws_server start the websocket server at `listen_port`
fn startup_ws_server(family net.AddrFamily, listen_port int) !&websocket.Server {
	println('> ws_server family:${family} | listen_port: ${listen_port}')
	mut s := websocket.new_server(family, listen_port, '')
	s.set_ping_interval(10)

	s.on_connect(fn (mut s websocket.ServerClient) !bool {
		// here you can look att the client info and accept or not accept
		// just returning a true/false
		// if s.resource_name != '/' {
		//        panic('unexpected resource name in test')
		//        return false
		//}
		println('on_connect done...')
		return true
	})!
	s.on_message(fn (mut ws websocket.Client, msg &websocket.Message) ! {
		match msg.opcode {
			.pong {
				ws.write_string('pong')!
			}
			else {
				println('${msg.payload.bytestr()}')
				response := '<div id="idMessage" hx-swap-oob="true">hello world</div>'
				ws.write(response.bytes(), msg.opcode)!
				// ws.write(msg.payload, msg.opcode)!
			}
		}
	})

	s.on_close(fn (mut ws websocket.Client, code int, reason string) ! {
	})
	start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut s)
	println('> start_server finished')
	return s
}

// start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections spawn to listen
fn start_server_in_thread_and_wait_till_it_is_ready_to_accept_connections(mut ws websocket.Server) {
	println('-----------------------------------------------------------------------------')
	spawn fn [mut ws] () {
		ws.listen() or { panic('websocket server could not listen, err: ${err}') }
	}()
	for ws.get_state() != .open {
		time.sleep(10 * time.millisecond)
	}
	println('-----------------------------------------------------------------------------')
}

// run open the `html_filename` and modify the `js_filename`(vxui-htmx.js)
pub fn (mut vv VXUI) run(html_filename string, js_filename string) {
	vv.init(js_filename)
	start_google_chrome(html_filename)
	mut ws_state := websocket.State.open
	mut client_num := int(0)
	mut close_timer := int(0)
	for {
		ws_state = vv.ws.get_state()

		rlock vv.ws.server_state {
			client_num = vv.ws.server_state.clients.len
		}
		if ws_state == .closed {
			break
		}
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
	vv.ws.free()
}
