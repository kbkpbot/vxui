module main

import vxui
import os
import x.json2

// first, inherit from vxui.Context
struct App {
	vxui.Context
mut:
	// add your custom vars below
	cnt int
}

// define some const values here
const default_first_page_html_file = './ui/index.html'

// define handler for specific route
@['/doit']
fn (mut app App) test(message map[string]json2.Any) string {
	app.logger.info("I'm test/doit function!")
	tmp := message['path'] or { json2.Null{} }
	app.logger.info(tmp.str())
	app.cnt++
	return '<div id="idMessage" hx-swap-oob="true">hello[${app.cnt}], I am test/doit</div>'
}

// if ommit the attr, the function name will act as a path
// `submit` function will handle `/submit` path
fn (mut app App) submit(message map[string]json2.Any) string {
	app.logger.info("I'm submit function!")
	tmp := message['parameters'] or { json2.Null{} }
	app.logger.info(tmp.str())
	app.cnt++
	return '<div id="idMessage" hx-swap-oob="true">hello[${app.cnt}], I am submit</div>'
}

fn main() {
	mut html_filename := default_first_page_html_file
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	// run the vxui to start the web browser and open the `html_filename`
	mut app := App{}
	app.logger.info('vxui example: startup ${html_filename}')
	vxui.run(mut app, html_filename)!
}
