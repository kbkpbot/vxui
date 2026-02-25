# Element Plus Integration Demo

Demonstrates integrating vxui with Vue 3 and Element Plus UI component library.

## Features

- **Vue 3 Integration**: Modern reactive frontend framework
- **Element Plus Components**: Professional UI components
- **Backend Notifications**: Server-driven notifications via `run_js()`
- **Form Controls**: Input, select, switch, slider, rating, color picker
- **Async JS Execution**: Fire-and-forget JavaScript commands

## How to Run

```sh
# From this directory
v run main.v
```

Or build and run:

```sh
v -prod -o element-plus main.v
./element-plus
```

## What It Demonstrates

This example shows how to:
- Integrate vxui with modern frontend frameworks (Vue 3)
- Use third-party UI component libraries
- Execute JavaScript from backend asynchronously
- Send backend-driven notifications to frontend
- Handle form inputs with complex components
- Use `send_js_async()` for fire-and-forget operations

## Architecture

1. Frontend: Vue 3 + Element Plus (loaded from CDN)
2. Backend: V with vxui
3. Communication: WebSocket for htmx, direct JS execution for notifications
