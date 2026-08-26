# module vxui


## Contents
- [detect_browser](#detect_browser)
- [escape_attr](#escape_attr)
- [escape_html](#escape_html)
- [escape_js](#escape_js)
- [fire_call](#fire_call)
- [generate_id](#generate_id)
- [generate_routes](#generate_routes)
- [get_free_port](#get_free_port)
- [handle_message](#handle_message)
- [is_valid_email](#is_valid_email)
- [new_packed_app](#new_packed_app)
- [parse_attrs](#parse_attrs)
- [run](#run)
- [run_packed](#run_packed)
- [sanitize_path](#sanitize_path)
- [open_window](#open_window)
- [open_window_with](#open_window_with)
- [truncate_string](#truncate_string)
- [Verb](#Verb)
- [BrowserConfig](#BrowserConfig)
- [Client](#Client)
- [Config](#Config)
- [Context](#Context)
  - [run_js](#run_js)
  - [run_js_client](#run_js_client)
  - [get_clients](#get_clients)
  - [get_client_count](#get_client_count)
  - [close_client](#close_client)
  - [broadcast](#broadcast)
  - [set_window_size](#set_window_size)
  - [set_window_position](#set_window_position)
  - [set_window_title](#set_window_title)
  - [set_resizable](#set_resizable)
  - [get_port](#get_port)
  - [get_token](#get_token)
- [EmbeddedFile](#EmbeddedFile)
- [PackedApp](#PackedApp)
  - [add_file](#add_file)
  - [add_file_string](#add_file_string)
  - [extract_to](#extract_to)
  - [extract_to_temp](#extract_to_temp)
  - [get_file](#get_file)
  - [get_file_content](#get_file_content)
  - [has_file](#has_file)
  - [list_files](#list_files)
  - [total_size](#total_size)
  - [cleanup](#cleanup)
- [Route](#Route)
- [WindowConfig](#WindowConfig)

## detect_browser
```v
fn detect_browser() !BrowserConfig
```

detect_browser detects available browser on the system

[[Return to contents]](#Contents)

## escape_attr
```v
fn escape_attr(input string) string
```

escape_attr escapes HTML attribute values

[[Return to contents]](#Contents)

## escape_html
```v
fn escape_html(input string) string
```

escape_html escapes special HTML characters to prevent XSS attacks Use this when outputting user-generated content in HTML

[[Return to contents]](#Contents)

## escape_js
```v
fn escape_js(input string) string
```

escape_js escapes JavaScript special characters Use this when outputting data in JavaScript contexts

[[Return to contents]](#Contents)

## fire_call
```v
fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string
```

fire_call calls the method

[[Return to contents]](#Contents)

## generate_id
```v
fn generate_id() string
```

generate_id generates a unique ID string

[[Return to contents]](#Contents)

## generate_routes
```v
fn generate_routes[T](app &T) !map[string]Route
```

generate_routes generates route structs for an app

[[Return to contents]](#Contents)

## get_free_port
```v
fn get_free_port() !u16
```

get_free_port try to get a free port to websocket listen to

[[Return to contents]](#Contents)

## handle_message
```v
fn handle_message[T](mut app T, message map[string]json2.Any) !string
```

handle_message checks routes and calls the handler

[[Return to contents]](#Contents)

## is_valid_email
```v
fn is_valid_email(email string) bool
```

is_valid_email validates email format (basic check)

[[Return to contents]](#Contents)

## new_packed_app
```v
fn new_packed_app() PackedApp
```

new_packed_app creates a new PackedApp instance

[[Return to contents]](#Contents)

## parse_attrs
```v
fn parse_attrs(name string, attrs []string) !([]Verb, string)
```

parse_attrs parses function attributes for verbs and path

[[Return to contents]](#Contents)

## run
```v
fn run[T](mut app T, html_filename string) !
```

run opens the `html_filename` in browser and starts the event loop

[[Return to contents]](#Contents)

## run_packed
```v
fn run_packed[T](mut app T, mut packed PackedApp, entry_file string) !
```

run_packed runs the app with packed (embedded) resources This allows distributing a single executable with all frontend files embedded

[[Return to contents]](#Contents)

## sanitize_path
```v
fn sanitize_path(path string) !string
```

sanitize_path validates and sanitizes the file path

[[Return to contents]](#Contents)

## open_window
```v
fn (mut ctx Context) open_window(html_filename string) !
```

Opens an additional display window using the current window config and
security token.

[[Return to contents]](#Contents)

## open_window_with
```v
fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) !
```

Opens an additional display window with an explicit window configuration.
Backend-specific options (browser args, window mode, remote debug port) come
from `ctx.config.browser`.

[[Return to contents]](#Contents)

## truncate_string
```v
fn truncate_string(s string, max_len int) string
```

truncate_string truncates a string to max length with ellipsis

[[Return to contents]](#Contents)

## Verb
```v
enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}
```

Verb represents HTTP methods

[[Return to contents]](#Contents)

## BrowserConfig
```v
struct BrowserConfig {
	path string
	args []string
}
```

BrowserConfig holds browser path and arguments

[[Return to contents]](#Contents)

## Client
```v
struct Client {
pub:
	id        string
	token     string
	connected time.Time
pub mut:
	connection &websocket.Client = unsafe { nil }
}
```

Client represents a connected browser client

[[Return to contents]](#Contents)

## Config
```v
struct Config {
pub mut:
	// Connection settings
	close_timer      int = 50 // Close app after N cycles with no browser (each cycle is ~1ms)
	ws_ping_interval_ms int = 30000 // WebSocket ping interval in milliseconds (default 30s)
	ws_pong_timeout_ms  int = 60000 // Watchdog timeout: closes if no pong received within this many ms (default 60s, = 2 × ws_ping_interval_ms)

	// Security settings
	token        string // Security token (auto-generated if empty)
	require_auth bool = true // Require token authentication

	// Client settings
	multi_client bool // Allow multiple browser clients
	max_clients  int = 10 // Maximum number of concurrent clients (0 = unlimited)

	// JavaScript execution settings
	js_timeout_default int = 5000 // Default timeout for run_js() in milliseconds
	js_poll_interval   int = 10   // Polling interval for JS result in milliseconds

	// Window settings
	window WindowConfig
}
```

Config holds vxui runtime configuration

[[Return to contents]](#Contents)

## Ping and Watchdog

The WebSocket ping/patch mechanism serves two purposes:

1. **Liveness probing** — detects connections that have gone silent (no data flowing). This is essential for remote deployments (`allow_remote = true`) where the process may crash without closing the socket cleanly.

2. **Watchdog** — the server's ping thread periodically sends ping frames and closes any connection whose pong response is not received within `ws_pong_timeout_ms`. The effective threshold is `2 × ws_ping_interval_ms`.

### Recommended settings by deployment type

| Deployment | `ws_ping_interval_ms` | `ws_pong_timeout_ms` | Rationale |
|---|---|---|---|
| **Loopback (default, `allow_remote = false`)** | 30000 (30s) | 60000 (60s) | Progress death is detected by `on_close`; long interval avoids false positives during large transfers. |
| **Remote / `allow_remote = true`** | 10000 (10s) | 15000 (15s) | Network partitions and middleboxes require more responsive detection. |
| **Activity‑aware mode** (future: any received frame refreshes the timer) | 20000 (20s) | 30000 (30s) | Complements the vlib watchdog patch; pong still fires for idle detection. |

### Known behavior

- The library's ping thread fires every `ws_ping_interval_ms / 1000` seconds. A connection whose pong staleness exceeds `ws_pong_timeout_ms` is closed with code 1001 (going away).
- During large file uploads (or any handler-blocking operation), the read loop may be temporarily unavailable to process pong frames. With the recommended loopback settings (30s interval / 60s timeout) and chunked uploads (≥1.5MB chunks, size multiple of 3 for base64 alignment), the watchdog never fires because each chunk processes in ~10s, well under the 60s threshold.
- If a handler genuinely blocks for >60s (e.g., slow disk write), the connection will be killed — this is intentional, as it indicates a stuck server thread.
- The `on_close` event fires when the connection is terminated, allowing the application to clean up gracefully.

[[Return to contents]](#Contents)

## Context
```v
struct Context {
mut:
	ws_port      u16
	ws           websocket.Server
	routes       map[string]Route
	clients      map[string]Client // client_id -> Client
	mu           sync.RwMutex
	js_callbacks map[string]chan string // JS execution callbacks
pub mut:
	close_timer  int      = 50 // close app after `close_timer` cycles with no browser
	logger       &log.Log = &log.Log{}
	token        string // Security token for client authentication
	multi_client bool   // Allow multiple clients
	window       WindowConfig
}
```

Context is the main struct of vxui

[[Return to contents]](#Contents)

## run_js
```v
fn (mut ctx Context) run_js(js_code string, timeout_ms int) !string
```

run_js executes JavaScript in the frontend and returns the result timeout is in milliseconds, 0 means no wait

[[Return to contents]](#Contents)

## run_js_client
```v
fn (mut ctx Context) run_js_client(client_id string, js_code string, timeout_ms int) !string
```

run_js_client executes JavaScript on a specific client

[[Return to contents]](#Contents)

## get_clients
```v
fn (mut ctx Context) get_clients() []string
```

get_clients returns list of connected client IDs

[[Return to contents]](#Contents)

## get_client_count
```v
fn (mut ctx Context) get_client_count() int
```

get_client_count returns the number of connected clients

[[Return to contents]](#Contents)

## close_client
```v
fn (mut ctx Context) close_client(client_id string) !
```

close_client disconnects a specific client

[[Return to contents]](#Contents)

## broadcast
```v
fn (mut ctx Context) broadcast(message string) !
```

broadcast sends a message to all connected clients

[[Return to contents]](#Contents)

## set_window_size
```v
fn (mut ctx Context) set_window_size(width int, height int)
```

set_window_size sets the window dimensions

[[Return to contents]](#Contents)

## set_window_position
```v
fn (mut ctx Context) set_window_position(x int, y int)
```

set_window_position sets the window position (-1 for center)

[[Return to contents]](#Contents)

## set_window_title
```v
fn (mut ctx Context) set_window_title(title string)
```

set_window_title sets the window title

[[Return to contents]](#Contents)

## set_resizable
```v
fn (mut ctx Context) set_resizable(resizable bool)
```

set_resizable sets whether the window can be resized

[[Return to contents]](#Contents)

## get_port
```v
fn (ctx Context) get_port() u16
```

get_port returns the WebSocket port

[[Return to contents]](#Contents)

## get_token
```v
fn (ctx Context) get_token() string
```

get_token returns the security token

[[Return to contents]](#Contents)

## EmbeddedFile
```v
struct EmbeddedFile {
pub:
	data []u8
	size int
}
```

EmbeddedFile represents an embedded file

[[Return to contents]](#Contents)

## PackedApp
```v
struct PackedApp {
pub mut:
	files map[string]EmbeddedFile
}
```

PackedApp holds embedded frontend resources

[[Return to contents]](#Contents)

## add_file
```v
fn (mut p PackedApp) add_file(path string, data []u8)
```

add_file adds an embedded file to the packed app Accepts both []u8 and EmbedFileData (from $embed_file)

[[Return to contents]](#Contents)

## add_file_string
```v
fn (mut p PackedApp) add_file_string(path string, content string)
```

add_file_string adds an embedded file from string

[[Return to contents]](#Contents)

## extract_to
```v
fn (p PackedApp) extract_to(dir string) !
```

extract_to extracts all files to a directory

[[Return to contents]](#Contents)

## extract_to_temp
```v
fn (p PackedApp) extract_to_temp() !string
```

extract_to_temp extracts all files to a temp directory and returns the path

[[Return to contents]](#Contents)

## get_file
```v
fn (p PackedApp) get_file(path string) !EmbeddedFile
```

get_file retrieves a file by path

[[Return to contents]](#Contents)

## get_file_content
```v
fn (p PackedApp) get_file_content(path string) !string
```

get_file_content retrieves file content as string

[[Return to contents]](#Contents)

## has_file
```v
fn (p PackedApp) has_file(path string) bool
```

has_file checks if a file exists

[[Return to contents]](#Contents)

## list_files
```v
fn (p PackedApp) list_files() []string
```

list_files returns all file paths

[[Return to contents]](#Contents)

## total_size
```v
fn (p PackedApp) total_size() int
```

total_size returns total size of all embedded files

[[Return to contents]](#Contents)

## cleanup
```v
fn (p PackedApp) cleanup(dir string)
```

cleanup removes extracted files

[[Return to contents]](#Contents)

## Route
```v
struct Route {
	verb []Verb
	path string
}
```

Route represents a registered route

[[Return to contents]](#Contents)

## WindowConfig
```v
struct WindowConfig {
pub mut:
	width       int  = 800
	height      int  = 600
	x           int  = -1 // -1 means center
	y           int  = -1
	min_width   int  = 100
	min_height  int  = 100
	resizable   bool = true
	frameless   bool
	transparent bool
	title       string
}
```

WindowConfig holds window configuration

[[Return to contents]](#Contents)

#### Powered by vdoc. Generated on: 24 Feb 2026 10:49:48
