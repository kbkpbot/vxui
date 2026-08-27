module vxui

import os
import time
import x.json2

// =============================================================================
// Display / Window Management
// =============================================================================

// open_window opens an additional display window using the current window
// configuration and security token.
pub fn (mut ctx Context) open_window(html_filename string) ! {
	ctx.open_window_with(html_filename, ctx.config.window) or { return err }
}

// open_window_with opens an additional display window with an explicit window
// configuration. Backend-specific options come from ctx.config.browser.
pub fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) ! {
	cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  window.width
		height: window.height
		x:      window.x
		y:      window.y
		title:  window.title
	}
	sess := ctx.display.spawn(html_filename, cfg)!

	// Keep the primary session in `display_session` only; secondary windows
	// go into `display_sessions`. Never store the same instance in both, or
	// close_displays() would close it twice (a double-free for in-process
	// WebView backends).
	if ctx.display_session == none {
		ctx.display_session = sess
	} else {
		ctx.display_sessions << sess
	}
}

// set_js_sandbox configures JavaScript execution security
pub fn (mut ctx Context) set_js_sandbox(config JsSandboxConfig) {
	ctx.config.js_sandbox = config
}

// set_browser_config configures browser startup options
pub fn (mut ctx Context) set_browser_config(config BrowserConfig) {
	ctx.config.browser = config
}

// set_webview_config configures WebView/WebKit backend options (used when
// display.kind == .webview).
pub fn (mut ctx Context) set_webview_config(config WebViewConfig) {
	ctx.config.webview = config
}

// close_displays tears down all live display sessions. No-op for the detached
// external-browser backend; REQUIRED for native WebView host backends so the
// host child process is signalled to close and its pipe/handle is released on
// shutdown.
pub fn (mut ctx Context) close_displays() {
	for mut s in ctx.display_sessions {
		s.close() or {}
	}
	if mut s := ctx.display_session {
		s.close() or {}
	}
	ctx.display_sessions = []
	ctx.display_session = none
}

// get_port returns the WebSocket port
pub fn (ctx Context) get_port() u16 {
	return ctx.ws_port
}

// get_token returns the security token
pub fn (ctx Context) get_token() string {
	return ctx.config.token
}

// get_config returns the current configuration
pub fn (ctx Context) get_config() Config {
	return ctx.config
}

// =============================================================================
// Hot Reload Support
// =============================================================================

// trigger_hot_reload sends a reload command to all connected clients.
// Per-client write failures are skipped, see broadcast().
pub fn (mut ctx Context) trigger_hot_reload() ! {
	ctx.broadcast_cmd('reload', {
		'timestamp': json2.Any(time.now().unix_milli())
	})
}

// scan_file_mtimes scans directories and returns file modification times
fn scan_file_mtimes(dirs []string) map[string]time.Time {
	mut mtimes := map[string]time.Time{}
	for dir in dirs {
		scan_dir_mtimes(dir, mut mtimes)
	}
	return mtimes
}

// scan_dir_mtimes recursively scans a directory for file modification times
fn scan_dir_mtimes(dir string, mut mtimes map[string]time.Time) {
	files := os.ls(dir) or { return }
	for file in files {
		path := os.join_path(dir, file)
		if os.is_dir(path) {
			// Skip hidden directories and common ignore patterns
			if !file.starts_with('.') && file != 'node_modules' && file != 'dist' && file != 'build' {
				scan_dir_mtimes(path, mut mtimes)
			}
		} else {
			// Only watch relevant file types
			ext := file.all_after_last('.').to_lower()
			if ext in ['html', 'htm', 'css', 'js', 'ts', 'vue', 'svelte', 'json', 'svg', 'png',
				'jpg', 'gif'] {
				info := os.stat(path) or { continue }
				mtimes[path] = time.unix(info.mtime)
			}
		}
	}
}

// has_files_changed compares two mtimes maps and returns true if any file changed
fn has_files_changed(old map[string]time.Time, new map[string]time.Time) bool {
	// Check for new or modified files
	for path, new_time in new {
		old_time := old[path] or { return true } // New file
		if new_time.unix_milli() != old_time.unix_milli() {
			return true
		}
	}
	// Check for deleted files (only if old had more files)
	if old.len > new.len {
		return true
	}
	return false
}
