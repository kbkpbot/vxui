# Multi-Window Demo

Demonstrates how to create applications with multiple synchronized windows using vxui's multi-client support.

## Features

- **Multi-Client Mode**: Multiple browser windows/tabs connect to the same application
- **Broadcast Messaging**: Send messages from main window to all child windows
- **Shared State**: Counter synchronized across all connected windows
- **Window Management**: Track connected windows and their status
- **Real-Time Updates**: All windows receive updates instantly via WebSocket

## How to Run

```sh
# From this directory
v run main.v
```

Or build and run:

```sh
v -prod -o multi-window main.v
./multi-window
```

## How It Works

1. **Main Control Window**: Opens by default with full control panel
2. **Child Windows**: Open additional windows by running `./multi-window` again
3. **Synchronization**: All windows share the same state via WebSocket
4. **Broadcasting**: Use `app.broadcast()` to send updates to all clients

## Architecture

### Key Components

```v
// Enable multi-client mode
app.config.multi_client = true

// Broadcast to all windows
app.broadcast('<div hx-swap-oob="true">...</div>')!
```

### Window Types

- **Main Window** (`?type=main`): Control panel with full features
- **Child Window** (default): Receives broadcasts, can increment counter

### State Management

- `messages`: Shared message history
- `shared_counter`: Synchronized counter across all windows
- `window_states`: Track connected window information

## Use Cases

- **Control Panels**: Main window controls multiple display windows
- **Dashboards**: Multiple monitors showing different views of same data
- **Collaboration**: Multiple users viewing synchronized state
- **Presentations**: Presenter view + audience view

## Technical Details

- Uses `multi_client = true` to allow multiple connections
- Each window gets a unique ID via JavaScript
- Periodic ping keeps connection alive
- WebSocket ensures real-time synchronization
