<div align="center">

<h1>vxui</h1>

<p>
  <strong>Build cross-platform desktop apps with V + HTML/CSS/JS</strong>
</p>

<p>
  <a href="https://github.com/kbkpbot/vxui/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT">
  </a>
  <a href="https://vlang.io">
    <img src="https://img.shields.io/badge/Built%20with-V-blue.svg" alt="Built with V">
  </a>
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="Platforms">
  <img src="https://img.shields.io/badge/Status-Alpha-orange.svg" alt="Status: Alpha">
</p>

<p>
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#examples">Examples</a> •
  <a href="#documentation">Documentation</a> •
  <a href="#contributing">Contributing</a>
</p>

</div>

---

## 📸 Screenshots

<table>
  <tr>
    <td align="center"><b>Gallery Demo</b></td>
    <td align="center"><b>Element Plus</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/gallery.png" alt="Gallery" width="400"></td>
    <td><img src="screenshots/element-plus.png" alt="Element Plus" width="400"></td>
  </tr>
  <tr>
    <td align="center"><b>Real-time Charts</b></td>
    <td align="center"><b>Todo App</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/enchart.png" alt="Enchart" width="400"></td>
    <td><img src="screenshots/todo.png" alt="Todo App" width="400"></td>
  </tr>
  <tr>
    <td align="center"><b>Gomoku — two-window play</b></td>
    <td align="center"><b>2048</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/game-gomoku.png" alt="Gomoku" width="400"></td>
    <td><img src="screenshots/game-2048.png" alt="2048" width="400"></td>
  </tr>
  <tr>
    <td align="center"><b>Minesweeper</b></td>
    <td align="center"><b>Markdown Editor</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/game-minesweeper.png" alt="Minesweeper" width="400"></td>
    <td><img src="screenshots/markdown-editor.png" alt="Markdown Editor" width="400"></td>
  </tr>
</table>

---

## 🚀 Features

- **⚡ WebSocket-Powered** — Real-time bidirectional communication without HTTP overhead
- **🎨 Use Your Browser** — Leverage modern web technologies for beautiful UIs
- **🔒 Secure by Default** — Token-based authentication, XSS protection, and path traversal prevention
- **🌐 Cross-Platform** — Linux, macOS, and Windows support with auto browser detection
- **📦 Lightweight** — Pure V implementation, no external dependencies
- **🎯 htmx Integration** — Seamless integration with official htmx (no modifications required)
- **🖥️ Native WebView (no system browser needed)** — On every desktop OS vxui can host the
  UI in the platform's own web control — **WebKitGTK** on Linux, **WebView2 (Edge)** on
  Windows, and **WKWebView** on macOS — instead of launching an external browser. Each native
  window runs in its own lightweight child copy of the app (`--vxui-host`) driven over a private
  control pipe, so the framework reuses the normal WebSocket service loop and gets full process
  isolation. Select with `app.config.display.id = 'webkitgtk' | 'webview2' | 'wkwebview'`
  (or leave it `'auto'` to prefer the native backend when present).
- **🔧 Backend-to-Frontend** — Execute JavaScript from backend with `run_js()`
- **👥 Multi-Client Support** — Optional support for multiple browser clients
- **🚀 Single Executable** — Embed frontend files into binary for easy distribution

## 📋 Table of Contents

