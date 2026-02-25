# Todo App Demo

A full-featured CRUD (Create, Read, Update, Delete) todo list application.

## Features

- **Add Todos**: Create new todo items
- **Toggle Complete**: Mark items as complete/incomplete
- **Delete Items**: Remove individual todos
- **Clear Completed**: Bulk delete completed items
- **Statistics**: Show active and completed counts
- **Empty State**: Friendly message when no todos

## How to Run

```sh
# From this directory
v run main.v
```

Or build and run:

```sh
v -prod -o todo-app main.v
./todo-app
```

## What It Demonstrates

This example shows how to:
- Implement full CRUD operations
- Manage a list of items in application state
- Filter and process collections
- Handle form validation
- Update multiple UI elements with single response
- Use `hx-vals` for passing data in requests

## Architecture

1. **Data Model**: `TodoItem` struct with id, text, and completed status
2. **State Management**: Array of todos with auto-increment ID
3. **Rendering**: HTML generation using V's `$tmpl` template feature
4. **Interactions**: Add, toggle, delete, and clear operations

## Using $tmpl Templates

This example demonstrates V's built-in `$tmpl` feature for cleaner HTML generation:

```v
fn (mut app App) render_todo_list() string {
    active_count := app.todos.filter(!it.completed).len
    completed_count := app.todos.filter(it.completed).len
    return $tmpl('templates/todo_list.html')
}
```

Template syntax (`templates/todo_list.html`):
```html
<ul id="todo-list" hx-swap-oob="true">
@if app.todos.len == 0
  <li class="empty">No todos yet!</li>
@else
  @for item in app.todos
    <li>@item.text</li>
  @end
@end
</ul>
```

**Benefits:**
- HTML and V code are separated
- Templates are compiled at build time (zero runtime overhead)
- Supports `@if`, `@for`, `@else`, and direct struct field access
