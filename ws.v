module vxui

import net
import net.websocket
import time
import x.json2
import rand

// =============================================================================
// WebSocket Server
// =============================================================================

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

// startup_ws_server starts the websocket server at `listen_port`.
// Callbacks derive the Context from the captured app on every invocation so
// they can never observe a stale/aliased Context instance.
fn startup_ws_server[T](mut app T, family net.AddrFamily, listen_port int) !&websocket.Server {
	mut ctx := context_of(mut app)
	// Erase the concrete App type so the (non-generic) WebSocket callbacks can
	// still reach the user's route handlers through `dispatch`. `context_of`
	// returns `&app.Context`; because Context is the embedded field at offset 0,
	// that pointer is also the address of the concrete App (stable for the
	// program's lifetime).
	ctx.app_ptr = unsafe { voidptr(context_of(mut app)) }
	ctx.dispatch = fire_ws[T]
	mut s := websocket.new_server(family, listen_port, '')
	// The library's ping thread also WATCHDOGS clients: it closes any
	// connection whose pong is older than 2x this interval. A 1-second
	// interval killed clients whenever a route handler (e.g. a multi-MB
	// upload) blocked the read loop for more than 2 seconds. Drive it from
	// the documented config instead: interval = ws_ping_interval_ms, so the
	// effective watchdog threshold matches ws_pong_timeout_ms semantics.
	ping_secs := ctx.config.ws_ping_interval_ms / 1000
	s.set_ping_interval(if ping_secs < 1 { 1 } else { ping_secs })

	// on_connect accepts every connection; the loopback/client-limit gate that
	// used to live here cannot run here because `on_connect` is a plain
	// (non-capturing) function pointer with no user-data slot. The gate is
	// applied in on_message instead, on the first frame of each not-yet
	// authenticated connection (which DOES carry the Context via `ref`).
	s.on_connect(fn (mut con websocket.ServerClient) !bool {
		return true
	})!

	s.on_message_ref(fn (mut ws websocket.Client, msg &websocket.Message, v voidptr) ! {
		mut ctx := unsafe { &Context(v) }
		if msg.opcode == .pong {
			// protocol-level pong: the websocket library answers control
			// pings itself; nothing to do here. Application liveness uses
			// the JSON cmd ping/pong in handle_control_message.
			return
		}
		raw_payload := msg.payload.bytestr()
		raw_message := json2.decode[json2.Any](raw_payload)!
		mut message := raw_message.as_map()

		// Connection gate for not-yet-authenticated sockets (moved from
		// on_connect, which lacks a user-data slot). Runs once per connection.
		if ctx.find_client_id_by_connection(ws) == '' {
			ctx.trigger_event(EventType.client_connecting, '', 'Client connecting...', {}, none,
				none, none)

			// Loopback gate: the server binds all interfaces, so unless the
			// user explicitly opted in, only local processes may connect.
			if !ctx.config.allow_remote {
				mut peer := '?'
				if a := ws.conn.peer_addr() {
					peer = a.str().all_before_last(':')
				}
				if !addr_is_loopback(peer) {
					ctx.logger.warn('Rejecting non-loopback connection from ${peer} (set config.allow_remote = true to permit)')
					ws.close(1008, 'Non-loopback connection rejected')!
					return
				}
			}

			// Check client limit
			ctx.mu.rlock()
			client_count := ctx.clients.len
			ctx.mu.runlock()

			if !ctx.config.multi_client && !ctx.config.evict_on_new && client_count > 0 {
				ctx.logger.warn('Rejecting connection: multi_client is disabled')
				ws.close(1008, 'multi_client is disabled')!
				return
			}

			if ctx.config.max_clients > 0 && client_count >= ctx.config.max_clients {
				ctx.logger.warn('Rejecting connection: max_clients limit reached')
				ws.close(1008, 'max_clients limit reached')!
				return
			}
		}

		ctx.logger.debug('Received message keys: ${message.keys()}')

		handled := ctx.handle_control_message(mut ws, message, raw_payload)!
		if handled {
			return
		}

		if rpc_id := message['rpcID'] {
			dispatch_rpc(mut ctx, mut ws, rpc_id.i64(), mut message)!
		}
	}, unsafe { voidptr(ctx) })

	s.on_close_ref(fn (mut ws websocket.Client, code int, reason string, v voidptr) ! {
		mut ctx := unsafe { &Context(v) }
		ctx.logger.info('Client disconnected: code=${code}, reason=${reason}')

		// Send removal request to channel (serialized processing)
		client_id_to_remove := ctx.find_client_id_by_connection(ws)
		if client_id_to_remove != '' {
			ctx.client_remove_chan <- ClientRemoveMsg{client_id_to_remove, 'on_close'}
		}
	}, unsafe { voidptr(ctx) })

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
			ctx.handle_ping(mut ws, message)!
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
		match cmd.str() {
			'js_result' {
				ctx.handle_js_result(message)
				return true
			}
			'pong' {
				ctx.handle_pong(message)
				return true
			}
			'client_close' {
				ctx.handle_client_close(mut ws, message)
				return true
			}
			'get_clients' {
				ctx.handle_get_clients(mut ws, message)!
				return true
			}
			else {}
		}
	}

	return false
}

