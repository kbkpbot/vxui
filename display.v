module vxui

// DisplayKind selects which display backend renders the UI.
pub enum DisplayKind {
	browser // external system browser (default)
	webview // reserved: in-process platform WebView/WebKit (not yet implemented)
}

// DisplayConfig selects and scopes the display backend.
pub struct DisplayConfig {
pub mut:
	kind DisplayKind = .browser
}

// DisplaySessionConfig carries the generic, backend-agnostic parameters needed
// to present one UI window. Backend-specific options (e.g. Chromium window
// mode, WebView runtime flags) live on the backend's own config and are merged
// by the backend during spawn — the core never hardcodes them.
pub struct DisplaySessionConfig {
	port   u16
	token  string
	width  int
	height int
	x      int
	y      int
	title  string
}

// DisplaySession is a live, presented window. It exposes only what a backend
// can meaningfully do after launch; all request/response traffic flows over
// WebSocket and never touches this interface.
pub interface DisplaySession {
mut:
	close() !
	set_size(w int, h int)
	set_title(t string)
	set_position(x int, y int)
}

// Display is the pluggable backend that turns an HTML file into one or more
// presented windows. The core talks to the page exclusively via WebSocket; the
// Display only has to get the page on screen.
pub interface Display {
mut:
	spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}

// BrowserDisplay launches an external browser process. Defined fully in Task 2.
pub struct BrowserDisplay {
	config &BrowserConfig
}

// spawn is a Task 1 placeholder; the real browser-launch logic lands in Task 2.
pub fn (mut b BrowserDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return error('BrowserDisplay.spawn not implemented yet (Task 2)')
}

// new_display constructs the configured backend.
pub fn new_display(kind DisplayKind) !Display {
	match kind {
		.browser {
			return BrowserDisplay{
				config: &BrowserConfig{}
			}
		}
		.webview {
			return error('WebView display backend is not implemented yet')
		}
	}
}
