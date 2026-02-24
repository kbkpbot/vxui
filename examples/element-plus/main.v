module main

import vxui
import x.json2
import time
import rand
import net.websocket

// App inherits from vxui.Context
struct App {
	vxui.Context
mut:
	// Form state
	input_text string
	select_val string
	switch_val bool
	slider_val int    = 50
	rate_val   int    = 3
	color_val  string = '#409EFF'
	// Counter
	click_count int
}

fn main() {
	mut app := App{}
	app.config.close_timer_ms = 10000 // 10 seconds for CDN loading
	app.config.window.width = 1400
	app.config.window.height = 900
	app.logger.set_level(.debug)
	vxui.run(mut app, './ui/index.html')!
}

// Helper: send JS command asynchronously (fire and forget)
fn (mut app App) send_js_async(js_code string) {
	// Get first client's connection
	app.mu.rlock()
	mut client_conn := &websocket.Client(unsafe { nil })
	for _, c in app.clients {
		client_conn = c.connection or { unsafe { nil } }
		break
	}
	app.mu.runlock()

	if client_conn == unsafe { nil } {
		app.logger.error('No client connection for send_js_async')
		return
	}

	js_id := '${time.now().unix_milli()}-${rand.u32()}'

	mut cmd := map[string]json2.Any{}
	cmd['cmd'] = json2.Any('run_js')
	cmd['js_id'] = json2.Any(js_id)
	cmd['script'] = json2.Any(js_code)
	client_conn.write(json2.encode(cmd).bytes(), .text_frame) or {
		app.logger.error('Failed to send JS: ${err}')
	}
}

// Helper: show Element Plus message (async)
fn (mut app App) show_message(msg string, msg_type string) {
	js_code := "window.ElementPlus.ElMessage({ message: '${msg}', type: '${msg_type}' })"
	app.send_js_async(js_code)
}

// Helper: show Element Plus notification (async)
fn (mut app App) show_notification(title string, msg string, msg_type string) {
	js_code := "window.ElementPlus.ElNotification({ title: '${title}', message: '${msg}', type: '${msg_type}' })"
	app.send_js_async(js_code)
}

// =============================================================================
// Button handlers
// =============================================================================

@['/button/click']
fn (mut app App) button_click(message map[string]json2.Any) string {
	params := get_params(message)
	type_val := params['type'] or { json2.Any('unknown') }
	app.click_count++

	msg_type := map_button_type(type_val.str())
	app.show_message('Button "${type_val.str()}" clicked! (Count: ${app.click_count})',
		msg_type)
	app.logger.info('Button clicked: ${type_val.str()}, count: ${app.click_count}')
	return ''
}

fn map_button_type(t string) string {
	return match t {
		'success' { 'success' }
		'warning' { 'warning' }
		'danger' { 'error' }
		else { 'info' }
	}
}

@['/button/loading']
fn (mut app App) button_loading(message map[string]json2.Any) string {
	app.show_message('Loading started...', 'info')
	app.logger.info('Loading button clicked')
	return ''
}

// =============================================================================
// Form handlers
// =============================================================================

@['/form/input']
fn (mut app App) form_input(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.input_text = val.str()
		if app.input_text.len > 0 {
			app.show_notification('Input Changed', 'New value: "${app.input_text}"', 'info')
		}
		app.logger.info('Input changed: ${app.input_text}')
	}
	return ''
}

@['/form/select']
fn (mut app App) form_select(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.select_val = val.str()
		option_name := match app.select_val {
			'option1' { '选项一' }
			'option2' { '选项二' }
			'option3' { '选项三' }
			else { app.select_val }
		}
		app.show_message('Selected: ${option_name}', 'success')
		app.logger.info('Select changed: ${app.select_val}')
	}
	return ''
}

@['/form/switch']
fn (mut app App) form_switch(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.switch_val = val.str() == 'true'
		status := if app.switch_val { 'ON' } else { 'OFF' }
		msg_type := if app.switch_val { 'success' } else { 'info' }
		app.show_message('Switch turned ${status}', msg_type)
		app.logger.info('Switch changed: ${app.switch_val}')
	}
	return ''
}

@['/form/slider']
fn (mut app App) form_slider(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.slider_val = int(val.int())
		app.show_notification('Slider Changed', 'Value: ${app.slider_val}%', 'info')
		app.logger.info('Slider changed: ${app.slider_val}')
	}
	return ''
}

