module vxui

import x.json2

// ---------------------------------------------------------------------------
// Multi-window native path: verify open_window_with / close_displays
// bookkeeping without spawning a real GUI window.
// ---------------------------------------------------------------------------

struct FakeSession {
mut:
	closed  bool
	counter &int
}

fn (mut s FakeSession) close() ! {
	if s.counter != unsafe { nil } {
		unsafe {
			*(s.counter) = *(s.counter) + 1
		}
	}
	s.closed = true
}
fn (mut s FakeSession) set_size(w int, h int) {}
fn (mut s FakeSession) set_title(t string) {}
fn (mut s FakeSession) set_position(x int, y int) {}
fn (mut s FakeSession) wait_closed() ! {}
fn (mut s FakeSession) is_closed() bool {
	return s.closed
}

struct FakeDisplay {
mut:
	counter &int
}

fn (mut d FakeDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
	return FakeSession{ counter: d.counter }
}

fn test_open_window_multi_session_bookkeeping() {
	mut count := 0
	mut ctx := Context{ config: Config{} }
	ctx.display = FakeDisplay{ counter: &count }

	// First window: primary session lives in `display_session` only.
	ctx.open_window_with('a.html', WindowConfig{ width: 100, height: 100 }) or { panic(err.msg()) }
	assert ctx.display_session != none
	assert ctx.display_sessions.len == 0

	// Second window: must NOT reuse display_session (that would double-free on
	// close); it must go into `display_sessions`.
	ctx.open_window_with('b.html', WindowConfig{ width: 200, height: 200 }) or { panic(err.msg()) }
	assert ctx.display_sessions.len == 1
	assert ctx.display_session != none

	// close_displays must tear down both windows exactly once each.
	ctx.close_displays()
	assert ctx.display_sessions.len == 0
	assert count == 2
}

fn test_new_display_browser_returns_backend() {
	d := new_display('browser', &Config{ browser: BrowserConfig{} }) or { panic(err.msg()) }
	match d {
		DisplayBackend { assert d.family == .process; assert d.id == 'browser' }
		else { assert false, 'expected DisplayBackend' }
	}
}

fn test_new_display_webview_constructs() {
	d := new_display('webview2', &Config{}) or { panic(err.msg()) }
	match d {
		DisplayBackend { assert d.family == .embedded; assert d.id == 'webview2' }
		else { assert false, 'expected DisplayBackend' }
	}
}

fn test_launch_url_with_token() {
	url := launch_url('/tmp/index.html', 8080, 'secret')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080&vxui_token=secret'
}

fn test_launch_url_no_token() {
	url := launch_url('/tmp/index.html', 8080, '')
	assert url == 'file:///tmp/index.html?vxui_ws_port=8080'
}

fn test_resolve_backend_id_passthrough_and_auto() {
	// Explicit id passes through untouched.
	cfg := Config{
		display: DisplayConfig{ id: 'webkitgtk' }
	}
	assert resolve_backend_id(&cfg, '') == 'webkitgtk'
	assert resolve_backend_id(&cfg, 'chrome') == 'chrome'
	// Empty/'auto' prefers this platform's native WebView when the build has
	// one (Linux: webkitgtk); otherwise it falls back to a browser backend.
	mut auto_cfg := Config{}
	resolved := resolve_backend_id(&auto_cfg, '')
	native := embedded_native_id()
	if native != '' {
		assert resolved == native
		assert backend_family(resolved) == .embedded
	} else {
		assert resolved != '' && resolved != 'auto'
		assert backend_family(resolved) == .process
	}
}

fn test_embedded_spawn_unsupported_id_errors() {
	// An embedded id this platform does not implement must error clearly,
	// never attempt to open a window.
	cfg := DisplaySessionConfig{}
	embedded_spawn('definitely-not-a-backend', '/nonexistent.html', cfg) or { return }
	assert false, 'expected embedded_spawn to fail for an unsupported id'
}

fn test_host_handshake_json_roundtrip() {
	// The handshake the parent writes to the control pipe must survive a
	// JSON encode/decode round-trip byte-for-byte; the host reads it back
	// with the exact same struct.
	hs := HostHandshake{
		url:    'file:///tmp/index.html?vxui_ws_port=8080&vxui_token=secret'
		token:  'secret'
		width:  1200
		height: 800
		x:      10
		y:      20
		title:  'vxui App'
	}
	encoded := json2.encode(hs)
	decoded := json2.decode[HostHandshake](encoded) or { panic('decode failed: ${err}') }
	assert decoded.url == hs.url
	assert decoded.token == hs.token
	assert decoded.width == hs.width
	assert decoded.height == hs.height
	assert decoded.x == hs.x
	assert decoded.y == hs.y
	assert decoded.title == hs.title
}

fn test_host_control_json_roundtrip() {
	// Every window op (resize/move/title/close) is forwarded as a JSON-line
	// HostControl; it must decode back to the same command + geometry.
	cases := [
		HostControl{ cmd: 'resize', w: 640, h: 480 },
		HostControl{ cmd: 'move', x: 100, y: 200 },
		HostControl{ cmd: 'title', title: 'New Title' },
		HostControl{ cmd: 'close' },
	]
	for c in cases {
		encoded := json2.encode(c)
		decoded := json2.decode[HostControl](encoded) or { panic('decode failed: ${err}') }
		assert decoded.cmd == c.cmd
		assert decoded.w == c.w
		assert decoded.h == c.h
		assert decoded.x == c.x
		assert decoded.y == c.y
		assert decoded.title == c.title
	}
}
