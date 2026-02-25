module main

import vxui
import x.json2
import time

// AppConfig represents the shared application configuration
struct AppConfig {
mut:
	title        string = 'Multi-Window Demo'
	bg_color     string = '#0f0f1a'
	accent_color string = '#00d4ff'
	message      string = 'Welcome to Multi-Window Demo!'
	font_size    int    = 16
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

	// Broadcast OOB update to all clients
	oob_html := app.render_main_window_oob()
	broadcast_msg := json2.encode({
		'cmd':  'oob_update'
		'html': oob_html
	})

	app.broadcast(broadcast_msg) or {
		eprintln('Broadcast failed: ${err}')
	}

	return '<div id="save-result" hx-swap-oob="true" style="color: #4ade80; text-align: center; padding: 8px; font-size: 13px;">✓ Saved successfully</div>'
}

// Open new settings window
@['/open-settings']
fn (mut app App) open_settings(message map[string]json2.Any) string {
	port := app.Context.get_port()
	token := app.Context.get_token()

	spawn fn (port u16, token string) {
		time.sleep(100 * time.millisecond)
		vxui.start_browser_with_token('./ui/settings.html', port, token, vxui.WindowConfig{
			width:     340
			height:    480
			title:     'Settings'
			resizable: false
		}) or {
			eprintln('Failed to open settings: ${err}')
		}
	}(port, token)

	return ''
}

