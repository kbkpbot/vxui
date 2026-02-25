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
3. **Rendering**: HTML generation for the todo list with swap-oob updates
4. **Interactions**: Add, toggle, delete, and clear operations
