module main

import vxui
import x.json2
import time

// AppConfig represents the shared application configuration
struct AppConfig {
mut:
	title       string = 'Multi-Window Demo'
	bg_color    string = '#1a1a2e'
	accent_color string = '#00d4ff'
	message     string = 'Welcome to multi-window demo!'
	font_size   int    = 16
}

// App manages the multi-window application
struct App {
	vxui.Context
mut:
	app_config AppConfig
}

// Index handler - renders main display window
@['/']
fn (mut app App) index(message map[string]json2.Any) string {
	return app.render_main_window()
}

// Settings handler - renders settings window
@['/settings']
fn (mut app App) settings(message map[string]json2.Any) string {
	return app.render_settings_window()
}

// Update settings from settings window
@['/update-settings']
fn (mut app App) update_settings(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()

	// Update config values
	if title := params['title'] {
		app.app_config.title = title.str()
	}
	if bg_color := params['bg_color'] {
		app.app_config.bg_color = bg_color.str()
	}
	if accent_color := params['accent_color'] {
		app.app_config.accent_color = accent_color.str()
	}
	if msg := params['message'] {
		app.app_config.message = msg.str()
	}
	if font_size := params['font_size'] {
		app.app_config.font_size = font_size.int()
	}

	// Broadcast update to all windows (including main window)
	update_html := app.render_main_window_oob()
	app.broadcast(update_html) or {}

	return '<div id="save-result" hx-swap-oob="true" style="color: #00ff88; margin-top: 10px;">✓ Settings saved!</div>'
}

// Open new settings window
@['/open-settings']
fn (mut app App) open_settings(message map[string]json2.Any) string {
	// Get server info from context
	port := app.Context.get_port()
	token := app.Context.get_token()

	// Open settings window in a separate thread
	spawn fn (port u16, token string) {
		time.sleep(100 * time.millisecond)
		vxui.start_browser_with_token('./ui/settings.html', port, token, vxui.WindowConfig{
			width:     500
			height:    600
			title:     'Settings'
			resizable: true
		}) or {
			eprintln('Failed to open settings: ${err}')
		}
	}(port, token)

	return '<div id="open-result" hx-swap-oob="true">Opening settings...</div>'
}

