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

// render_todo_list generates the HTML for the todo list
fn (mut app App) render_todo_list() string {
	mut html := ''

	// Stats
	active_count := app.todos.filter(!it.completed).len
	completed_count := app.todos.filter(it.completed).len

	html += '<div id="stats" hx-swap-oob="true" class="stats">
		<span>${active_count} items left</span>
		<span>${completed_count} completed</span>
	</div>'

	// Error placeholder
	html += '<div id="error" hx-swap-oob="true" class="error-hidden"></div>'

	// Todo list
	html += '<ul id="todo-list" hx-swap-oob="true">'

	if app.todos.len == 0 {
		html += '<li class="empty">No todos yet! Add one above.</li>'
	} else {
		for item in app.todos {
			completed_class := if item.completed { 'completed' } else { '' }
			check_text := if item.completed { 'Undo' } else { 'Complete' }

			html += '<li class="${completed_class}">
				<span class="todo-text">${item.text}</span>
				<div class="todo-actions">
					<button hx-post="/toggle" hx-vals=\'{"id": ${item.id}}\' hx-target="#todo-list" hx-swap="outerHTML">${check_text}</button>
					<button hx-post="/delete" hx-vals=\'{"id": ${item.id}}\' hx-target="#todo-list" hx-swap="outerHTML" class="delete">Delete</button>
				</div>
			</li>'
		}
	}

	html += '</ul>'

	// Clear button (only show if there are completed items)
	if completed_count > 0 {
		html += '<div id="clear-btn" hx-swap-oob="true">
			<button hx-post="/clear" hx-target="#todo-list" hx-swap="outerHTML">Clear Completed</button>
		</div>'
	} else {
		html += '<div id="clear-btn" hx-swap-oob="true"></div>'
	}

	// Input field (clear after submit)
	html += '<input id="todo-input" hx-swap-oob="true" type="text" name="text" placeholder="What needs to be done?" autofocus>'

	return html
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
