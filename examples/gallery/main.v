module main

import vxui
import os
import x.json2
import rand
import time

// Gallery App demonstrates various desktop UI controls
struct App {
	vxui.Context
mut:
	// Form state
	input_text    string
	textarea_text string = 'Multi-line text\nLine 2\nLine 3'
	selected      string = 'option2'
	checked       bool   = true
	radio_value   string = 'radio1'
	slider_value  int    = 50
	toggle        bool   = true
	
	// Progress
	progress int
	
	// Tabs
	active_tab string = 'tab1'
	
	// Table data
	items []Item
	
	// Notifications
	notifications []Notification
}

struct Item {
	id    int
	name  string
	value int
	status string
}

struct Notification {
	id      int
	message string
	type_   string
}

fn main() {
	mut html_filename := './ui/index.html'
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	mut app := App{}
	app.config.close_timer_ms = 1000
	app.logger.set_level(.debug)
	app.logger.set_output_stream(os.stderr())
	app.logger.set_short_tag(true)
	
	// Initialize sample data
	app.items = [
		Item{1, 'Alpha', 100, 'active'},
		Item{2, 'Beta', 200, 'pending'},
		Item{3, 'Gamma', 300, 'active'},
		Item{4, 'Delta', 400, 'inactive'},
		Item{5, 'Epsilon', 500, 'active'},
	]

	vxui.run(mut app, html_filename) or {
		eprintln('Error: ${err}')
		exit(1)
	}
}

// =============================================================================
// Button handlers
// =============================================================================

@['/button/click']
fn (mut app App) button_click(message map[string]json2.Any) string {
	app.notify('Button clicked!', 'info')
	return '<span id="btn-result" hx-swap-oob="true">Clicked at ${time.now().unix()}</span>'
}

@['/button/primary']
fn (mut app App) button_primary(message map[string]json2.Any) string {
	app.notify('Primary action executed', 'success')
	return ''
}

@['/button/danger']
fn (mut app App) button_danger(message map[string]json2.Any) string {
	app.notify('Dangerous action!', 'error')
	return ''
}

// =============================================================================
// Form handlers
// =============================================================================

@['/form/input']
fn (mut app App) form_input(message map[string]json2.Any) string {
	params := get_params(message)
	if text := params['text'] {
		app.input_text = text.str()
	}
	return '<span id="input-result" hx-swap-oob="true">You typed: ${app.input_text}</span>'
}

@['/form/textarea']
fn (mut app App) form_textarea(message map[string]json2.Any) string {
	params := get_params(message)
	if text := params['text'] {
		app.textarea_text = text.str()
	}
	line_count := app.textarea_text.split('\n').len
	return '<span id="textarea-result" hx-swap-oob="true">${line_count} lines</span>'
}

@['/form/select']
fn (mut app App) form_select(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['selected'] {
		app.selected = val.str()
	}
	return '<span id="select-result" hx-swap-oob="true">Selected: ${app.selected}</span>'
}

@['/form/checkbox']
fn (mut app App) form_checkbox(message map[string]json2.Any) string {
	params := get_params(message)
	checked_val := params['checked'] or { json2.Null{} }
	app.checked = checked_val.str() == 'on'
	return '<span id="checkbox-result" hx-swap-oob="true">Checked: ${app.checked}</span>'
}

@['/form/radio']
fn (mut app App) form_radio(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.radio_value = val.str()
	}
	return '<span id="radio-result" hx-swap-oob="true">Selected: ${app.radio_value}</span>'
}

@['/form/slider']
fn (mut app App) form_slider(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.slider_value = val.int()
	}
	return '<span id="slider-result" hx-swap-oob="true">Value: ${app.slider_value}</span>'
}

@['/form/toggle']
fn (mut app App) form_toggle(message map[string]json2.Any) string {
	app.toggle = !app.toggle
	active_class := if app.toggle { 'active' } else { '' }
	text := if app.toggle { 'ON' } else { 'OFF' }
	return '<span id="toggle-btn" hx-swap-oob="true" class="toggle ${active_class}" hx-post="/form/toggle">${text}</span><span id="toggle-result" hx-swap-oob="true">State: ${app.toggle}</span>'
}

// =============================================================================
// Progress
// =============================================================================

@['/progress/start']
fn (mut app App) progress_start(message map[string]json2.Any) string {
	app.progress = 0
	return app.render_progress()
}

@['/progress/increment']
fn (mut app App) progress_increment(message map[string]json2.Any) string {
	app.progress = if app.progress >= 100 { 0 } else { app.progress + 10 }
	return app.render_progress()
}

fn (app App) render_progress() string {
	return '<div id="progress-bar" hx-swap-oob="true" class="progress-bar" style="width: ${app.progress}%"></div><span id="progress-result" hx-swap-oob="true">${app.progress}%</span>'
}

// =============================================================================
// Tabs
// =============================================================================

@['/tabs/switch']
fn (mut app App) tabs_switch(message map[string]json2.Any) string {
	params := get_params(message)
	if tab := params['tab'] {
		app.active_tab = tab.str()
	}
	return app.render_tabs()
}

