module main

import vxui
import x.json2

// App inherits from vxui.Context
struct App {
	vxui.Context
mut:
	// Form state
	input_text  string
	select_val  string
	switch_val  bool
	slider_val  int = 50
	rate_val    int = 3
	color_val   string = '#409EFF'
	// Counter
	click_count int
}

fn main() {
	mut app := App{}
	app.config.close_timer_ms = 10000 // 10 seconds for CDN loading
	app.window.width = 1400
	app.window.height = 900
	app.logger.set_level(.debug)
	vxui.run(mut app, './ui/index.html')!
}

// =============================================================================
// Button handlers
// =============================================================================

@['/button/click']
fn (mut app App) button_click(message map[string]json2.Any) string {
	params := get_params(message)
	type_val := params['type'] or { json2.Any('unknown') }
	app.click_count++
	app.logger.info('Button clicked: ${type_val.str()}, count: ${app.click_count}')
	return '' // Vue handles the UI update
}

@['/button/loading']
fn (mut app App) button_loading(message map[string]json2.Any) string {
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
		app.logger.info('Input changed: ${app.input_text}')
	}
	return ''
}

@['/form/select']
fn (mut app App) form_select(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.select_val = val.str()
		app.logger.info('Select changed: ${app.select_val}')
	}
	return ''
}

@['/form/switch']
fn (mut app App) form_switch(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.switch_val = val.str() == 'true'
		app.logger.info('Switch changed: ${app.switch_val}')
	}
	return ''
}

@['/form/slider']
fn (mut app App) form_slider(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.slider_val = int(val.int())
		app.logger.info('Slider changed: ${app.slider_val}')
	}
	return ''
}

@['/form/rate']
fn (mut app App) form_rate(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.rate_val = int(val.int())
		app.logger.info('Rate changed: ${app.rate_val}')
	}
	return ''
}

@['/form/color']
fn (mut app App) form_color(message map[string]json2.Any) string {
	params := get_params(message)
	if val := params['value'] {
		app.color_val = val.str()
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
	app.logger.info('Tag closed: ${tag.str()}')
	return ''
}

// =============================================================================
// Progress handlers
// =============================================================================

@['/progress/complete']
fn (mut app App) progress_complete(message map[string]json2.Any) string {
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
	app.logger.info('Edit row: id=${id.int()}, name=${name.str()}')
	return ''
}

@['/table/add']
fn (mut app App) table_add(message map[string]json2.Any) string {
	params := get_params(message)
	id := params['id'] or { json2.Any(0) }
	app.logger.info('Add row: id=${id.int()}')
	return ''
}

@['/table/clear']
fn (mut app App) table_clear(message map[string]json2.Any) string {
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
	app.logger.info('Date picked: ${val.str()}')
	return ''
}

@['/datetime/pick']
fn (mut app App) datetime_pick(message map[string]json2.Any) string {
	params := get_params(message)
	val := params['value'] or { json2.Any('') }
	app.logger.info('DateTime picked: ${val.str()}')
	return ''
}

@['/daterange/pick']
fn (mut app App) daterange_pick(message map[string]json2.Any) string {
	params := get_params(message)
	val := params['value'] or { json2.Any('') }
	app.logger.info('DateRange picked: ${val.str()}')
	return ''
}

// =============================================================================
// Helper function
// =============================================================================

fn get_params(message map[string]json2.Any) map[string]json2.Any {
	mut params := map[string]json2.Any{}
	if p := message['parameters'] {
		if p is map[string]json2.Any {
			params = p.clone()
		}
	}
	return params
}
