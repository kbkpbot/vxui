module main

import vxui
import time
import x.json2

// Demonstrates: run_js, run_js_client, js_timeout error handling,
// oob_update console log sync

const default_page_html_file = './ui/index.html'

struct App {
	vxui.Context
mut:
	seq int
}

// param pulls a string parameter from the request
fn param(message map[string]json2.Any, key string) string {
	if params := message['parameters'] {
		if v := params.as_map()[key] {
			return v.str()
		}
	}
	return ''
}

// log_entry builds an OOB console line appended to #console
fn log_entry(ok bool, title string, detail string) string {
	cls := if ok { 'ok' } else { 'err' }
	ts := time.now().format_ss()
	return '<div id="console" hx-swap-oob="beforeend:#console">
		<div class="entry ${cls}">
			<span class="ts">${ts}</span><span class="title">${title}</span>
			<pre>${detail.replace_each(['&', '&amp;', '<', '&lt;', '>', '&gt;'])}</pre>
		</div></div>'
}

// run_and_log executes js on target client and logs the outcome to ALL windows.
// Must not return string: fire_call dispatches every string-returning method.
// The waiting call runs in a spawned coroutine: route handlers execute on the
// connection read loop, and a blocking run_js() there would deadlock until
// timeout because the js_result it waits for arrives on that same loop
// (see AGENTS.md "Routing rules").
fn (mut app App) run_and_log(title string, js string, timeout_ms int, cid string) {
	spawn fn [mut app, title, js, timeout_ms, cid] () {
		mut result := ''
		mut ok := true
		if cid != '' {
			result = app.run_js_client(cid, js, timeout_ms) or {
				ok = false
				err.msg()
			}
		} else {
			result = app.run_js(js, timeout_ms) or {
				ok = false
				err.msg()
			}
		}
		payload := {'cmd': 'oob_update', 'html': log_entry(ok, title, result)}
		app.broadcast(json2.encode(payload)) or {}
	}()
}

@['/title']
fn (mut app App) do_title(message map[string]json2.Any) string {
	app.run_and_log('读取页面标题', 'document.title', 3000, param(message, 'cid'))
	return ''
}

@['/scroll-top']
fn (mut app App) do_scroll(message map[string]json2.Any) string {
	app.run_and_log('平滑滚顶', 'window.scrollTo({top:0, behavior:\'smooth\'}), \'scrolled\'',
		3000, param(message, 'cid'))
	return ''
}

@['/toast']
fn (mut app App) do_toast(message map[string]json2.Any) string {
	js := "(()=>{const t=document.createElement('div');t.textContent='来自后端的消息 '+new Date().toLocaleTimeString();t.style.cssText='position:fixed;top:20px;left:50%;transform:translateX(-50%);background:#11998e;color:#fff;padding:10px 18px;border-radius:8px;z-index:99999';document.body.appendChild(t);setTimeout(()=>t.remove(),2500);return 'toast shown'})()"
	app.run_and_log('弹出 Toast', js, 3000, param(message, 'cid'))
	return ''
}

@['/accent']
fn (mut app App) do_accent(message map[string]json2.Any) string {
	js := "(document.documentElement.style.setProperty('--accent', ['#38ef7d','#4fc3f7','#ffb74d','#eb3349'][Math.floor(Math.random()*4)]), 'accent changed')"
	app.run_and_log('随机主题色', js, 3000, param(message, 'cid'))
	return ''
}

@['/ua']
fn (mut app App) do_ua(message map[string]json2.Any) string {
	app.run_and_log('获取 UA', 'navigator.userAgent', 3000, param(message, 'cid'))
	return ''
}

@['/timeout-demo']
fn (mut app App) do_timeout(message map[string]json2.Any) string {
	js := 'const t0 = Date.now(); while (Date.now() - t0 < 8000) {} "done"'
	app.run_and_log('超时演示（预期失败）', js, 2000, param(message, 'cid'))
	return ''
}

fn main() {
	mut app := App{}
	app.config.app_name = 'run-js-playground'
	app.config.close_timer_ms = 60000
	// setTimeout is essential for UI scripts (auto-dismissing toasts etc.);
	// opt out of the default blanket timer ban for this playground.
	mut forbidden := app.config.js_sandbox.forbidden_patterns.clone()
	forbidden = forbidden.filter(it != 'setTimeout(' && it != 'setInterval(')
	app.config.js_sandbox.forbidden_patterns = forbidden

	vxui.run(mut app, default_page_html_file)!
}
