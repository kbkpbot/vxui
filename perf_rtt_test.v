module vxui

import time
import net.websocket
import x.json2

// =============================================================================
// RPC round-trip latency benchmark (real WebSocket server, loopback)
// =============================================================================

// PerfApp is a minimal self-contained app: one tagged route returning a
// constant string — the cheapest possible handler so the measurement isolates
// the framework round-trip (WS frame -> decode -> dispatch -> encode -> out).
@[heap]
struct PerfApp {
	Context
mut:
	calls int
}

@['/tagged']
fn (mut app PerfApp) tagged_handler(_ map[string]json2.Any) string {
	app.calls++
	return 'tagged-ok'
}

// read_text_frame reads the next TEXT frame, skipping protocol-level control
// frames (pong/ping). Fails after 64 frames.
fn read_text_frame(mut cl websocket.Client) !string {
	for _ in 0 .. 64 {
		msg := cl.read_next_message()!
		if msg.opcode == .text_frame {
			return msg.payload.bytestr()
		}
	}
	return error('no text frame received')
}

// test_rpc_round_trip_latency measures the full backend response path a user
// feels when clicking a button: WS frame in -> json decode -> token gate ->
// route dispatch -> handler -> WS frame out. It runs against the REAL
// websocket server (no browser), so the numbers are stable across machines.
//
// Reported metrics: p50/p90/p99/max RTT and serial throughput.
// Assertions are deliberately loose order-of-magnitude regression gates:
// loopback RTTs are normally sub-millisecond even in debug builds; if p99
// exceeds 20ms the hot path has regressed (accidental sleep, lock contention,
// per-message allocation blowup, ...).
fn test_rpc_round_trip_latency() ! {
	port := int(get_free_port()!)
	mut app := PerfApp{}
	app.ws_port = u16(port)
	app.config.token = 'it-token'
	app.config.close_timer_ms = 60_000
	app.clients = map[string]Client{}
	app.js_callbacks = map[string]chan string{}
	app.event_handlers = map[EventType][]EventHandler{}
	app.client_remove_chan = chan ClientRemoveMsg{cap: 8}
	app.routes = generate_routes(app)!

	startup_ws_server(mut app, .ip, port)!
	defer {
		app.ws.free()
	}
	spawn fn [mut app] () {
		app.process_client_removals()
	}()

	// --- connect + authenticate like a real page ---
	mut cl := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	auth_resp := read_text_frame(mut cl)!
	assert auth_resp.contains('"cmd":"auth_ok"'), 'auth failed: ${auth_resp}'

	send_rpc := fn [mut cl] (seq int) ! {
		cl.write_string('{"rpcID":${seq},"token":"it-token","verb":"get","path":"/tagged"}')!
	}
	wait_resp := fn [mut cl] (seq int) ! {
		want := '"rpcID":"${seq}"'
		for {
			resp := read_text_frame(mut cl)!
			if resp.contains(want) {
				return
			}
			// skip unrelated text frames (heartbeats etc.)
		}
	}

	// --- warmup: absorb thread-pool cold start and allocator growth ---
	warmup := 200
	n_rtt := 1000
	mut rtts := []i64{cap: n_rtt}
	for i in 0 .. warmup {
		send_rpc(i)!
		wait_resp(i)!
	}

	// --- measurement ---
	for i in warmup .. warmup + n_rtt {
		t0 := time.now().unix_nano()
		send_rpc(i)!
		wait_resp(i)!
		t1 := time.now().unix_nano()
		rtts << (t1 - t0)
	}

	rtts.sort()
	p50 := rtts[n_rtt / 2 - 1]
	p90 := rtts[n_rtt * 9 / 10 - 1]
	p99 := rtts[n_rtt * 99 / 100 - 1]
	mx := rtts[n_rtt - 1]

	mut sum := i64(0)
	for v in rtts {
		sum += v
	}
	total_us := f64(sum) / 1000.0
	throughput := f64(n_rtt) / (total_us / 1_000_000.0)

	// ns -> ms
	p50_ms := f64(p50) / 1_000_000.0
	p90_ms := f64(p90) / 1_000_000.0
	p99_ms := f64(p99) / 1_000_000.0
	max_ms := f64(mx) / 1_000_000.0

	println('=== RPC round-trip latency (loopback, ${n_rtt} samples) ===')
	println('p50=${p50_ms:.3}ms  p90=${p90_ms:.3}ms  p99=${p99_ms:.3}ms  max=${max_ms:.3}ms')
	println('throughput≈${throughput:.0} round-trips/s (serial)')

	// Order-of-magnitude regression gates only — see doc comment above.
	assert p50_ms < 10.0, 'p50 RTT regressed: ${p50_ms:.2}ms'
	assert p99_ms < 20.0, 'p99 RTT regressed: ${p99_ms:.2}ms'

	cl.close(1000, 'done') or {}
}