fn (app App) render_tabs() string {
	mut html := '<div id="tabs-container" hx-swap-oob="true">
		<div class="tabs">
			<button class="tab ${if app.active_tab == 'tab1' { 'active' } else { '' }}" hx-post="/tabs/switch" hx-vals=\'{"tab":"tab1"}\'>Tab 1</button>
			<button class="tab ${if app.active_tab == 'tab2' { 'active' } else { '' }}" hx-post="/tabs/switch" hx-vals=\'{"tab":"tab2"}\'>Tab 2</button>
			<button class="tab ${if app.active_tab == 'tab3' { 'active' } else { '' }}" hx-post="/tabs/switch" hx-vals=\'{"tab":"tab3"}\'>Tab 3</button>
		</div>
		<div class="tab-content">'
	
	match app.active_tab {
		'tab1' {
			html += '<h3>Tab 1 Content</h3><p>This is the first tab panel.</p>'
		}
		'tab2' {
			html += '<h3>Tab 2 Content</h3><p>This is the second tab panel.</p>'
		}
		'tab3' {
			html += '<h3>Tab 3 Content</h3><p>This is the third tab panel.</p>'
		}
		else {
			html += '<p>Select a tab</p>'
		}
	}
	
	html += '</div></div>'
	return html
}

// =============================================================================
// Table
// =============================================================================

@['/table/refresh']
fn (mut app App) table_refresh(message map[string]json2.Any) string {
	return app.render_table()
}

@['/table/add']
fn (mut app App) table_add(message map[string]json2.Any) string {
	id := if app.items.len > 0 { app.items.last().id + 1 } else { 1 }
	statuses := ['active', 'pending', 'inactive']
	app.items << Item{
		id:     id
		name:   'Item ${id}'
		value:  rand.int_in_range(100, 999) or { 100 }
		status: statuses[rand.int_in_range(0, 3) or { 0 }]
	}
	app.notify('Item added', 'success')
	return app.render_table()
}

@['/table/delete']
fn (mut app App) table_delete(message map[string]json2.Any) string {
	params := get_params(message)
	id_val := params['id'] or { json2.Null{} }
	id := id_val.int()
	
	mut new_items := []Item{}
	for item in app.items {
		if item.id != id {
			new_items << item
		}
	}
	app.items = new_items
	app.notify('Item deleted', 'warning')
	return app.render_table()
}

fn (app App) render_table() string {
	mut html := '<table id="data-table" hx-swap-oob="true">
		<thead>
			<tr>
				<th>ID</th>
				<th>Name</th>
				<th>Value</th>
				<th>Status</th>
				<th>Actions</th>
			</tr>
		</thead>
		<tbody>'
	
	for item in app.items {
		status_class := match item.status {
			'active' { 'status-active' }
			'pending' { 'status-pending' }
			else { 'status-inactive' }
		}
		html += '<tr>
			<td>${item.id}</td>
			<td>${item.name}</td>
			<td>${item.value}</td>
			<td><span class="status ${status_class}">${item.status}</span></td>
			<td><button class="btn-small btn-danger" hx-post="/table/delete" hx-vals=\'{"id":${item.id}}\' hx-target="#data-table" hx-swap="outerHTML">Delete</button></td>
		</tr>'
	}
	
	html += '</tbody></table>'
	return html
}

// =============================================================================
// Modal
// =============================================================================

@['/modal/open']
fn (mut app App) modal_open(message map[string]json2.Any) string {
	return '<div id="modal-container" hx-swap-oob="true">
		<div class="modal-backdrop"></div>
		<div class="modal">
			<div class="modal-header">
				<h3>Modal Dialog</h3>
				<button class="modal-close" hx-post="/modal/close">&times;</button>
			</div>
			<div class="modal-body">
				<p>This is a modal dialog. You can put any content here.</p>
			</div>
			<div class="modal-footer">
				<button class="btn" hx-post="/modal/close">Cancel</button>
				<button class="btn btn-primary" hx-post="/modal/close">Confirm</button>
			</div>
		</div>
	</div>'
}

@['/modal/close']
fn (mut app App) modal_close(message map[string]json2.Any) string {
	app.notify('Modal closed', 'info')
	return '<div id="modal-container" hx-swap-oob="true"></div>'
}

// =============================================================================
// Notifications
// =============================================================================

fn (mut app App) notify(message string, type_ string) {
	id := if app.notifications.len > 0 { app.notifications.last().id + 1 } else { 1 }
	app.notifications << Notification{id: id, message: message, type_: type_}
	// Keep only last 5 notifications
	if app.notifications.len > 5 {
		app.notifications = app.notifications[1..]
	}
}

@['/notify/show']
fn (mut app App) notify_show(message map[string]json2.Any) string {
	params := get_params(message)
	type_val := params['type'] or { json2.Any('info') }
	type_ := type_val.str()
	app.notify('This is a ${type_} notification!', type_)
	return app.render_notifications()
}

@['/notify/clear']
fn (mut app App) notify_clear(message map[string]json2.Any) string {
	app.notifications = []
	return '<div id="notifications" hx-swap-oob="true"></div>'
}

fn (app App) render_notifications() string {
	mut html := '<div id="notifications" hx-swap-oob="true">'
	for n in app.notifications {
		html += '<div class="notification ${n.type_}">${n.message}</div>'
	}
	html += '</div>'
	return html
}

// =============================================================================
// Cards
// =============================================================================

@['/card/flip']
fn (mut app App) card_flip(message map[string]json2.Any) string {
	params := get_params(message)
	id_val := params['id'] or { json2.Any('1') }
	id := id_val.str()
	return '<div id="card-${id}" hx-swap-oob="true" class="card flipped">
		<div class="card-inner">
			<div class="card-front">
				<h4>Card ${id}</h4>
				<p>Click to flip</p>
			</div>
			<div class="card-back">
				<h4>Back Side</h4>
				<p>This is the back!</p>
			</div>
		</div>
	</div>'
}

// =============================================================================
// Helpers
// =============================================================================

fn get_params(message map[string]json2.Any) map[string]json2.Any {
	tmp := message['parameters'] or { json2.Null{} }
	return tmp.as_map()
}
