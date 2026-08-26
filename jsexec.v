module vxui

import net.websocket
import time
import x.json2
import rand

// =============================================================================
// JavaScript Execution
// =============================================================================

// execute_js is the internal implementation for JS execution
fn (mut ctx Context) execute_js(client_id string, js_code string, timeout_ms int) !string {
	ctx.mu.rlock()
	if ctx.clients.len == 0 {
		ctx.mu.runlock()
		return new_error_detail(.no_clients, 'No connected clients')
	}

	// SAFETY: nil is used as sentinel value for optional pointer
	mut client_conn := &websocket.Client(unsafe { nil })
	if client_id == '' {
		for _, c in ctx.clients {
			// SAFETY: nil comparison only, no dereference
			client_conn = c.connection or { unsafe { nil } }
			break
		}
	} else {
		client := ctx.clients[client_id] or {
			ctx.mu.runlock()
			return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
		}
		// SAFETY: nil comparison only, no dereference
		client_conn = client.connection or { unsafe { nil } }
	}
	ctx.mu.runlock()

	// SAFETY: nil comparison only, no dereference
	if client_conn == unsafe { nil } {
		return new_error_detail(.no_valid_connection, 'No valid client connection')
	}

	if ctx.config.js_sandbox.enabled {
		validate_js_code(js_code, ctx.config.js_sandbox) or {
			return new_error_detail(.js_validation_failed, 'JS validation failed: ${err}')
		}
	}

	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	mut ch := chan string{cap: 1}
	ctx.mu.lock()
	ctx.js_callbacks[js_id] = ch
	ctx.mu.unlock()
	defer {
		ctx.mu.lock()
		ctx.js_callbacks.delete(js_id)
		ctx.mu.unlock()
	}

	ctx.send_cmd(mut client_conn, 'run_js', {
		'js_id':   json2.Any(js_id)
		'script':  json2.Any(js_code)
		'timeout': json2.Any(timeout_ms)
	})!

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

		ch.close()

		if !got_result {
			return new_error_detail(.js_timeout, 'JavaScript execution timeout')
		}

		if ctx.config.js_sandbox.enabled && result.len > ctx.config.js_sandbox.max_result_size {
			return new_error_detail(.js_result_too_large, 'Result exceeds maximum size')
		}

		return result
	}
	// timeout_ms <= 0: fire-and-forget; the result channel is dropped with
	// the registration removed by the defer above.
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
			return new_error_detail(.js_validation_failed, 'Forbidden pattern found: ${pattern}')
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

// post_js executes JavaScript in the frontend fire-and-forget: the result
// (or error) is discarded and the pending callback is unregistered
// immediately. Safe to call from INSIDE route handlers, unlike
// run_js(timeout_ms > 0), which deadlocks there: a handler runs on the
// connection read loop, the very goroutine that would deliver js_result.
pub fn (mut ctx Context) post_js(js_code string) ! {
	ctx.execute_js('', js_code, 0)!
}

// post_js_client is post_js targeting one specific client.
pub fn (mut ctx Context) post_js_client(client_id string, js_code string) ! {
	ctx.execute_js(client_id, js_code, 0)!
}

// send_cmd writes a JSON control-message envelope ({'cmd': cmd, ...extra})
// to a single connection. The envelope shape matches the hand-built maps
// used throughout handle_control_message / execute_js / heartbeat, so the
// frontend sees identical frames. This is the single place that builds a
// cmd frame for a known connection.
fn (mut ctx Context) send_cmd(mut conn &websocket.Client, cmd string, extra map[string]json2.Any) ! {
	mut m := map[string]json2.Any{}
	m['cmd'] = cmd
	for k, v in extra {
		m[k] = v
	}
	conn.write(json2.encode(m).bytes(), .text_frame)!
}