// Render main window HTML
fn (app App) render_main_window() string {
	return '<!DOCTYPE html>
<html>
<head>
    <title>${app.app_config.title}</title>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
    <style id="dynamic-style">
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: ${app.app_config.bg_color};
            color: #fff;
            min-height: 100vh;
            padding: 40px;
            font-size: ${app.app_config.font_size}px;
        }
        .header {
            border-bottom-color: ${app.app_config.accent_color};
        }
        h1 {
            color: ${app.app_config.accent_color};
        }
        .settings-btn {
            background: ${app.app_config.accent_color};
        }
        .label {
            color: ${app.app_config.accent_color};
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 2px solid;
        }
        h1 {
            font-size: 2.5em;
        }
        .settings-btn {
            padding: 12px 24px;
            color: #fff;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            transition: transform 0.2s;
        }
        .settings-btn:hover {
            transform: translateY(-2px);
        }
        .content-box {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 40px;
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .message-display {
            font-size: 1.5em;
            line-height: 1.6;
            color: #ddd;
            text-align: center;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            color: #888;
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <!-- Hidden style container for dynamic CSS updates -->
    <div id="style-updater" hx-swap-oob="true" style="display: none;">
        <style>
            body { background: ${app.app_config.bg_color} !important; color: #fff !important; font-size: ${app.app_config.font_size}px !important; }
            .main-wrapper .header { border-bottom-color: ${app.app_config.accent_color} !important; }
            .main-wrapper h1 { color: ${app.app_config.accent_color} !important; }
            .main-wrapper .settings-btn { background: ${app.app_config.accent_color} !important; }
            .main-wrapper .label { color: ${app.app_config.accent_color} !important; }
        </style>
    </div>
    
    <!-- Main content wrapper for OOB updates -->
    <div id="main-wrapper" class="main-wrapper" hx-swap-oob="true">
        <div class="container">
            <div class="header">
                <h1>${app.app_config.title}</h1>
                <button class="settings-btn" hx-post="/open-settings" hx-swap="none">
                    ⚙️ Settings
                </button>
            </div>
            <div class="content-box">
                <div class="message-display">${app.app_config.message}</div>
                <div class="info-row">
                    <span><span class="label">Background:</span> ${app.app_config.bg_color}</span>
                    <span><span class="label">Accent:</span> ${app.app_config.accent_color}</span>
                    <span><span class="label">Font Size:</span> ${app.app_config.font_size}px</span>
                </div>
            </div>
        </div>
        <div id="open-result"></div>
    </div>
</body>
</html>'
}

// Render main window update (for OOB broadcast)
fn (app App) render_main_window_oob() string {
	// Return style updater and main wrapper as OOB updates
	return '<div id="style-updater" hx-swap-oob="true" style="display: none;">
        <style>
            body { background: ${app.app_config.bg_color} !important; color: #fff !important; font-size: ${app.app_config.font_size}px !important; }
            .main-wrapper .header { border-bottom-color: ${app.app_config.accent_color} !important; }
            .main-wrapper h1 { color: ${app.app_config.accent_color} !important; }
            .main-wrapper .settings-btn { background: ${app.app_config.accent_color} !important; }
            .main-wrapper .label { color: ${app.app_config.accent_color} !important; }
        </style>
    </div>
    <div id="main-wrapper" class="main-wrapper" hx-swap-oob="true">
        <div class="container">
            <div class="header">
                <h1>${app.app_config.title}</h1>
                <button class="settings-btn" hx-post="/open-settings" hx-swap="none">
                    ⚙️ Settings
                </button>
            </div>
            <div class="content-box">
                <div class="message-display">${app.app_config.message}</div>
                <div class="info-row">
                    <span><span class="label">Background:</span> ${app.app_config.bg_color}</span>
                    <span><span class="label">Accent:</span> ${app.app_config.accent_color}</span>
                    <span><span class="label">Font Size:</span> ${app.app_config.font_size}px</span>
                </div>
            </div>
        </div>
        <div id="open-result"></div>
    </div>'
}

// Render settings window HTML
fn (app App) render_settings_window() string {
	return '<!DOCTYPE html>
<html>
<head>
    <title>Settings</title>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0f0f23;
            color: #fff;
            min-height: 100vh;
            padding: 30px;
        }
        .container {
            max-width: 450px;
            margin: 0 auto;
        }
        h1 {
            color: #00d4ff;
            margin-bottom: 30px;
            text-align: center;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #aaa;
            font-size: 14px;
        }
        input[type="text"], input[type="number"] {
            width: 100%;
            padding: 12px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 6px;
            background: rgba(255, 255, 255, 0.05);
            color: #fff;
            font-size: 14px;
        }
        input[type="color"] {
            width: 100%;
            height: 40px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
        }
        .color-preview {
            display: inline-block;
            width: 30px;
            height: 30px;
            border-radius: 4px;
            margin-left: 10px;
            vertical-align: middle;
            border: 2px solid rgba(255, 255, 255, 0.2);
        }
        .btn-group {
            display: flex;
            gap: 10px;
            margin-top: 30px;
        }
        button {
            flex: 1;
            padding: 14px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            transition: all 0.2s;
        }
        .btn-save {
            background: linear-gradient(90deg, #00d4ff, #0099cc);
            color: #fff;
        }
        .btn-save:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0, 212, 255, 0.4);
        }
        .btn-close {
            background: rgba(255, 255, 255, 0.1);
            color: #fff;
        }
        .btn-close:hover {
            background: rgba(255, 255, 255, 0.2);
        }
        .info-box {
            background: rgba(0, 212, 255, 0.1);
            border: 1px solid rgba(0, 212, 255, 0.3);
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
            font-size: 13px;
            color: #aaa;
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <div class="container">
        <h1>⚙️ Settings</h1>
        
        <div class="info-box">
            Changes will be applied to the main window in real-time.
        </div>

        <form hx-post="/update-settings" hx-swap="none" hx-include="input,textarea">
            <div class="form-group">
                <label>Title</label>
                <input type="text" name="title" value="${app.app_config.title}">
            </div>

            <div class="form-group">
                <label>Message</label>
                <input type="text" name="message" value="${app.app_config.message}">
            </div>

            <div class="form-group">
                <label>Background Color <span class="color-preview" style="background: ${app.app_config.bg_color}"></span></label>
                <input type="color" name="bg_color" value="${app.app_config.bg_color}">
            </div>

            <div class="form-group">
                <label>Accent Color <span class="color-preview" style="background: ${app.app_config.accent_color}"></span></label>
                <input type="color" name="accent_color" value="${app.app_config.accent_color}">
            </div>

            <div class="form-group">
                <label>Font Size (${app.app_config.font_size}px)</label>
                <input type="number" name="font_size" value="${app.app_config.font_size}" min="12" max="32">
            </div>

            <div class="btn-group">
                <button type="submit" class="btn-save">💾 Save Changes</button>
                <button type="button" class="btn-close" onclick="window.close()">✕ Close</button>
            </div>
        </form>

        <div id="save-result"></div>
    </div>
</body>
</html>'
}

fn main() {
	mut app := App{}

	// Configure vxui context (not app config)
	app.Context.config.multi_client = true
	app.Context.config.close_timer_ms = 30000
	app.Context.config.window = vxui.WindowConfig{
		width:     900
		height:    600
		title:     'Multi-Window Demo'
		resizable: true
	}
	app.logger.set_level(.debug)

	vxui.run(mut app, './ui/index.html') or {
		eprintln('Error: ${err}')
		exit(1)
	}
}