@['/form/rate']
fn (mut app App) form_rate(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.rate_val = int(val.int())
		stars := '★'.repeat(app.rate_val) + '☆'.repeat(5 - app.rate_val)
		msg_type := if app.rate_val >= 4 {
			'success'
		} else if app.rate_val >= 2 {
			'warning'
		} else {
			'error'
		}
		app.show_message('Rating: ${stars} (${app.rate_val}/5)', msg_type)
		app.logger.info('Rate changed: ${app.rate_val}')
	}
	return ''
}

@['/form/color']
fn (mut app App) form_color(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.color_val = val.str()
		app.show_notification('Color Changed', 'New color: ${app.color_val}', 'info')
		app.logger.info('Color changed: ${app.color_val}')
	}
	return ''
}

// =============================================================================
// Tag handlers
// =============================================================================

@['/tag/close']
fn (mut app App) tag_close(message map[string]json2.Any) string {
	params := get_params(message)
	tag := params['tag'] or { json2.Any('') }
	app.show_message('Tag "${tag.str()}" closed', 'warning')
	app.logger.info('Tag closed: ${tag.str()}')
	return ''
}

// =============================================================================
// Progress handlers
// =============================================================================

@['/progress/complete']
fn (mut app App) progress_complete(message map[string]json2.Any) string {
	app.show_notification('Progress Complete', 'Task finished successfully!', 'success')
	app.logger.info('Progress completed!')
	return ''
}

// =============================================================================
// Table handlers
// =============================================================================

@['/table/edit']
fn (mut app App) table_edit(message map[string]json2.Any) string {
	params := get_params(message)
	id := params['id'] or { json2.Any(0) }
	name := params['name'] or { json2.Any('') }
	app.show_notification('Edit Row', 'ID: ${id.int()}, Name: ${name.str()}', 'info')
	app.logger.info('Edit row: id=${id.int()}, name=${name.str()}')
	return ''
}

@['/table/add']
fn (mut app App) table_add(message map[string]json2.Any) string {
	params := get_params(message)
	id := params['id'] or { json2.Any(0) }
	app.show_message('New row added (ID: ${id.int()})', 'success')
	app.logger.info('Add row: id=${id.int()}')
	return ''
}

@['/table/clear']
fn (mut app App) table_clear(message map[string]json2.Any) string {
	app.show_message('Table cleared', 'warning')
	app.logger.info('Table cleared')
	return ''
}

// =============================================================================
// Message handlers
// =============================================================================

@['/message/show']
fn (mut app App) message_show(message map[string]json2.Any) string {
	params := get_params(message)
	type_val := params['type'] or { json2.Any('info') }
	app.logger.info('Message shown: ${type_val.str()}')
	return ''
}

// =============================================================================
// Dialog handlers
// =============================================================================

@['/dialog/confirm']
fn (mut app App) dialog_confirm(message map[string]json2.Any) string {
	app.show_notification('Dialog Confirmed', 'Your action was recorded by the backend!',
		'success')
	app.logger.info('Dialog confirmed')
	return ''
}

// =============================================================================
// Date handlers
// =============================================================================

@['/date/pick']
fn (mut app App) date_pick(message map[string]json2.Any) string {
	params := get_params(message)
	val := params['value'] or { json2.Any('') }
	if val.str().len > 0 {
		app.show_message('Date selected: ${val.str()}', 'info')
	}
	app.logger.info('Date picked: ${val.str()}')
	return ''
}

@['/datetime/pick']
fn (mut app App) datetime_pick(message map[string]json2.Any) string {
	params := get_params(message)
	val := params['value'] or { json2.Any('') }
	if val.str().len > 0 {
		app.show_message('DateTime selected: ${val.str()}', 'info')
	}
	app.logger.info('DateTime picked: ${val.str()}')
	return ''
}

@['/daterange/pick']
fn (mut app App) daterange_pick(message map[string]json2.Any) string {
	params := get_params(message)
	val := params['value'] or { json2.Any('') }
	if val.str().len > 0 {
		app.show_notification('Date Range Selected', val.str(), 'info')
	}
	app.logger.info('DateRange picked: ${val.str()}')
	return ''
}

// =============================================================================
// Helper function
// =============================================================================

fn get_params(message map[string]json2.Any) map[string]json2.Any {
	tmp := message['parameters'] or { json2.Null{} }
	return tmp.as_map()
}