// handle_ping answers a keep-alive ping. Liveness bookkeeping (handle_pong)
// only runs for token-authenticated pings; the pong reply is always sent.
fn (mut ctx Context) handle_ping(mut conn &websocket.Client, message map[string]json2.Any) ! {
	if message_token_valid(message, ctx.config.require_auth, ctx.config.token) {
		ctx.handle_pong(message)
	}
	ctx.send_cmd(mut conn, 'pong', {
		'client_id': message['client_id'] or { json2.Any('') }
		'timestamp': json2.Any(time.now().unix_milli())
	})!
}

// handle_get_clients enumerates connected clients (token-gated by the caller).
fn (mut ctx Context) handle_get_clients(mut _conn &websocket.Client, _message map[string]json2.Any) ! {
	mut ids := []json2.Any{}
	for id in ctx.get_clients() {
		ids << json2.Any(id)
	}
	ctx.send_cmd(mut _conn, 'clients', {
		'ids': json2.Any(ids)
	})!
}

// handle_client_close forwards a client-initiated close to the serialized
// removal channel (token-gated by the caller).
fn (mut ctx Context) handle_client_close(mut _conn &websocket.Client, message map[string]json2.Any) {
	client_id := message['client_id'] or { json2.Any('') }.str()
	ctx.client_remove_chan <- ClientRemoveMsg{client_id, 'client_close'}
}

// dispatch_rpc routes an rpcID-bearing message to its tagged route handler
// and writes the JSON response back on the same connection. It is non-generic:
// the concrete App type is reached through the type-erased `ctx.dispatch`
// trampoline (set in startup_ws_server), so the WebSocket callbacks need not
// be generic themselves.
fn dispatch_rpc(mut ctx Context, mut ws websocket.Client, rpc_id i64, mut message map[string]json2.Any) ! {
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

	// Handle message. handle_request only ever returns a Response (no `!` in
	// practice), but the `or` block preserves the original 404 trace path.
	response := ctx.dispatch(mut &ctx, req.path, message) or {
		// unknown route: previously a completely silent 404 — the player
		// clicks a button and nothing happens, no trace anywhere
		ctx.logger.warn('rpc 404: no route for ${req.verb} ${req.path} (client ${client_id})')
		mut err_m := map[string]json2.Any{}
		err_m['rpcID'] = json2.Any('${rpc_id}')
		err_m['error'] = json2.Any('route_not_found')
		err_m['message'] = json2.Any('no route for ${req.path}')
		ws.write(json2.encode(err_m).bytes(), .text_frame)!
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

// fire_ws is the type-erased trampoline monomorphized per App type. It
// recovers the concrete App pointer from `ctx.app_ptr` and dispatches the
// message to the matching route handler via handle_request/fire_call.
fn fire_ws[T](mut ctx Context, _method_name string, message map[string]json2.Any) !Response {
	mut p := ctx.app_ptr
	mut app := unsafe { p as &T }
	return handle_request[T](mut app, ctx, build_request(message, ''), message)
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
		id:         client_id
		token:      ctx.config.token
		last_ping:  time.now()
		connection: ws
	}
	ctx.mu.unlock()

	ctx.logger.info('Client authenticated: ${client_id}')
	ctx.trigger_event(EventType.client_connected, client_id, 'Client authenticated', {}, none,
		none, none)

	mut auth_extra := map[string]json2.Any{}
	auth_extra['client_id'] = json2.Any(client_id)
	if ctx.config.js_sandbox.enabled {
		auth_extra['js_sandbox'] = json2.encode(ctx.config.js_sandbox)
	}
	ctx.send_cmd(mut ws, 'auth_ok', auth_extra)!

	// Apply the configured window/page title on the freshly connected client
	effective_title := if ctx.config.window.title != '' {
		ctx.config.window.title
	} else if ctx.config.app_name != default_app_name {
		ctx.config.app_name
	} else {
		''
	}
	if effective_title != '' {
		mut title_extra := map[string]json2.Any{}
		title_extra['js_id'] = json2.Any('title-${client_id}')
		title_extra['script'] = json2.Any("document.title = '${escape_js(effective_title)}'")
		ctx.send_cmd(mut ws, 'run_js', title_extra)!
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
