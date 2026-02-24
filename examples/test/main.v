module main

import vxui
import os
import x.json2

// first, inherit from vxui.Context
struct App {
	vxui.Context
mut:
	// add your custom vars below
	cnt        int
	first_name string = 'kbkpbot'
	last_name  string = 'kbkpbot'
	email      string = 'kbkpbot@gmail.com'
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
	mut tmp := message['parameters'] or { json2.Null{} }
	parameters := tmp.as_map()
	if first_name := parameters['firstName'] {
		app.first_name = first_name.str()
	}
	if last_name := parameters['lastName'] {
		app.last_name = last_name.str()
	}

	if email := parameters['email'] {
		app.email = email.str()
	}
	app.cnt++

	// this will replace the div "idMessage" and div "outerHTML"
	// please add `hx-swap-oob="true"`
	return '<div id="idMessage" hx-swap-oob="true">hello[${app.cnt}], I am submit</div>
	
	<div id="outerHTML" hx-swap-oob="true" class="contact-info">
		<div class="info-row">
			<span class="info-label">First Name</span>
			<span class="info-value">${app.first_name}</span>
		</div>
		<div class="info-row">
			<span class="info-label">Last Name</span>
			<span class="info-value">${app.last_name}</span>
		</div>
		<div class="info-row">
			<span class="info-label">Email</span>
			<span class="info-value">${app.email}</span>
		</div>
		<div class="button-row">
			<button id="edit" hx-post="/edit" class="btn btn-primary">
				<span class="btn-icon">✏️</span> Edit
			</button>
		</div>
	</div>
	'
}

fn (mut app App) edit(message map[string]json2.Any) string {
	app.logger.info("I'm edit function!")
	tmp := message['parameters'] or { json2.Null{} }
	app.logger.info(tmp.str())
	app.cnt++
	return '<div id="outerHTML" hx-swap-oob="true" class="contact-info">
		<div class="info-row">
			<span class="info-label">First Name</span>
			<input type="text" name="firstName" value="${app.first_name}" style="flex:1; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.15); border-radius: 6px; padding: 8px 12px; color: #fff;">
		</div>
		<div class="info-row">
			<span class="info-label">Last Name</span>
			<input type="text" name="lastName" value="${app.last_name}" style="flex:1; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.15); border-radius: 6px; padding: 8px 12px; color: #fff;">
		</div>
		<div class="info-row">
			<span class="info-label">Email</span>
			<input type="email" name="email" value="${app.email}" style="flex:1; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.15); border-radius: 6px; padding: 8px 12px; color: #fff;">
		</div>
		<div class="button-row">
			<button class="btn btn-success" id="submit" hx-post="/submit">
				<span class="btn-icon">✓</span> Submit
			</button>
			<button class="btn btn-outline" id="cancel" hx-post="/cancel">
				<span class="btn-icon">✕</span> Cancel
			</button>
		</div>
	</div>'
}

fn (mut app App) cancel(message map[string]json2.Any) string {
	app.logger.info("I'm cancel function!")
	app.cnt++

	return '<div id="idMessage" hx-swap-oob="true">hello[${app.cnt}], I am cancel</div>
	
	<div id="outerHTML" hx-swap-oob="true" class="contact-info">
		<div class="info-row">
			<span class="info-label">First Name</span>
			<span class="info-value">${app.first_name}</span>
		</div>
		<div class="info-row">
			<span class="info-label">Last Name</span>
			<span class="info-value">${app.last_name}</span>
		</div>
		<div class="info-row">
			<span class="info-label">Email</span>
			<span class="info-value">${app.email}</span>
		</div>
		<div class="button-row">
			<button id="edit" hx-post="/edit" class="btn btn-primary">
				<span class="btn-icon">✏️</span> Edit
			</button>
		</div>
	</div>
	'
}

fn main() {
	mut html_filename := default_first_page_html_file
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	// run the vxui to start the web browser and open the `html_filename`
	mut app := App{}
	// Window configuration
	app.config.window.width = 1000
	app.config.window.height = 700
	// if we have no client, just wait for 5000 cycles (5 seconds), and quit
	// because when page change, it have a small time gap between close old page and open new page
	app.config.close_timer_ms = 1000
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