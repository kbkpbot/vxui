module main

import vxui
import os
import x.json2

// TodoItem represents a single todo item
struct TodoItem {
	id   int
	text string
mut:
	completed bool
}

// App inherits from vxui.Context
struct App {
	vxui.Context
mut:
	todos   []TodoItem
	next_id int = 1
}

// index serves the main page
@['/']
fn (mut app App) index(message map[string]json2.Any) string {
	return app.render_todo_list()
}

// add adds a new todo item
@['/add']
fn (mut app App) add(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	text := params['text'] or { json2.Null{} }.str().trim_space()

	if text == '' {
		return '<div id="error" class="error">Please enter a todo item</div>'
	}

	item := TodoItem{
		id:        app.next_id
		text:      text
		completed: false
	}
	app.todos << item
	app.next_id++

	return app.render_todo_list()
}

// toggle marks a todo as complete/incomplete
@['/toggle']
fn (mut app App) toggle(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	id := params['id'] or { json2.Null{} }.str().int()

	for mut item in app.todos {
		if item.id == id {
			item.completed = !item.completed
			break
		}
	}

	return app.render_todo_list()
}

// delete removes a todo item
@['/delete']
fn (mut app App) delete(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	id := params['id'] or { json2.Null{} }.str().int()

	mut new_todos := []TodoItem{}
	for item in app.todos {
		if item.id != id {
			new_todos << item
		}
	}
	app.todos = new_todos

	return app.render_todo_list()
}

// clear_completed removes all completed items
@['/clear']
fn (mut app App) clear_completed(message map[string]json2.Any) string {
	mut new_todos := []TodoItem{}
	for item in app.todos {
		if !item.completed {
			new_todos << item
		}
	}
	app.todos = new_todos

	return app.render_todo_list()
}

// render_todo_list generates the HTML for the todo list using $tmpl
fn (mut app App) render_todo_list() string {
	// Calculate stats for template
	active_count := app.todos.filter(!it.completed).len
	completed_count := app.todos.filter(it.completed).len
	return $tmpl('templates/todo_list.html')
}

fn main() {
	mut html_filename := './ui/index.html'
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	mut app := App{}
	app.config.close_timer_ms = 1000
	app.config.window = vxui.WindowConfig{
		width:  500
		height: 600
		title:  'Todo App - vxui'
	}
	app.config.log.level = .info

	vxui.run(mut app, html_filename) or {
		eprintln('Error: ${err}')
		exit(1)
	}
}
