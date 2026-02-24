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
- [parse_attrs](#parse_attrs)
- [run](#run)
- [sanitize_path](#sanitize_path)
- [start_browser](#start_browser)
- [start_browser_with_token](#start_browser_with_token)
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

## sanitize_path
```v
fn sanitize_path(path string) !string
```

sanitize_path validates and sanitizes the file path

[[Return to contents]](#Contents)

## start_browser
```v
fn start_browser(filename string, vxui_ws_port u16) !
```

start_browser starts the browser and open the `filename`

[[Return to contents]](#Contents)

## start_browser_with_token
```v
fn start_browser_with_token(filename string, vxui_ws_port u16, token string, window WindowConfig) !
```

start_browser_with_token starts the browser with security token and window config

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
	ws_ping_interval int = 10 // WebSocket ping interval in seconds

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

#### Powered by vdoc. Generated on: 24 Feb 2026 10:35:10
