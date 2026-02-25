# Multi-Window Demo

Demonstrates how to create applications with multiple synchronized windows using vxui's multi-client support.

## Features

- **Multi-Client Mode**: Multiple browser windows/tabs connect to the same application
- **Broadcast Messaging**: Send messages from any window to all other windows
- **Shared State**: Counter synchronized across all connected windows
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

**Open multiple windows**: Run the command again in another terminal to open additional synchronized windows.

## How It Works

1. **Enable Multi-Client**: Set `app.config.multi_client = true`
2. **Open Multiple Windows**: Each window connects to the same WebSocket server
3. **Broadcast**: Use `app.broadcast()` to send updates to all clients
4. **Synchronization**: All windows share the same application state

## Key Code

```v
// Enable multi-client mode
app.config.multi_client = true

// Broadcast HTML update to all windows
app.broadcast('<div id="counter" hx-swap-oob="true">${count}</div>')!
```

## Architecture

- **Shared State**: `messages` array and `shared_counter` are shared across all windows
- **Broadcasting**: Server sends HTML fragments to all connected clients
- **Real-Time**: WebSocket ensures instant synchronization
- **Multi-Window**: Each window is a separate browser instance

## Use Cases

- **Control Panels**: Main window controls multiple display windows
- **Dashboards**: Multiple monitors showing different views of same data
- **Collaboration**: Multiple users viewing synchronized state
- **Presentations**: Presenter view + audience view

## Technical Details

- Uses `multi_client = true` to allow multiple connections
- Each window generates a unique ID via JavaScript
- Periodic ping keeps connection alive
- WebSocket broadcasts ensure real-time synchronization