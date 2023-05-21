module main

import vxui
import os
import x.json2

// first, inherit from vxui.Context
struct App {
	vxui.Context
}

// define some const values here
const (
	default_first_page_html_file = os.abs_path('./ui/index.html')
	default_js_file              = os.abs_path('./ui/js/vxui-htmx.js')
)

// define handler for specific route
['/edit']
fn (mut app App) test(message map[string]json2.Any) string {
	app.logger.info("I'm test function!")
	return '<div id="idMessage" hx-swap-oob="true">hello test</div>'
}

// if ommit the attr, the function name will act as a path
// `submit` function will handle `/submit` path
fn (mut app App) submit(message map[string]json2.Any) string {
	app.logger.info("I'm submit function!")
	return '<div id="idMessage" hx-swap-oob="true">hello submit</div>'
}

fn main() {
	mut html_filename := default_first_page_html_file
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}
	mut js_filename := default_js_file
	if os.args.len >= 3 {
		js_filename = os.args[2]
	}

	// run the vxui to start the web browser and open the `html_filename`
	mut app := App{}
	app.logger.info('vxui example: startup ${html_filename}')
	vxui.run(mut app, html_filename, js_filename)!
}
