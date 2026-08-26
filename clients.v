module vxui

import net.websocket
import time
import x.json2

// =============================================================================
// Client Management
// =============================================================================

// ClientRemoveMsg is a message for the client removal channel
struct ClientRemoveMsg {
	client_id string
	from_msg  string // for debugging: 'client_close' or 'on_close'
}

// Client represents a connected browser client
pub struct Client {
pub:
	id    string
	token string
pub mut:
	connection ?&websocket.Client
	last_ping  time.Time
}

// check_client_timeouts removes clients that haven't responded to pings
fn (mut ctx Context) check_client_timeouts() {
	ctx.mu.lock()
	mut stale_clients := []string{}
	now := time.now()

	for id, client in ctx.clients {
		if now.unix_milli() - client.last_ping.unix_milli() > ctx.config.ws_pong_timeout_ms {
			stale_clients << id
		}
	}

	for id in stale_clients {
		ctx.clients.delete(id)
		ctx.logger.warn('Removed stale client: ${id}')
	}
	ctx.mu.unlock()

	// Fire events AFTER releasing the lock: handlers may call back into
	// Context APIs (broadcast/get_clients/...) and do network IO.
	for id in stale_clients {
		ctx.trigger_event(EventType.client_disconnected, id, 'Client timeout', {}, none, none, none)
	}
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

// get_client returns client info by ID
pub fn (mut ctx Context) get_client(client_id string) ?Client {
	ctx.mu.rlock()
	result := ctx.clients[client_id] or { Client{} }
	ctx.mu.runlock()
	if result.id == '' {
		return none
	}
	return result
}

// close_client disconnects a specific client
pub fn (mut ctx Context) close_client(client_id string) ! {
	ctx.mu.lock()
	client := ctx.clients[client_id] or {
		ctx.mu.unlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.unlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.clients.delete(client_id)
	ctx.mu.unlock()

	conn.close(1000, 'Closed by server')!
	ctx.logger.info('Closed client: ${client_id}')
	ctx.trigger_event(EventType.client_disconnected, client_id, 'Closed by server', {}, none, none,
		none)
}

// client_connections returns the connections of all clients except `except_client_id`
// (pass '' to include everyone). The lock is released before writing.
fn (mut ctx Context) client_connections(except_client_id string) []&websocket.Client {
	ctx.mu.rlock()
	mut connections := []&websocket.Client{}
	for id, client in ctx.clients {
		if id != except_client_id {
			if conn := client.connection {
				connections << conn
			}
		}
	}
	ctx.mu.runlock()
	return connections
}

// broadcast sends a message to all connected clients.
// A write failure on one client (e.g. a stale connection) is skipped
// so the remaining clients still receive the message.
pub fn (mut ctx Context) broadcast(message string) ! {
	for mut conn in ctx.client_connections('') {
		conn.write_string(message) or {
			ctx.logger.debug('broadcast: client write failed, skipped: ${err}')
			continue
		}
	}
}

// broadcast_except sends a message to all clients except one.
// Per-client write failures are skipped, see broadcast().
pub fn (mut ctx Context) broadcast_except(message string, except_client_id string) ! {
	for mut conn in ctx.client_connections(except_client_id) {
		conn.write_string(message) or {
			ctx.logger.debug('broadcast_except: client write failed, skipped: ${err}')
			continue
		}
	}
}

// send_to_client sends a message to a specific client
pub fn (mut ctx Context) send_to_client(client_id string, message string) ! {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.mu.runlock()

	conn.write_string(message)!
}

// broadcast_cmd writes a JSON control-message envelope ({'cmd': cmd, ...extra})
// to every connected client. Per-client write failures are skipped, matching
// broadcast().
fn (mut ctx Context) broadcast_cmd(cmd string, extra map[string]json2.Any) {
	mut m := map[string]json2.Any{}
	m['cmd'] = cmd
	for k, v in extra {
		m[k] = v
	}
	ctx.broadcast(json2.encode(m)) or {}
}

// ping_client sends a ping to a specific client
pub fn (mut ctx Context) ping_client(client_id string) ! {
	ctx.mu.rlock()
	client := ctx.clients[client_id] or {
		ctx.mu.runlock()
		return new_error_detail(.client_not_found, 'Client not found: ${client_id}')
	}
	mut conn := client.connection or {
		ctx.mu.runlock()
		return new_error_detail(.no_valid_connection, 'Client has no connection')
	}

	ctx.mu.runlock()

	ctx.send_cmd(mut conn, 'ping', {
		'timestamp': json2.Any(time.now().unix_milli())
	})!
}

// ping_all_clients sends a ping to all connected clients
pub fn (mut ctx Context) ping_all_clients() {
	ctx.broadcast_cmd('ping', {
		'timestamp': json2.Any(time.now().unix_milli())
	})
}

// process_client_removals handles client removal requests from the channel
// This should be run in a separate goroutine to serialize removal operations
pub fn (mut ctx Context) process_client_removals() {
	for {
		msg := <-ctx.client_remove_chan or { break }
		ctx.mu.lock()
		existed := msg.client_id in ctx.clients
		if existed {
			ctx.clients.delete(msg.client_id)
			ctx.logger.info('Client removed (${msg.from_msg}): ${msg.client_id}')
		} else {
			ctx.logger.debug('Client already removed (${msg.from_msg}): ${msg.client_id}')
		}
		ctx.mu.unlock()

		// Fire the event AFTER releasing the lock: handlers may call back
		// into Context APIs (broadcast/get_clients/...) and do network IO.
		if existed {
			ctx.trigger_event(EventType.client_disconnected, msg.client_id, 'Client disconnected',
				{}, none, none, none)
		}
	}
}
