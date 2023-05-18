module main

import vxui
import os

// define some const values here
const (
	default_first_page_html_file = './ui/index.html'
	default_js_file              = './ui/js/vxui-htmx.js'
)

fn main() {
	mut html_filename := default_first_page_html_file
	if os.args.len == 2 {
		html_filename = os.args[1]
	}
	mut js_filename := default_js_file
	if os.args.len == 3 {
		js_filename = os.args[2]
	}

	// run the vxui to start the web browser and open the `html_filename`
	println('vxui example: startup ${html_filename}')
	mut vv := vxui.VXUI{}
	vv.run(html_filename, js_filename)
}
