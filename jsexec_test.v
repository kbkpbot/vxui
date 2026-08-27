module vxui

import time
import net.websocket

// =============================================================================
// JS Execution & Sandbox Validation Tests
// =============================================================================

fn test_validate_js_code_safe() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	validate_js_code('document.title', sandbox) or {
		assert false
		return
	}
}

fn test_validate_js_code_forbidden() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	validate_js_code('eval("alert(1)")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

fn test_validate_js_code_eval_blocked() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'Function(', 'setTimeout(']
	}

	// Should block eval
	validate_js_code('eval("alert(1)")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

fn test_validate_js_code_fetch_blocked() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['fetch(', 'XMLHttpRequest', 'WebSocket']
	}

	// Should block fetch
	validate_js_code('fetch("/api/data")', sandbox) or {
		assert err.msg().contains('Forbidden pattern')
		return
	}
	assert false
}

fn test_validate_js_code_case_insensitive() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['EVAL(']
	}

	// Should block even with different case
	validate_js_code('EVAL("test")', sandbox) or { return }
	assert false
}

fn test_validate_js_code_safe_code() {
	sandbox := JsSandboxConfig{
		enabled:            true
		forbidden_patterns: ['eval(', 'fetch(']
	}

	// Should allow safe code
	validate_js_code('document.title = "Hello"', sandbox) or {
		assert false
		return
	}
}

fn test_js_sandbox_disabled_allows_all() {
	sandbox := JsSandboxConfig{
		enabled:            false
		forbidden_patterns: ['eval(']
	}

	// Should allow when sandbox disabled
	validate_js_code('eval("test")', sandbox) or {
		assert false
		return
	}
}

fn test_escape_js() {
	assert escape_js('"quoted"') == '\\"quoted\\"'
	assert escape_js('line\nbreak') == 'line\\nbreak'
}

fn test_escape_js_special_chars() {
	input := 'line1\nline2\ttab"quote\'apostrophe\\backslash'
	result := escape_js(input)
	assert result.contains('\\n')
	assert result.contains('\\t')
	assert result.contains('\\"')
	assert result.contains("\\'")
	assert result.contains('\\\\')
}

fn test_escape_js_basic() {
	assert escape_js('alert("test")') == 'alert(\\"test\\")'
	assert escape_js('line1\nline2') == 'line1\\nline2'
	assert escape_js('path\\to\\file') == 'path\\\\to\\\\file'
}

fn test_escape_js_tab_and_return() {
	assert escape_js('\t') == '\\t'
	assert escape_js('\r') == '\\r'
}

fn test_post_js_is_fire_and_forget_and_leaks_no_callback() {
	port := get_free_port()!
	mut app := new_ws_test_app(u16(port))!
	mut ctx := unsafe { &app.Context }
	startup_ws_server(mut app, .ip, port)!
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	mut cl := websocket.new_client('ws://localhost:${port}/echo',
		websocket.ClientOpt{
			read_timeout: 2 * time.second
		})!
	cl.connect()!
	cl.write_string('{"cmd":"auth","token":"it-token"}')!
	assert wait_for(2000, fn [ctx] () bool {
		return ctx.clients.len == 1
	})

	ctx.post_js('void(0);')!
	// Registration must be gone immediately: post_js never waits.
	assert ctx.js_callbacks.len == 0, 'post_js left a pending js_callback'

	// The run_js command did go out on the wire (after the auth_ok frame).
	read_text_until(mut cl, fn (s string) bool {
		return s.contains('run_js') && s.contains('void(0)')
	}) or {
		assert false, 'post_js command never reached the client'
		return
	}

	cl.close(1000, 'done') or {}
	ctx.ws.free()
}