// Render main window HTML
fn (app App) render_main_window() string {
	return '<!DOCTYPE html>
<html>
<head>
    <title>${app.app_config.title}</title>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: ${app.app_config.bg_color};
            --accent-color: ${app.app_config.accent_color};
            --font-size: ${app.app_config.font_size}px;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, var(--bg-color) 0%, #1a1a2e 50%, #16213e 100%);
            color: #fff;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            font-size: var(--font-size);
            overflow: hidden;
        }
        
        /* Animated background */
        body::before {
            content: "";
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: 
                radial-gradient(circle at 20% 80%, var(--accent-color)15 0%, transparent 50%),
                radial-gradient(circle at 80% 20%, #ff006620 0%, transparent 50%);
            pointer-events: none;
            animation: bgPulse 8s ease-in-out infinite;
        }
        
        @keyframes bgPulse {
            0%, 100% { opacity: 0.5; }
            50% { opacity: 1; }
        }
        
        .container {
            position: relative;
            z-index: 1;
            max-width: 720px;
            width: 100%;
        }
        
        /* Glass card effect */
        .card {
            background: rgba(255, 255, 255, 0.03);
            backdrop-filter: blur(20px);
            border-radius: 24px;
            border: 1px solid rgba(255, 255, 255, 0.08);
            padding: 48px;
            box-shadow: 
                0 25px 50px rgba(0, 0, 0, 0.3),
                0 0 0 1px rgba(255, 255, 255, 0.05) inset;
        }
        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
            padding-bottom: 24px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }
        
        .title-group h1 {
            font-size: 1.75rem;
            font-weight: 700;
            background: linear-gradient(135deg, #fff 0%, var(--accent-color) 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            letter-spacing: -0.02em;
        }
        
        .title-group .subtitle {
            font-size: 0.875rem;
            color: rgba(255, 255, 255, 0.4);
            margin-top: 4px;
            font-weight: 400;
        }
        
        .settings-btn {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 12px 20px;
            background: rgba(255, 255, 255, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            color: rgba(255, 255, 255, 0.8);
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            font-family: inherit;
            transition: all 0.2s ease;
        }
        
        .settings-btn:hover {
            background: var(--accent-color);
            border-color: var(--accent-color);
            color: #fff;
            transform: translateY(-2px);
            box-shadow: 0 8px 24px var(--accent-color)40;
        }
        
        .settings-btn svg {
            width: 18px;
            height: 18px;
        }
        
        .content-box {
            text-align: center;
            padding: 32px 0;
        }
        
        .message-display {
            font-size: 1.25rem;
            line-height: 1.7;
            color: rgba(255, 255, 255, 0.85);
            font-weight: 400;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 16px;
            margin-top: 40px;
            padding-top: 24px;
            border-top: 1px solid rgba(255, 255, 255, 0.08);
        }
        
        .info-item {
            background: rgba(255, 255, 255, 0.02);
            border-radius: 12px;
            padding: 16px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            transition: all 0.2s ease;
        }
        
        .info-item:hover {
            background: rgba(255, 255, 255, 0.05);
            border-color: var(--accent-color)30;
        }
        
        .info-item .label {
            font-size: 0.75rem;
            color: rgba(255, 255, 255, 0.4);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 6px;
        }
        
        .info-item .value {
            font-size: 0.95rem;
            color: var(--accent-color);
            font-weight: 600;
        }
        
        .color-swatch {
            display: inline-block;
            width: 14px;
            height: 14px;
            border-radius: 4px;
            margin-left: 8px;
            vertical-align: middle;
            border: 2px solid rgba(255, 255, 255, 0.2);
        }
        
        /* Floating particles */
        .particles {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            pointer-events: none;
            overflow: hidden;
        }
        
        .particle {
            position: absolute;
            width: 4px;
            height: 4px;
            background: var(--accent-color);
            border-radius: 50%;
            opacity: 0.3;
            animation: float 15s infinite;
        }
        
        .particle:nth-child(1) { left: 10%; animation-delay: 0s; }
        .particle:nth-child(2) { left: 30%; animation-delay: 2s; }
        .particle:nth-child(3) { left: 50%; animation-delay: 4s; }
        .particle:nth-child(4) { left: 70%; animation-delay: 6s; }
        .particle:nth-child(5) { left: 90%; animation-delay: 8s; }
        
        @keyframes float {
            0%, 100% { transform: translateY(100vh) scale(0); opacity: 0; }
            10% { opacity: 0.3; }
            90% { opacity: 0.3; }
            100% { transform: translateY(-100vh) scale(1); opacity: 0; }
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <div class="particles">
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
    </div>
    
    <div id="main-wrapper">
        <div class="container">
            <div class="card">
                <div class="header">
                    <div class="title-group">
                        <h1>${app.app_config.title}</h1>
                        <div class="subtitle">Cross-platform desktop UI</div>
                    </div>
                    <button class="settings-btn" hx-post="/open-settings" hx-swap="none">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        Settings
                    </button>
                </div>
                <div class="content-box">
                    <div class="message-display">${app.app_config.message}</div>
                </div>
                <div class="info-grid">
                    <div class="info-item">
                        <div class="label">Background</div>
                        <div class="value">${app.app_config.bg_color}<span class="color-swatch" style="background: ${app.app_config.bg_color}"></span></div>
                    </div>
                    <div class="info-item">
                        <div class="label">Accent</div>
                        <div class="value">${app.app_config.accent_color}<span class="color-swatch" style="background: ${app.app_config.accent_color}"></span></div>
                    </div>
                    <div class="info-item">
                        <div class="label">Font Size</div>
                        <div class="value">${app.app_config.font_size}px</div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>'
}

// Render main window update (for OOB broadcast)
fn (app App) render_main_window_oob() string {
	bg := app.app_config.bg_color
	accent := app.app_config.accent_color
	font_size := app.app_config.font_size

	return '<div id="main-wrapper" hx-swap-oob="true" data-bg="${bg}" data-accent="${accent}" data-font-size="${font_size}">
        <div class="container">
            <div class="card">
                <div class="header">
                    <div class="title-group">
                        <h1>${app.app_config.title}</h1>
                        <div class="subtitle">Cross-platform desktop UI</div>
                    </div>
                    <button class="settings-btn" hx-post="/open-settings" hx-swap="none">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        Settings
                    </button>
                </div>
                <div class="content-box">
                    <div class="message-display">${app.app_config.message}</div>
                </div>
                <div class="info-grid">
                    <div class="info-item">
                        <div class="label">Background</div>
                        <div class="value">${bg}<span class="color-swatch" style="background: ${bg}"></span></div>
                    </div>
                    <div class="info-item">
                        <div class="label">Accent</div>
                        <div class="value">${accent}<span class="color-swatch" style="background: ${accent}"></span></div>
                    </div>
                    <div class="info-item">
                        <div class="label">Font Size</div>
                        <div class="value">${font_size}px</div>
                    </div>
                </div>
            </div>
        </div>
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
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: "Inter", -apple-system, sans-serif;
            background: linear-gradient(135deg, #0a0a14 0%, #141428 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 100%;
        }
        
        .header {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 20px;
            padding-bottom: 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }
        
        .header svg {
            color: #00d4ff;
        }
        
        .header h1 {
            font-size: 1.1rem;
            font-weight: 600;
            color: #fff;
        }
        
        .form-group {
            margin-bottom: 14px;
        }
        
        label {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 6px;
            color: rgba(255, 255, 255, 0.6);
            font-size: 12px;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.03em;
        }
        
        .color-dot {
            width: 16px;
            height: 16px;
            border-radius: 4px;
            border: 2px solid rgba(255, 255, 255, 0.15);
        }
        
        input[type="text"], input[type="number"] {
            width: 100%;
            padding: 10px 12px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            background: rgba(255, 255, 255, 0.04);
            color: #fff;
            font-size: 14px;
            font-family: inherit;
            transition: all 0.2s;
        }
        
        input[type="text"]:focus, input[type="number"]:focus {
            outline: none;
            border-color: #00d4ff;
            background: rgba(255, 255, 255, 0.06);
            box-shadow: 0 0 0 3px rgba(0, 212, 255, 0.1);
        }
        
        .color-input-wrap {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 6px 10px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            background: rgba(255, 255, 255, 0.04);
        }
        
        input[type="color"] {
            width: 32px;
            height: 32px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            background: transparent;
        }
        
        input[type="color"]::-webkit-color-swatch-wrapper {
            padding: 0;
        }
        
        input[type="color"]::-webkit-color-swatch {
            border-radius: 6px;
            border: none;
        }
        
        .color-value {
            flex: 1;
            color: rgba(255, 255, 255, 0.7);
            font-size: 13px;
            font-family: "SF Mono", Monaco, monospace;
        }
        
        .btn-group {
            display: flex;
            gap: 8px;
            margin-top: 20px;
            padding-top: 16px;
            border-top: 1px solid rgba(255, 255, 255, 0.08);
        }
        
        button {
            flex: 1;
            padding: 12px;
            border: none;
            border-radius: 10px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            font-family: inherit;
            transition: all 0.2s;
        }
        
        .btn-save {
            background: linear-gradient(135deg, #00d4ff 0%, #0099cc 100%);
            color: #fff;
        }
        
        .btn-save:hover {
            transform: translateY(-1px);
            box-shadow: 0 6px 20px rgba(0, 212, 255, 0.35);
        }
        
        .btn-close {
            background: rgba(255, 255, 255, 0.06);
            color: rgba(255, 255, 255, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        .btn-close:hover {
            background: rgba(255, 255, 255, 0.1);
            color: #fff;
        }
        
        #save-result {
            text-align: center;
            margin-top: 12px;
        }
    </style>
</head>
<body hx-ext="vxui-ws">
    <div class="container">
        <div class="header">
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <h1>Settings</h1>
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
                <label>
                    Background
                    <span class="color-dot" id="bg-preview" style="background: ${app.app_config.bg_color}"></span>
                </label>
                <div class="color-input-wrap">
                    <input type="color" name="bg_color" id="bg-input" value="${app.app_config.bg_color}" 
                           onchange="document.getElementById(\"bg-preview\").style.background=this.value; document.getElementById(\"bg-val\").textContent=this.value">
                    <span class="color-value" id="bg-val">${app.app_config.bg_color}</span>
                </div>
            </div>

            <div class="form-group">
                <label>
                    Accent
                    <span class="color-dot" id="accent-preview" style="background: ${app.app_config.accent_color}"></span>
                </label>
                <div class="color-input-wrap">
                    <input type="color" name="accent_color" id="accent-input" value="${app.app_config.accent_color}"
                           onchange="document.getElementById(\"accent-preview\").style.background=this.value; document.getElementById(\"accent-val\").textContent=this.value">
                    <span class="color-value" id="accent-val">${app.app_config.accent_color}</span>
                </div>
            </div>

            <div class="form-group">
                <label>Font Size (${app.app_config.font_size}px)</label>
                <input type="number" name="font_size" value="${app.app_config.font_size}" min="12" max="32">
            </div>

            <div class="btn-group">
                <button type="submit" class="btn-save">Save</button>
                <button type="button" class="btn-close" onclick="window.close()">Close</button>
            </div>
        </form>

        <div id="save-result"></div>
    </div>
</body>
</html>'
}

fn main() {
	mut app := App{}

	app.Context.config.multi_client = true
	app.Context.config.close_timer_ms = 30000
	app.Context.config.window = vxui.WindowConfig{
		width:     800
		height:    550
		title:     'Multi-Window Demo'
		resizable: true
	}
	app.logger.set_level(.info)

	vxui.run(mut app, './ui/index.html') or {
		eprintln('Error: ${err}')
		exit(1)
	}
}