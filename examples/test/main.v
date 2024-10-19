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
	
	<div id="outerHTML" hx-swap-oob="true">
		<div><label>First Name</label>: ${app.first_name}</div>
		<div><label>Last Name</label>: ${app.last_name}</div>
		<div><label>Email</label>: ${app.email}</div>
		<button id="edit" hx-post="/edit" class="btn btn-primary">Click To Edit</button>
	</div>
	'
}

fn (mut app App) edit(message map[string]json2.Any) string {
	app.logger.info("I'm edit function!")
	tmp := message['parameters'] or { json2.Null{} }
	app.logger.info(tmp.str())
	app.cnt++
	return '<div id="outerHTML" hx-swap-oob="true">
  <div>
    <label>First Name</label>
    <input type="text" name="firstName" value="${app.first_name}">
  </div>
  <div class="form-group">
    <label>Last Name</label>
    <input type="text" name="lastName" value="${app.last_name}">
  </div>
  <div class="form-group">
    <label>Email Address</label>
    <input type="email" name="email" value="${app.email}">
  </div>
  <button class="btn" id="submit" hx-post="/submit">Submit</button>
  <button class="btn" id="cancel" hx-post="/cancel">Cancel</button>
</div>'
}

fn (mut app App) cancel(message map[string]json2.Any) string {
	app.logger.info("I'm cancel function!")
	app.cnt++

	return '<div id="idMessage" hx-swap-oob="true">hello[${app.cnt}], I am submit</div>
	
	<div id="outerHTML" hx-swap-oob="true">
		<div><label>First Name</label>: ${app.first_name}</div>
		<div><label>Last Name</label>: ${app.last_name}</div>
		<div><label>Email</label>: ${app.email}</div>
		<button id="edit" hx-post="/edit" class="btn btn-primary">Click To Edit</button>
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
	app.logger.set_level(.debug)
	app.logger.set_short_tag(true)
	app.logger.set_custom_time_format('HH:mm:ss')
	app.logger.info('vxui example: startup ${html_filename}')
	vxui.run(mut app, html_filename)!
}
