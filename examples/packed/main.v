module main

import vxui
import os
import x.json2

// Embed frontend resources into executable
const index_html = $embed_file('ui/index.html')
const htmx_js = $embed_file('ui/js/htmx.js')
const vxui_ws_js = $embed_file('ui/js/vxui-ws.js')

struct App {
	vxui.Context
mut:
	counter int
}

@['/click']
fn (mut app App) click(message map[string]json2.Any) string {
	app.counter++
	return '<div id="result" hx-swap-oob="true">Clicked ${app.counter} times!</div>'
}

fn main() {
	mut app := App{}
	app.close_timer = 5000
	app.logger.set_level(.debug)
	app.logger.set_output_stream(os.stderr())

	// Create packed app with embedded files
	mut packed := vxui.new_packed_app()
	packed.add_file_string('index.html', index_html.to_string())
	packed.add_file_string('js/htmx.js', htmx_js.to_string())
	packed.add_file_string('js/vxui-ws.js', vxui_ws_js.to_string())

	app.logger.info('Packed app ready, total size: ${packed.total_size()} bytes')

	// Run with packed resources
	vxui.run_packed(mut app, mut packed, 'index.html') or {
		eprintln('Error: ${err}')
		exit(1)
	}
}
