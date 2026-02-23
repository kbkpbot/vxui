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

<img src="vxui.png" alt="vxui Architecture" width="600">

</div>

---

## 🚀 Features

- **⚡ WebSocket-Powered** — Real-time bidirectional communication without HTTP overhead
- **🎨 Use Your Browser** — Leverage modern web technologies for beautiful UIs
- **🔒 Secure by Default** — Built-in XSS protection and path traversal prevention
- **🌐 Cross-Platform** — Linux, macOS, and Windows support with auto browser detection
- **📦 Lightweight** — Pure V implementation, no external dependencies
- **🎯 htmx Integration** — Seamless integration with htmx for dynamic HTML updates

## 📋 Table of Contents

- [Introduction](#-introduction)
- [Motivation](#-motivation)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Architecture](#-architecture)
- [Examples](#-examples)
- [Security](#-security)
- [Contributing](#-contributing)
- [License](#-license)

## 📖 Introduction

vxui is a lightweight, cross-platform desktop UI framework that uses your browser as the display and V as the backend. Unlike traditional web frameworks, vxui:

- **No HTTP/HTTPS server** — Direct WebSocket communication
- **No build step** — Just V code and HTML files
- **No framework lock-in** — Use any frontend libraries you like

```
vxui = browser + htmx/webui + websocket + V
```

## 💡 Motivation

1. **Every desktop has a browser** — Modern browsers offer better rendering than native GUI toolkits
2. **WebSocket > HTTP** — Why use a web server for desktop apps? WebSocket enables true bidirectional communication
3. **Full-stack V** — Write your entire app in one language

## 📦 Installation

### Prerequisites

- [V](https://vlang.io) (v0.4.0 or later)
- Chrome, Chromium, Edge, or Firefox

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
    <script src="./js/ajaxhook.js"></script>
    <script src="./js/vxui-htmx.js"></script>
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

```bash
v run main.v
```

## 🏗️ Architecture

```
┌─────────────────┐      WebSocket      ┌─────────────────┐
│   Browser       │ ◄─────────────────► │   V Backend     │
│  (HTML/CSS/JS)  │    (No HTTP!)       │  (WebSocket     │
│                 │                     │   Server)       │
└─────────────────┘                     └─────────────────┘
       │                                          │
       │ htmx events                              │ Method calls
       ▼                                          ▼
┌─────────────────┐                     ┌─────────────────┐
│  vxui-htmx.js   │                     │   Route Handler │
│  (Intercepts    │                     │   (Your code!)  │
│   AJAX calls)   │                     │                 │
└─────────────────┘                     └─────────────────┘
```

### How it works

1. **Start** — vxui finds a free port and starts a WebSocket server
2. **Launch** — Detects and launches your system browser with the HTML file
3. **Connect** — Browser connects to WebSocket server via `vxui-htmx.js`
4. **Interact** — User actions trigger WebSocket messages instead of HTTP requests
5. **Respond** — V handlers return HTML fragments for dynamic updates

## 📚 Examples

### Basic Form Handling

See [`examples/test/`](examples/test/) for a complete form handling example with:
- Input validation
- Dynamic updates
- Edit/Cancel workflow

### Real-time Charts

See [`examples/enchart/`](examples/enchart/) for:
- ECharts integration
- Real-time data streaming
- JSON API endpoints

Run examples:

```bash
cd examples/test
v run main.v
```

## 🔒 Security

vxui includes several security features:

- **XSS Protection** — Built-in HTML/JS escaping functions
- **Path Traversal Prevention** — Input sanitization
- **No External Network** — WebSocket only binds to localhost

### Safe Output Example

```v
import vxui

fn (mut app App) handler(msg map[string]json2.Any) string {
    user_input := msg['name'] or { '' }.str()
    safe := vxui.escape_html(user_input)
    return '<div>Hello ${safe}</div>'
}
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

## 📖 Documentation

- [API Reference](doc/vxui.md) — Auto-generated from source
- [Architecture Guide](AGENTS.md) — Internal design documentation

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

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
- [ajaxhook](https://github.com/wendux/ajax-hook) — AJAX interception library

## ⚠️ Alpha Notice

vxui is currently in **alpha** stage. APIs may change, and some features are still being developed. Please report any issues you encounter!

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/kbkpbot">kbkpbot</a> and contributors</sub>
</div>