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

// Main window handler
@['/']
fn (mut app App) index(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	window_type := params['type'] or { json2.Any('child') }.str()

	if window_type == 'main' {
		return app.render_main_window()
	}
	return app.render_child_window()
}

// Send message to all windows
@['/broadcast']
fn (mut app App) broadcast_handler(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	text := params['text'] or { json2.Null{} }.str().trim_space()
	sender := params['sender'] or { json2.Any('System') }.str()

	if text == '' {
		return '<div id="error" class="error">Please enter a message</div>'
	}

	app.message_id++
	msg := Message{
		id:      app.message_id
		text:    text
		sender:  sender
		time:    time.now().format_ss()
	}
	app.messages << msg

	// Keep only last 20 messages
	if app.messages.len > 20 {
		app.messages = app.messages[app.messages.len - 20..]
	}

	// Broadcast to all connected clients
	broadcast_html := app.render_broadcast_message()
	app.broadcast(broadcast_html) or {}

	return app.render_message_list()
}

// Update shared counter
@['/counter/increment']
fn (mut app App) increment_counter(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('Unknown') }.str()

	app.shared_counter++

	// Broadcast counter update to all windows
	counter_html := '<div id="shared-counter" hx-swap-oob="true"><span class="counter-value">${app.shared_counter}</span><span class="counter-info">Last updated by: ${client_id}</span></div>'
	app.broadcast(counter_html) or {}

	return '<div id="counter-result" hx-swap-oob="true">Counter incremented!</div>'
}

// Reset counter
@['/counter/reset']
fn (mut app App) reset_counter(message map[string]json2.Any) string {
	app.shared_counter = 0
	counter_html := '<div id="shared-counter" hx-swap-oob="true"><span class="counter-value">0</span><span class="counter-info">Counter reset</span></div>'
	app.broadcast(counter_html) or {}
	return ''
}

// Clear all messages
@['/messages/clear']
fn (mut app App) clear_messages(message map[string]json2.Any) string {
	app.messages = []
	return '<div id="messages" hx-swap-oob="true" class="message-list empty"><p class="empty-text">No messages yet</p></div>'
}

// Ping from window
@['/ping']
fn (mut app App) ping(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	client_id := params['client_id'] or { json2.Any('') }.str()

	if client_id != '' {
		app.window_states[client_id] = WindowState{
			id:        client_id
			name:      'Window-${client_id[..8]}'
			joined_at: app.window_states[client_id].joined_at
			last_ping: time.now().format_ss()
		}
	}

	return ''
}

