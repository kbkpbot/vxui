# Multi-Window Demo

Demonstrates a practical multi-window desktop application with a main window and a settings window.

## Features

- **Main Window**: Displays content with customizable properties
- **Settings Window**: Separate window for editing configuration
- **Real-Time Sync**: Changes in settings window immediately reflect in main window
- **Configurable Properties**:
  - Title
  - Background color
  - Accent color  
  - Display message
  - Font size

## How to Run

```sh
# From this directory
v run main.v
```

## How It Works

1. **Start the application** - Opens the main display window
2. **Click Settings** - Opens a separate settings window
3. **Modify settings** - Change colors, text, or other properties
4. **Save changes** - Updates are broadcast to the main window instantly
5. **Close settings** - Settings window can be closed independently

## Architecture

### Window Communication

```
Main Window          Settings Window
     │                       │
     │  Click "Settings"    │
     ├──────────────────────►│
     │                       │
     │   Broadcast Update   │
     │◄──────────────────────┤
     │   (real-time sync)   │
```

### Key Components

- **Main Window** (`/`): Displays the content using `AppConfig`
- **Settings Window** (`/settings`): Form for editing `AppConfig`
- **Update Handler** (`/update-settings`): Broadcasts changes to all windows
- **Open Handler** (`/open-settings`): Opens new settings window via `start_browser_with_token()`

### Data Flow

1. User changes setting in settings window
2. Settings window POSTs to `/update-settings`
3. Backend updates `AppConfig`
4. Backend broadcasts HTML update to all connected windows
5. Main window receives update via `hx-swap-oob` and refreshes display

## Use Cases

- **Preferences/Settings dialogs**
- **Property editors**
- **Configuration panels**
- **Inspector windows**

## Technical Details

- Uses `multi_client = true` for multiple window support
- `spawn` + `start_browser_with_token()` opens new windows programmatically
- `broadcast()` sends updates to all connected clients
- `hx-swap-oob` enables partial page updates without full refresh
