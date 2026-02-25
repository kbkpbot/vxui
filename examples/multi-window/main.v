module main

import vxui
import x.json2
import time

// Message represents a broadcast message
struct Message {
	id      int
	text    string
	sender  string
	time    string
}

// App manages multiple windows via multi-client support
struct App {
	vxui.Context
mut:
	messages       []Message
	message_id     int
	shared_counter int
	window_states  map[string]WindowState
}

struct WindowState {
	id       string
	name     string
	joined_at string
	last_ping string
}

// Send message to all windows
@['/broadcast']
fn (mut app App) broadcast_handler(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	text := params['text'] or { json2.Null{} }.str().trim_space()

	if text == '' {
		return '<div id="error" class="error">Please enter a message</div>'
	}

	app.message_id++
	msg := Message{
		id:      app.message_id
		text:    text
		sender:  'Window-${app.get_client_count()}'
		time:    time.now().format_ss()
	}
	app.messages << msg

	// Keep only last 20 messages
	if app.messages.len > 20 {
		app.messages = app.messages[app.messages.len - 20..]
	}

	// Get current client ID
	client_id := params['client_id'] or { json2.Any('') }.str()

	// Create message update HTML
	message_html := app.render_broadcast_message()

	// Broadcast to all OTHER windows
	if client_id != '' {
		app.broadcast_except(message_html, client_id) or {}
	} else {
		// If no client_id, broadcast to all
		app.broadcast(message_html) or {}
	}

	// Return update for current window
	return message_html + '<div id="error" hx-swap-oob="true"></div>'
}

// Update shared counter
@['/counter/increment']
fn (mut app App) increment_counter(message map[string]json2.Any) string {
	app.shared_counter++

	// Get current client ID from message
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('') }.str()

	// Create counter update HTML
	counter_html := '<div id="shared-counter" hx-swap-oob="true"><span class="counter-value">${app.shared_counter}</span><span class="counter-info">Last updated by Window-${app.get_client_count()}</span></div>'

	// Broadcast to all OTHER windows
	if client_id != '' {
		app.broadcast_except(counter_html, client_id) or {}
	}

	// Return update for current window (both counter and result message)
	return counter_html + '<div id="counter-result" hx-swap-oob="true">Counter incremented!</div>'
}

// Reset counter
@['/counter/reset']
fn (mut app App) reset_counter(message map[string]json2.Any) string {
	app.shared_counter = 0

	// Get current client ID
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('') }.str()

	// Create counter update HTML
	counter_html := '<div id="shared-counter" hx-swap-oob="true"><span class="counter-value">0</span><span class="counter-info">Counter reset</span></div>'

	// Broadcast to all OTHER windows
	if client_id != '' {
		app.broadcast_except(counter_html, client_id) or {}
	}

	// Return update for current window
	return counter_html
}

// Clear all messages
@['/messages/clear']
fn (mut app App) clear_messages(message map[string]json2.Any) string {
	app.messages = []

	// Get current client ID
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('') }.str()

	// Create clear message HTML
	clear_html := '<div id="messages" hx-swap-oob="true" class="message-list empty"><p class="empty-text">No messages yet</p></div>'

	// Broadcast to all OTHER windows
	if client_id != '' {
		app.broadcast_except(clear_html, client_id) or {}
	} else {
		app.broadcast(clear_html) or {}
	}

	// Return for current window
	return clear_html
}

// Ping from window
@['/ping']
fn (mut app App) ping(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('') }.str()

	if client_id != '' {
		is_new := client_id !in app.window_states
		app.window_states[client_id] = WindowState{
			id:        client_id
			name:      'Window-${client_id[..8]}'
			joined_at: if is_new { time.now().format_ss() } else { app.window_states[client_id].joined_at }
			last_ping: time.now().format_ss()
		}

		// Broadcast connected windows update to all windows
		windows_html := app.render_connected_windows()
		app.broadcast(windows_html) or {}
	}

	return ''
}

// Render message list
fn (app App) render_message_list() string {
	if app.messages.len == 0 {
		return '<div id="messages" class="message-list empty"><p class="empty-text">No messages yet</p></div>'
	}

	mut html := '<div id="messages" class="message-list">'
	for msg in app.messages {
		html += '<div class="message">
			<div class="message-header">
				<span class="message-sender">${msg.sender}</span>
				<span class="message-time">${msg.time}</span>
			</div>
			<div class="message-text">${msg.text}</div>
		</div>'
	}
	html += '</div>'
	return html
}

// Render single broadcast message (for hx-swap-oob)
fn (app App) render_broadcast_message() string {
	return '<div id="messages" hx-swap-oob="true" class="message-list">${app.render_message_items()}</div>'
}

fn (app App) render_message_items() string {
	if app.messages.len == 0 {
		return '<p class="empty-text">No messages yet</p>'
	}

	mut html := ''
	for msg in app.messages {
		html += '<div class="message">
			<div class="message-header">
				<span class="message-sender">${msg.sender}</span>
				<span class="message-time">${msg.time}</span>
			</div>
			<div class="message-text">${msg.text}</div>
		</div>'
	}
	return html
}

// Render connected windows list
fn (app App) render_connected_windows() string {
	mut html := '<div id="connected-windows" hx-swap-oob="true" class="windows-list">'
	html += '<h3>Connected Windows (${app.window_states.len})</h3>'

	if app.window_states.len == 0 {
		html += '<p class="empty">No windows connected</p>'
	} else {
		html += '<ul>'
		for _, state in app.window_states {
			html += '<li><span class="window-name">${state.name}</span><span class="window-ping">Last seen: ${state.last_ping}</span></li>'
		}
		html += '</ul>'
	}
	html += '</div>'
	return html
}

fn main() {
	mut app := App{}

	// Enable multi-client mode for multiple windows
	app.config.multi_client = true
	app.config.close_timer_ms = 30000 // 30 seconds
	app.config.window = vxui.WindowConfig{
		width:     1200
		height:    800
		title:     'Multi-Window Demo'
		resizable: true
	}
	app.logger.set_level(.debug)

	// Open window
	vxui.run(mut app, './ui/index.html') or {
		eprintln('Error: ${err}')
		exit(1)
	}
}