// Get connected windows info
fn (mut app App) render_connected_windows() string {
	mut html := '<div id="connected-windows" hx-swap-oob="true" class="windows-list">'
	html += '<h3>Connected Windows (${app.get_client_count()})</h3>'

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

// Render main control window
fn (app App) render_main_window() string {
	return '<!DOCTYPE html>
<html>
<head>
    <title>Multi-Window Demo - Main Control</title>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            text-align: center;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: #888;
            margin-bottom: 30px;
        }
        .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        .panel {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 20px;
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .panel h2 {
            margin-bottom: 15px;
            color: #00d4ff;
        }
        .input-group {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
        input[type="text"] {
            flex: 1;
            padding: 10px 15px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 6px;
            background: rgba(255, 255, 255, 0.05);
            color: #fff;
            font-size: 14px;
        }
        button {
            padding: 10px 20px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.2s;
        }
        .btn-primary {
            background: linear-gradient(90deg, #00d4ff, #0099cc);
            color: #fff;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0, 212, 255, 0.4);
        }
        .btn-danger {
            background: linear-gradient(90deg, #ff4757, #cc0033);
            color: #fff;
        }
        .btn-secondary {
            background: rgba(255, 255, 255, 0.1);
            color: #fff;
        }
        .message-list {
            max-height: 300px;
            overflow-y: auto;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 8px;
            padding: 15px;
        }
        .message-list.empty {
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100px;
        }
        .empty-text {
            color: #666;
        }
        .message {
            padding: 10px;
            margin-bottom: 8px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 6px;
            border-left: 3px solid #00d4ff;
        }
        .message-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-size: 12px;
        }
        .message-sender {
            color: #00d4ff;
            font-weight: bold;
        }
        .message-time {
            color: #666;
        }
        .message-text {
            color: #ddd;
        }
        .counter-section {
            text-align: center;
            padding: 20px;
        }
        .counter-value {
            font-size: 48px;
            font-weight: bold;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .counter-info {
            display: block;
            color: #888;
            margin-top: 10px;
            font-size: 14px;
        }
        .counter-buttons {
            display: flex;
            gap: 10px;
            justify-content: center;
            margin-top: 15px;
        }
        .windows-list ul {
            list-style: none;
        }
        .windows-list li {
            padding: 10px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 6px;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
        }
        .window-name {
            color: #00d4ff;
        }
        .window-ping {
            color: #666;
            font-size: 12px;
        }
        .error {
            color: #ff4757;
            padding: 10px;
            background: rgba(255, 71, 87, 0.1);
            border-radius: 6px;
            margin-top: 10px;
        }
        .info-box {
            background: rgba(0, 212, 255, 0.1);
            border: 1px solid rgba(0, 212, 255, 0.3);
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
        }
        .info-box p {
            margin-bottom: 8px;
            color: #aaa;
        }
        .info-box code {
            background: rgba(0, 0, 0, 0.3);
            padding: 2px 6px;
            border-radius: 3px;
            color: #00d4ff;
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <div class="container">
        <h1>🪟 Multi-Window Demo</h1>
        <p class="subtitle">Control panel for managing multiple windows</p>

        <div class="info-box">
            <p><strong>How to use:</strong></p>
            <p>1. Open multiple browser windows/tabs with: <code>./multi-window</code></p>
            <p>2. Type messages below to broadcast to all windows</p>
            <p>3. Click the counter button to sync across all windows</p>
        </div>

        <div class="grid">
            <div class="panel">
                <h2>📢 Broadcast Messages</h2>
                <div class="input-group">
                    <input type="text" name="text" placeholder="Enter message to broadcast..." id="message-input">
                    <button class="btn-primary" hx-post="/broadcast" hx-target="#messages" hx-swap="outerHTML" hx-include="#message-input, [name=\'sender\']">
                        Send
                    </button>
                </div>
                <input type="hidden" name="sender" value="Main Control">
                <button class="btn-secondary" hx-post="/messages/clear" hx-target="#messages" hx-swap="outerHTML" style="margin-bottom: 15px;">
                    Clear Messages
                </button>
                <div id="error"></div>
                <div id="messages" class="message-list empty">
                    <p class="empty-text">No messages yet</p>
                </div>
            </div>

            <div class="panel">
                <h2>🔢 Shared Counter</h2>
                <div class="counter-section">
                    <div id="shared-counter">
                        <span class="counter-value">0</span>
                        <span class="counter-info">Click to increment across all windows</span>
                    </div>
                    <div class="counter-buttons">
                        <button class="btn-primary" hx-post="/counter/increment" hx-target="#counter-result" hx-swap="outerHTML" hx-vals=\'{"client_id": "main"}\'>
                            + Increment
                        </button>
                        <button class="btn-danger" hx-post="/counter/reset" hx-target="#counter-result" hx-swap="outerHTML">
                            Reset
                        </button>
                    </div>
                    <div id="counter-result"></div>
                </div>
            </div>

            <div class="panel">
                <h2>🖥️ Connected Windows</h2>
                <div id="connected-windows" class="windows-list">
                    <h3>Connected Windows (0)</h3>
                    <p class="empty">No windows connected</p>
                </div>
            </div>

            <div class="panel">
                <h2>📊 System Status</h2>
                <div style="padding: 20px;">
                    <p style="margin-bottom: 10px;"><strong>Multi-client mode:</strong> <span style="color: #00d4ff;">Enabled</span></p>
                    <p style="margin-bottom: 10px;"><strong>WebSocket:</strong> <span style="color: #00ff88;">Connected</span></p>
                    <p><strong>Window Type:</strong> Main Control</p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Send periodic ping to keep connection alive
        setInterval(() => {
            fetch("/ping", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ client_id: "main-" + Date.now() })
            });
        }, 5000);
    </script>
</body>
</html>'
}

// Render child window
fn (app App) render_child_window() string {
	return '<!DOCTYPE html>
<html>
<head>
    <title>Multi-Window Demo - Child Window</title>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #0f0f23 0%, #1a1a3e 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        h1 {
            text-align: center;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #7b2cbf, #ff006e);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: #888;
            margin-bottom: 30px;
        }
        .panel {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 20px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            margin-bottom: 20px;
        }
        .panel h2 {
            margin-bottom: 15px;
            color: #ff006e;
        }
        .message-list {
            max-height: 300px;
            overflow-y: auto;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 8px;
            padding: 15px;
        }
        .message-list.empty {
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100px;
        }
        .empty-text {
            color: #666;
        }
        .message {
            padding: 10px;
            margin-bottom: 8px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 6px;
            border-left: 3px solid #ff006e;
        }
        .message-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-size: 12px;
        }
        .message-sender {
            color: #ff006e;
            font-weight: bold;
        }
        .message-time {
            color: #666;
        }
        .message-text {
            color: #ddd;
        }
        .counter-section {
            text-align: center;
            padding: 20px;
        }
        .counter-value {
            font-size: 48px;
            font-weight: bold;
            background: linear-gradient(90deg, #ff006e, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .counter-info {
            display: block;
            color: #888;
            margin-top: 10px;
            font-size: 14px;
        }
        .input-group {
            display: flex;
            gap: 10px;
            margin-top: 15px;
        }
        input[type="text"] {
            flex: 1;
            padding: 10px 15px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 6px;
            background: rgba(255, 255, 255, 0.05);
            color: #fff;
            font-size: 14px;
        }
        button {
            padding: 10px 20px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.2s;
        }
        .btn-primary {
            background: linear-gradient(90deg, #ff006e, #cc0055);
            color: #fff;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(255, 0, 110, 0.4);
        }
        .status-bar {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: rgba(0, 0, 0, 0.8);
            padding: 10px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
        }
        .status-item {
            color: #888;
            font-size: 12px;
        }
        .status-online {
            color: #00ff88;
        }
        .window-id {
            color: #ff006e;
            font-family: monospace;
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <div class="container">
        <h1>🪟 Child Window</h1>
        <p class="subtitle">This window receives broadcasts from the main control</p>

        <div class="panel">
            <h2>📢 Received Messages</h2>
            <div id="messages" class="message-list empty">
                <p class="empty-text">No messages yet</p>
            </div>
        </div>

        <div class="panel">
            <h2>🔢 Shared Counter</h2>
            <div class="counter-section">
                <div id="shared-counter">
                    <span class="counter-value">0</span>
                    <span class="counter-info">Counter is synchronized across all windows</span>
                </div>
                <div class="input-group">
                    <input type="text" name="sender" placeholder="Your name (optional)" value="Child Window">
                    <button class="btn-primary" hx-post="/counter/increment" hx-target="#counter-result" hx-swap="outerHTML" hx-vals=\'{"client_id": "child"}\'>
                        + Increment from here
                    </button>
                </div>
                <div id="counter-result"></div>
            </div>
        </div>

        <div class="panel">
            <h2>💡 Instructions</h2>
            <ul style="color: #aaa; line-height: 1.8; margin-left: 20px;">
                <li>Open the main control window to send broadcasts</li>
                <li>Open multiple child windows to see synchronization</li>
                <li>Click "Increment" in any window to update all</li>
                <li>Messages from main appear here in real-time</li>
            </ul>
        </div>
    </div>

    <div class="status-bar">
        <span class="status-item">Window ID: <span class="window-id" id="window-id">...</span></span>
        <span class="status-item status-online">● Connected</span>
    </div>

    <script>
        // Generate unique window ID
        const windowId = "win-" + Math.random().toString(36).substr(2, 9);
        document.getElementById("window-id").textContent = windowId;

        // Send periodic ping
        setInterval(() => {
            fetch("/ping", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ client_id: windowId })
            });
        }, 5000);
    </script>
</body>
</html>'
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

fn main() {
	mut app := App{
		messages:      []
		window_states: map[string]WindowState{}
	}

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

	// Open main window by default
	vxui.run(mut app, './ui/index.html?type=main') or {
		eprintln('Error: ${err}')
		exit(1)
	}
}