module vxui

import time
import net.websocket
import x.json2

// =============================================================================
// Shared test helpers (defined exactly once in a normal module file so every
// _test.v sees them; V compiles each _test.v separately, so a _test.v helper
// would not be visible to sibling test files).
// =============================================================================

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
fn (mut app RoutingTestApp) tagged_handler(_message map[string]json2.Any) string {
	app.calls++
	return 'tagged-ok'
}

// untagged message-signature method: NOT a route under attr-gating
fn (mut app RoutingTestApp) untagged_handler(_message map[string]json2.Any) string {
	return 'untagged'
}

// untagged void helper with a custom signature: must not become a route
fn (mut app RoutingTestApp) track_call(x int) {
	app.calls += x
}

// A tagged method that does not return string is a configuration mistake:
// generate_routes must fail fast with a clear message instead of silently
// registering a route that cannot be dispatched.
struct BadReturnApp {
	Context
}

@['/bad']
fn (mut app BadReturnApp) bad_handler(_message map[string]json2.Any) int {
	return 1
}

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
