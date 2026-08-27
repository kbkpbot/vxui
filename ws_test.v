module vxui

import time
import net.websocket
import x.json2

// =============================================================================
// WebSocket Integration & Security Gate Tests (real client against server)
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
