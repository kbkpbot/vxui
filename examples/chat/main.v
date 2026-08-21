module main

import vxui
import sync
import x.json2

// Demonstrates: multi_client, broadcast, get_clients, on_event lifecycle hooks

const default_page_html_file = './ui/index.html'

struct App {
	vxui.Context
mut:
	mu        sync.RwMutex
	nicknames map[string]string
}

// msg_param pulls a string out of the request parameters object
fn msg_param(message map[string]json2.Any, key string) string {
	if params := message['parameters'] {
		m := params.as_map()
		if v := m[key] {
			return v.str()
		}
	}
	return ''
}

// escape_html escapes user supplied text before embedding into HTML
fn esc(s string) string {
	return s.replace_each(['&', '&amp;', '<', '&lt;', '>', '&gt;', '"', '&quot;', "'", '&#x27;'])
}

// bubble renders one chat bubble element
fn bubble(kind string, text string) string {
	return '<div class="msg ${kind}">${text}</div>'
}

// users_fragment renders the OOB online-user panel
fn (mut app App) users_fragment() string {
	app.mu.rlock()
	defer {
		app.mu.unlock()
	}
	mut lis := ''
	for cid, nick in app.nicknames {
		lis += '<li data-cid="${cid}">${esc(nick)}</li>'
	}
	count := app.nicknames.len
	return '<ul id="user-list" hx-swap-oob="true">${lis}<li class="count">${count} 人在线</li></ul>'
}

// system_broadcast composes a system line plus refreshed user list and sends
// it to every connected window (including the originator).
fn (mut app App) system_broadcast(html string) {
	payload := {'cmd': 'oob_update', 'html': html + app.users_fragment()}
	app.broadcast(json2.encode(payload)) or {}
}

@['/join']
fn (mut app App) join(message map[string]json2.Any) string {
	nick := esc(msg_param(message, 'nick'))
	cid := esc(msg_param(message, 'cid'))
	if nick == '' || cid == '' {
		return ''
	}
	app.mu.lock()
	app.nicknames[cid] = nick
	app.mu.unlock()
	app.system_broadcast(bubble('system', '${nick} 加入了聊天室'))
	return ''
}

@['/send']
fn (mut app App) send(message map[string]json2.Any) string {
	text := esc(msg_param(message, 'text'))
	cid := esc(msg_param(message, 'cid'))
	if text == '' || cid == '' {
		return ''
	}
	app.mu.rlock()
	nick := app.nicknames[cid] or { '匿名' }
	app.mu.runlock()
	app.system_broadcast(bubble('chat', '<b>${nick}：</b>${text}'))
	return ''
}

fn main() {
	mut app := App{}
	app.nicknames = map[string]string{}
	app.config.app_name = 'chat-room'
	app.config.multi_client = true
	app.config.close_timer_ms = 60000

	app.on_event(.client_disconnected, fn [mut app] (e vxui.EventData) {
		if e.client_id == '' {
			return
		}
		app.mu.lock()
		nick := app.nicknames[e.client_id] or {
			app.mu.unlock()
			return
		}
		app.nicknames.delete(e.client_id)
		app.mu.unlock()
		app.system_broadcast(bubble('system', '${esc(nick)} 离开了聊天室'))
	})

	vxui.run(mut app, default_page_html_file)!
}
