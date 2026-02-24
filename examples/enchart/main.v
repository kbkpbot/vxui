module main

import vxui
import os
import x.json2
import rand
import time

// first, inherit from vxui.Context
struct App {
	vxui.Context
mut:
	// add your custom vars below
	cnt int
}

// define some const values here
const default_first_page_html_file = './ui/index.html'

fn (mut app App) get(message map[string]json2.Any) string {
	// generate random hashrate for last 24 hour
	// main.js will call this function every second
	// we send back a hashtable to render the enchart
	mut start := time.now().unix() - 24 * 3600
	mut step := 2880
	mut hashtable := '{"get": "hashtable", "dat": {"key": "Hashrate (MH/s)", "time_axis": [${
		start + 0 * 7200}000, ${start + 1 * 7200}000, ${start + 2 * 7200}000, ${start + 3 * 7200}000, ${
		start + 4 * 7200}000, ${start + 5 * 7200}000, ${start + 6 * 7200}000, ${start + 7 * 7200}000, ${
		start + 8 * 7200}000, ${start + 9 * 7200}000, ${start + 10 * 7200}000, ${start + 11 * 7200}000], "values": ['
	mut hash := ''
	mut val := f32(0.0)
	mut first := true
	for i in 0 .. 30 {
		val = rand.f32_in_range(0, 1000) or { panic(err) }
		if first {
			hash = hash + '[${start + i * step}000,${val:.2f}]'
			first = false
		} else {
			hash = hash + ',[${start + i * step}000,${val:.2f}]'
		}
	}
	hashtable = hashtable + hash + ']}}'
	app.logger.info(hashtable)
	tmp := message['path'] or { json2.Null{} }
	app.logger.info(tmp.str())
	app.cnt++

	return hashtable
}

fn main() {
	mut html_filename := default_first_page_html_file
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	// run the vxui to start the web browser and open the `html_filename`
	mut app := App{}
	// if we have no client, just wait for 1000ms, and quit
	// because when page change, it have a small time gap between close old page and open new page
	app.config.close_timer_ms = 1000
	app.config.window.width = 1200
	app.config.window.height = 700
	app.logger.set_level(.debug)
	app.logger.set_output_stream(os.stderr())
	app.logger.set_short_tag(true)
	app.logger.set_custom_time_format('HH:mm:ss')
	app.logger.info('vxui example: startup ${html_filename}')

	// Run the app with proper error handling
	vxui.run(mut app, html_filename) or {
		eprintln('Error running vxui: ${err}')
		exit(1)
	}
}
