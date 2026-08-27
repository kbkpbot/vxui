module vxui

import time
import net.websocket

// =============================================================================
// Event System Tests
// =============================================================================

fn test_event_type_enum() {
	assert int(EventType.before_start) == 0
	assert int(EventType.after_start) == 1
	assert int(EventType.client_connecting) == 2
	assert int(EventType.client_connected) == 3
	assert int(EventType.client_disconnected) == 4
	assert int(EventType.before_shutdown) == 5
	assert int(EventType.error) == 6
	assert int(EventType.js_execution) == 7
	assert int(EventType.before_request) == 8
	assert int(EventType.after_request) == 9
}

fn test_event_data_struct() {
	data := EventData{
		event_type: EventType.client_connected
		client_id:  'test-client'
		message:    'Client connected'
	}
	assert data.event_type == EventType.client_connected
	assert data.client_id == 'test-client'
}

fn test_on_event() {
	mut ctx := Context{}
	ctx.on_event(EventType.client_connected, fn (e EventData) {
		// Handler registered
	})
	assert ctx.event_handlers[EventType.client_connected].len == 1
}

// Regression: client_disconnected handlers must be able to call Context APIs
// (get_clients/broadcast/...) — events must fire OUTSIDE the write lock,
// otherwise any handler touching the lock deadlocks.
fn test_disconnect_events_fire_outside_lock() {
	mut ctx := new_test_context()

	mut handler_ran := chan bool{cap: 4}
	ctx.on_event(.client_disconnected, fn [mut ctx, mut handler_ran] (e EventData) {
		// These acquire mu internally; called while holding mu they deadlock.
		_ := ctx.get_clients()
		_ := ctx.get_client_count()
		handler_ran <- true
	})

	stale := Client{
		id:        'stale-1'
		last_ping: time.now().add(-(2 * time.minute))
	}
	live := Client{
		id:        'live-1'
		last_ping: time.now()
	}
	ctx.clients['stale-1'] = stale
	ctx.clients['live-1'] = live

	// 1. timeout sweep removes the stale client and fires the event unlocked
	ctx.check_client_timeouts()
	assert 'stale-1' !in ctx.clients
	assert 'live-1' in ctx.clients

	// 2. removal channel path fires the event unlocked too
	ctx.client_remove_chan <- ClientRemoveMsg{'live-1', 'test'}
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()
	time.sleep(100 * time.millisecond)
	assert 'live-1' !in ctx.clients

	// both events observed, handlers ran to completion
	for _ in 0 .. 2 {
		select {
			ok := <-handler_ran {
				assert ok
			}
			10 * time.second {
				assert false, 'disconnect handler never completed (deadlock?)'
			}
		}
	}
}

// Regression: on_event() handlers registered BEFORE vxui.run()/init() must
// still fire. init() used to wipe event_handlers, silently dropping them.
fn test_on_event_before_run_survives_init() ! {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut fired := [false]
	app.on_event(.client_connected, fn [mut fired] (e vxui.EventData) {
		fired[0] = true // in-place: append would reallocate a captured copy
	})
	// registration sanity: the handler must be visible on the Context
	mut ctx0 := unsafe { &app.Context }
	assert ctx0.event_handlers[EventType.client_connected].len == 1
	// bisect: does direct dispatch through trigger_event fire the handler?
	ctx0.trigger_event(.client_connected, 'pre-test', '', {}, none, none, none)
	assert fired[0], 'direct trigger_event did not fire the handler'
	fired[0] = false
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut app] () {
		app.process_client_removals()
	}()
	defer {
		app.ws.free()
	}

	mut cl := websocket.new_client('ws://localhost:${port}/echo', websocket.ClientOpt{})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	auth_resp := read_text_until(mut cl, fn (s string) bool {
		return s.contains('"cmd":"auth_ok"')
	})!
	assert auth_resp.contains('"cmd":"auth_ok"')

	// the handler runs synchronously inside handle_auth (before auth_ok is
	// even written), so by the time we read auth_ok it must have fired
	assert fired[0], 'client_connected handler registered before run() did not fire'
	cl.close(1000, 'done') or {}
}