- [Introduction](#-introduction)
- [Motivation](#-motivation)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Features](#-features)
- [Architecture](#-architecture)
- [Examples](#-examples)
- [Security](#-security)
- [Browser Support](#-browser-support)
- [Contributing](#-contributing)
- [License](#-license)

## 📖 Introduction

vxui is a lightweight, cross-platform desktop UI framework that uses your browser as the display and V as the backend. Unlike traditional web frameworks, vxui:

- **No HTTP/HTTPS server** — Direct WebSocket communication
- **No build step** — Just V code and HTML files
- **No framework lock-in** — Use any frontend libraries you like

```
vxui = browser + htmx + websocket + V
```

## 💡 Motivation

1. **Every desktop has a browser** — Modern browsers offer better rendering than native GUI toolkits
2. **WebSocket > HTTP** — Why use a web server for desktop apps? WebSocket enables true bidirectional communication
3. **Full-stack V** — Write your entire app in one language

## 📦 Installation

### Prerequisites

- [V](https://vlang.io) (v0.4.0 or later)
- **Optional:** a system browser (Chrome / Chromium / Edge / Firefox) — only needed if you pick the external-browser backend. The default native WebView backend (WebKitGTK / WKWebView / WebView2) needs no browser installed.

### Install via VPM

```bash
v install --git https://github.com/kbkpbot/vxui.git
```

### Manual Installation

```bash
git clone https://github.com/kbkpbot/vxui.git ~/.vmodules/vxui
```

## 🚀 Quick Start

### 1. Create your app (`main.v`)

```v
module main

import vxui
import x.json2

struct App {
    vxui.Context
mut:
    counter int
}

@['/clicked']
fn (mut app App) clicked(message map[string]json2.Any) string {
    app.counter++
    return '<div id="counter">Count: ${app.counter}</div>'
}

fn main() {
    mut app := App{}
    app.logger.set_level(.debug)
    vxui.run(mut app, './ui/index.html') or {
        eprintln('Error: ${err}')
        exit(1)
    }
}
```

### 2. Create your UI (`ui/index.html`)

```html
<!DOCTYPE html>
<html>
<head>
    <script src="./js/htmx.js"></script>
    <script src="./js/vxui-ws.js"></script>
</head>
<body>
    <h1>Hello vxui!</h1>
    <button hx-post="/clicked" hx-swap="outerHTML">
        Click Me
    </button>
    <div id="counter">Count: 0</div>
</body>
</html>
```

### 3. Run

> ⚠️ **Use the stable compiler.** The new V3 frontend is unstable for this project
> (memory spikes on the WebKitGTK headers), so always pass `-old-compiler` first:

```bash
v -old-compiler run main.v
```

## 🏗️ Architecture

```mermaid
flowchart TB
    subgraph Frontend["Browser"]
        HTML["HTML/CSS"]
        HTMX["htmx attributes"]
        WS["vxui-ws.js"]
    end
    
    subgraph Backend["V Backend"]
        WSS["WebSocket Server"]
        Router["Router"]
        Handler["Route Handler"]
    end
    
    HTML --> HTMX
    HTMX -->|"hx-post, hx-get, etc."| WS
    WS <-->|"WebSocket (No HTTP!)"| WSS
    WSS --> Router
    Router --> Handler
    Handler -->|"HTML fragments"| WSS
    WSS -->|"Response"| WS
    WS -->|"DOM Update"| HTML
```

### How it works

1. **Start** — vxui finds a free port and starts a WebSocket server
2. **Launch** — By default opens the UI in the platform's native WebView
   (WebKitGTK on Linux, WKWebView on macOS, WebView2 on Windows). Each native
   window runs in a lightweight child copy of the app, hosted via a private
   control pipe — no system browser required. Set `config.display.id` to a
   browser id to launch an external browser instead.
3. **Connect** — Browser connects to WebSocket server via `vxui-ws.js`
4. **Interact** — User actions trigger WebSocket messages instead of HTTP requests
5. **Respond** — V handlers return HTML fragments for dynamic updates

### Native WebView backend (no system browser needed)

On every desktop OS vxui can host the UI in the platform's own web control:
**WebKitGTK** on Linux, **WKWebView** on macOS, and **WebView2 (Edge)** on
Windows. Instead of launching an external browser, vxui forks a *lightweight
child copy of the same app* in "host" mode (`--vxui-host <pipe>`) and talks to
it over a private control pipe — `HostHandshake` carries the page URL + window
geometry + token (the token never touches the command line), and `HostControl`
carries resize / move / title / close commands. The child owns its own OS window
and main thread, so the framework reuses the exact same WebSocket service loop
and gains full **process isolation**: a WebView crash can never take down the
host app, and the window closing simply shows up as a WebSocket client
disconnect that drives a clean shutdown. It also keeps single-executable
(`run_packed`) distribution simple, because the host is the same binary.

Select the backend with `app.config.display.id` (`'webkitgtk'` / `'wkwebview'`
/ `'webview2'`), or leave it `'auto'` to prefer the native backend when present.

## 📚 Examples

### Basic Form Handling

See [`examples/test/`](examples/test/) for a complete form handling example with:
- Modern dark theme with glassmorphism
- Input validation
- Dynamic updates
- Edit/Cancel workflow

### Real-time Charts

See [`examples/enchart/`](examples/enchart/) for:
- Modern dashboard UI with dark theme
- ECharts integration with gradient charts
- Real-time data streaming with live statistics
- Stat cards showing current/average/peak values

### Gallery Demo

See [`examples/gallery/`](examples/gallery/) for a comprehensive UI controls demo:
- Buttons, forms, inputs
- Progress bars, tabs, tables
- Cards, modals, notifications
- Dark mode toggle

### Element Plus Integration

See [`examples/element-plus/`](examples/element-plus/) for Vue 3 + Element Plus integration:
- Professional UI components (Button, Form, Table, Dialog, etc.)
- Backend-driven notifications via `run_js()`
- Demonstrates vxui with modern Vue 3 ecosystem

### More Examples

- [`examples/system-monitor/`](examples/system-monitor/) — real-time dashboard: backend
  pushes CPU/RAM/load via `broadcast` + `oob_update`, multi-window sync
- [`examples/chat/`](examples/chat/) — multi-window chat room: broadcast + lifecycle events
- [`examples/run-js-playground/`](examples/run-js-playground/) — backend-driven frontend:
  `run_js` demos incl. timeout/error paths
- [`examples/data-table/`](examples/data-table/) — server-side pagination/search/sort table

Run examples:

```bash
cd examples/test
v -old-compiler run main.v
```

## ✨ Features

### Security Model

The WebSocket server listens on `localhost` semantics by default and every
request is token-authenticated:

- A random token is generated per run and passed to the page via URL; clients
  must present it (`require_auth = true` is the default — messages without a
  valid token are disconnected with code 1008)
- Connections from **non-loopback interfaces are rejected** unless you
  explicitly opt in:

```v
fn main() {
    mut app := App{}
    // Allow LAN/remote browsers to connect (default: loopback only)
    app.config.allow_remote = true
    // Optional: pin the token instead of the auto-generated one
    // app.config.token = 'my-secret'
    vxui.run(mut app, './ui/index.html')!
}
```

### Execute JavaScript from Backend

Use `run_js()` to execute JavaScript in the browser and get results:

```v
// Execute on first connected client
result := app.run_js('document.title', 5000)!  // 5 second timeout
println('Page title: ${result}')

// Execute on specific client
result := app.run_js_client(client_id, 'alert("Hello!")', 3000)!

// Fire-and-forget: safe inside route handlers, result ignored
app.post_js('console.log("saved")')!
```

> Route handlers run on the connection read loop. A waiting
> `run_js(timeout > 0)` call from inside a handler deadlocks until timeout —
> use `post_js()` / `post_js_client()` there.

### Multi-Client Support

Enable multiple browser connections:

```v
fn main() {
    mut app := App{}
    app.multi_client = true  // Allow multiple clients
    vxui.run(mut app, './ui/index.html')!
}

// In your handlers:
fn (mut app App) broadcast_msg(msg map[string]json2.Any) string {
    // Get all connected clients
    clients := app.get_clients()
    
    // Broadcast to all
    app.broadcast('<div hx-swap-oob="true">Server update</div>')!
    
    return '<div>Sent to ${clients.len} clients</div>'
}
```

### Window Management

Configure browser window size via `WindowConfig`:

```v
fn main() {
    mut app := App{}
    app.Context.config.window = vxui.WindowConfig{
        width:  1200
        height: 800
    }
    vxui.run(mut app, './ui/index.html')!
}
```

### Single Executable Distribution

Embed frontend files into the binary for easy distribution:

```v
module main

import vxui

// Embed frontend files at compile time
const index_html = $embed_file('ui/index.html')
const app_js = $embed_file('ui/app.js')
const style_css = $embed_file('ui/style.css')

struct App {
    vxui.Context
}

fn main() {
    mut app := App{}
    
    // Create packed app with embedded files
    mut packed := vxui.new_packed_app()
    packed.add_file_string('index.html', index_html.to_string())
    packed.add_file_string('app.js', app_js.to_string())
    packed.add_file_string('style.css', style_css.to_string())
    
    // Run with packed resources
    vxui.run_packed(mut app, mut packed, 'index.html')!
}
```

Build single executable:
```bash
v -old-compiler -prod main.v           # Production build (~1.4 MB)
v -old-compiler -prod -compress main.v # Compressed build (smaller)
```

Result: A single `.exe` file containing all frontend assets!

## 🔒 Security

vxui includes several security features:

- **Token Authentication** — Auto-generated security token for client verification
- **XSS Protection** — Built-in HTML/JS escaping functions
- **Path Traversal Prevention** — Input sanitization
- **No External Network** — WebSocket only binds to localhost

### Token Authentication

Every connection requires token verification:

```v
fn main() {
    mut app := App{}
    // Token is auto-generated, or set manually:
    // app.token = 'my-secret-token'
    
    // Get token for debugging
    println('Token: ${app.get_token()}')
    
    vxui.run(mut app, './ui/index.html')!
}
```

### Safe Output Example

```v
import vxui

fn (mut app App) handler(msg map[string]json2.Any) string {
    user_input := msg['name'] or { '' }.str()
    // escape before injecting into a JavaScript context
    safe := vxui.escape_js(user_input)
    app.run_js('console.log("${safe}")', 1000) or {}
    return '<div>Hello</div>'
}
```

### Security Best Practices

1. **Always validate input** — Use `sanitize_path()` for file paths
2. **Escape output** — Use `escape_js()` when injecting values into JavaScript contexts
3. **Keep tokens secure** — Tokens are auto-generated and passed via URL
4. **Limit JS execution** — Configure `js_sandbox` settings appropriately

```v
fn main() {
    mut app := App{}
    // Enhanced security configuration
    app.config.js_sandbox = vxui.JsSandboxConfig{
        enabled: true
        timeout_ms: 3000
        max_result_size: 1024 * 100  // 100KB
        allow_eval: false
    }
    vxui.run(mut app, './ui/index.html')!
}
```

## 🔄 Migration Guide

### From v0.5.x to v0.6.0

**Deprecated fields removed:**
- `app.token` → Use `app.config.token`
- `app.multi_client` → Use `app.config.multi_client`

```v
// Before (v0.5.x)
mut app := App{}
app.token = 'my-token'
app.multi_client = true

// After (v0.6.0)
mut app := App{}
app.config.token = 'my-token'
app.config.multi_client = true
```

### From v0.4.x to v0.5.0

**Configuration unified:**
- All settings now in `app.config`
- Window, browser, JS sandbox settings available

```v
// Before
app.window = vxui.WindowConfig{width: 1200, height: 800}

// After
app.config.window = vxui.WindowConfig{width: 1200, height: 800}
```

## 🌍 Browser Support

vxui auto-detects and supports:

| Browser | Linux | macOS | Windows |
|---------|-------|-------|---------|
| Chrome | ✅ | ✅ | ✅ |
| Chromium | ✅ | ✅ | ❌ |
| Edge | ✅ | ✅ | ✅ |
| Firefox | ✅ | ✅ | ✅ |
| Brave | ✅ | ❌ | ❌ |

> **Prefer zero-install?** Leave `config.display.id = 'auto'` (the default): on Linux/macOS/Windows
> vxui automatically hosts the UI in the OS-native WebView (WebKitGTK / WKWebView / WebView2) in a
> separate lightweight child process — no browser install required. Pick an explicit browser id
> above only when you want the external-browser path.

## 📖 Documentation

- [API Reference](doc/vxui.md) — Auto-generated from source
- [Architecture Guide](doc/AGENTS.md) — Internal design documentation

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](doc/CONTRIBUTING.md) for guidelines.

### Development

```bash
# Clone the repo
git clone https://github.com/kbkpbot/vxui.git
cd vxui

# Run tests
v test vxui_test.v

# Format code
v fmt -w .
```

## 🛡️ License

This project is licensed under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- [V Language](https://vlang.io/) — The amazing language powering vxui
- [htmx](https://htmx.org/) — The frontend library for dynamic HTML

## ⚠️ Alpha Notice

vxui is currently in **alpha** stage. APIs may change, and some features are still being developed. Please report any issues you encounter!

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/kbkpbot">kbkpbot</a> and contributors</sub>
</div>