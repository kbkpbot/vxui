# module vxui


## Contents
- [detect_browser_type](#detect_browser_type)
- [escape_attr](#escape_attr)
- [escape_html](#escape_html)
- [escape_js](#escape_js)
- [fire_call](#fire_call)
- [generate_id](#generate_id)
- [generate_routes](#generate_routes)
- [get_free_port](#get_free_port)
- [is_app_mode_supported](#is_app_mode_supported)
- [is_valid_email](#is_valid_email)
- [new_display](#new_display)
- [new_error_detail](#new_error_detail)
- [new_error_detail_with_cause](#new_error_detail_with_cause)
- [new_error_detail_with_details](#new_error_detail_with_details)
- [new_packed_app](#new_packed_app)
- [parse_attrs](#parse_attrs)
- [run](#run)
- [run_packed](#run_packed)
- [sanitize_path](#sanitize_path)
- [sanitize_utf8](#sanitize_utf8)
- [truncate_string](#truncate_string)
- [BrowserType.from](#BrowserType.from)
- [DisplayKind.from](#DisplayKind.from)
- [EventType.from](#EventType.from)
- [Verb.from](#Verb.from)
- [VxuiError.from](#VxuiError.from)
- [WindowMode.from](#WindowMode.from)
- [Display](#Display)
- [DisplaySession](#DisplaySession)
- [BrowserSession](#BrowserSession)
  - [close](#close)
  - [set_size](#set_size)
  - [set_title](#set_title)
  - [set_position](#set_position)
- [EventHandler](#EventHandler)
- [WebViewSession](#WebViewSession)
  - [close](#close)
  - [set_size](#set_size)
  - [set_title](#set_title)
  - [set_position](#set_position)
- [BrowserType](#BrowserType)
- [DisplayKind](#DisplayKind)
- [EventType](#EventType)
- [Verb](#Verb)
- [VxuiError](#VxuiError)
- [WindowMode](#WindowMode)
- [BrowserConfig](#BrowserConfig)
- [BrowserDisplay](#BrowserDisplay)
  - [spawn](#spawn)
- [Client](#Client)
- [Config](#Config)
- [Context](#Context)
  - [on_event](#on_event)
  - [run_js](#run_js)
  - [run_js_client](#run_js_client)
  - [post_js](#post_js)
  - [post_js_client](#post_js_client)
  - [get_clients](#get_clients)
  - [get_client_count](#get_client_count)
  - [get_client](#get_client)
  - [close_client](#close_client)
  - [broadcast](#broadcast)
  - [broadcast_except](#broadcast_except)
  - [send_to_client](#send_to_client)
  - [ping_client](#ping_client)
  - [ping_all_clients](#ping_all_clients)
  - [process_client_removals](#process_client_removals)
  - [set_window_size](#set_window_size)
  - [set_window_position](#set_window_position)
  - [set_window_title](#set_window_title)
  - [open_window](#open_window)
  - [open_window_with](#open_window_with)
  - [set_js_sandbox](#set_js_sandbox)
  - [set_browser_config](#set_browser_config)
  - [set_webview_config](#set_webview_config)
  - [close_displays](#close_displays)
  - [get_port](#get_port)
  - [get_token](#get_token)
  - [get_config](#get_config)
  - [trigger_hot_reload](#trigger_hot_reload)
- [DevConfig](#DevConfig)
- [DisplayConfig](#DisplayConfig)
- [DisplaySessionConfig](#DisplaySessionConfig)
- [EmbeddedFile](#EmbeddedFile)
- [EventData](#EventData)
- [JsSandboxConfig](#JsSandboxConfig)
- [LogConfig](#LogConfig)
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
- [Request](#Request)
- [Response](#Response)
- [Route](#Route)
- [VxuiErrorDetail](#VxuiErrorDetail)
  - [msg](#msg)
  - [code](#code)
  - [str](#str)
  - [with_cause](#with_cause)
  - [with_detail](#with_detail)
- [WebViewConfig](#WebViewConfig)
- [WebViewDisplay](#WebViewDisplay)
  - [spawn](#spawn)
- [WindowConfig](#WindowConfig)

## detect_browser_type
```v
fn detect_browser_type(browser_path string) BrowserType
```

detect_browser_type determines the browser type from path

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

fire_call calls the method Only methods carrying route attributes (@['/path'] and/or a verb) are dispatchable; untagged helper methods are invisible to routing.

NOTE on V comptime limits (tested on V 0.5.2 / 9142d68): the dispatch call below is instantiated ONCE FOR EVERY string-returning method of T, regardless of attributes — runtime `if` guards do not gate comptime instantiation, `$for attr in method.attributes` nesting parses but does not gate it either, and `continue` is illegal inside `$for`. Helpers on the app struct must therefore return void/non-string types (or take no parameters): a string-returning helper with custom parameters will not compile. generate_routes fails fast when a TAGGED method has the wrong return type, which keeps this constraint discoverable at startup.

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

## is_app_mode_supported
```v
fn is_app_mode_supported(browser_type BrowserType) bool
```

is_app_mode_supported returns true if browser supports app mode

[[Return to contents]](#Contents)

## is_valid_email
```v
fn is_valid_email(email string) bool
```

is_valid_email validates email format (basic check)

[[Return to contents]](#Contents)

## new_display
```v
fn new_display(kind DisplayKind, app_cfg &Config) !Display
```

new_display constructs the configured backend. It receives the whole app Config so each backend extracts its OWN sub-config — this keeps the construction wiring backend-agnostic (no hardcoded BrowserConfig).

[[Return to contents]](#Contents)

## new_error_detail
```v
fn new_error_detail(code VxuiError, message string) VxuiErrorDetail
```

new_error_detail creates a new VxuiErrorDetail

[[Return to contents]](#Contents)

## new_error_detail_with_cause
```v
fn new_error_detail_with_cause(code VxuiError, message string, cause IError) VxuiErrorDetail
```

new_error_detail_with_cause creates a new VxuiErrorDetail with an underlying cause

[[Return to contents]](#Contents)

## new_error_detail_with_details
```v
fn new_error_detail_with_details(code VxuiError, message string, details map[string]string) VxuiErrorDetail
```

new_error_detail_with_details creates a new VxuiErrorDetail with details

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

run_packed runs the app with packed (embedded) resources

[[Return to contents]](#Contents)

## sanitize_path
```v
fn sanitize_path(path string) !string
```

sanitize_path validates and sanitizes the file path Handles both plain and URL-encoded path traversal attempts

[[Return to contents]](#Contents)

## sanitize_utf8
```v
fn sanitize_utf8(s string) string
```

sanitize_utf8 returns `s` with every invalid UTF-8 byte replaced by the Unicode replacement character (U+FFFD). The websocket layer REJECTS text frames that are not valid UTF-8, so any payload built from byte-wise slicing of multibyte strings must be passed through this helper before being returned from a route handler.

[[Return to contents]](#Contents)

## truncate_string
```v
fn truncate_string(s string, max_len int) string
```

truncate_string truncates a string to max length with ellipsis

[[Return to contents]](#Contents)

## BrowserType.from
```v
fn BrowserType.from[W](input W) !BrowserType
```

[[Return to contents]](#Contents)

## DisplayKind.from
```v
fn DisplayKind.from[W](input W) !DisplayKind
```

[[Return to contents]](#Contents)

## EventType.from
```v
fn EventType.from[W](input W) !EventType
```

[[Return to contents]](#Contents)

## Verb.from
```v
fn Verb.from[W](input W) !Verb
```

[[Return to contents]](#Contents)

## VxuiError.from
```v
fn VxuiError.from[W](input W) !VxuiError
```

[[Return to contents]](#Contents)

## WindowMode.from
```v
fn WindowMode.from[W](input W) !WindowMode
```

[[Return to contents]](#Contents)

## Display
```v
interface Display {
mut:
	spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}
```

Display is the pluggable backend that turns an HTML file into one or more presented windows. The core talks to the page exclusively via WebSocket; the Display only has to get the page on screen.

[[Return to contents]](#Contents)

## DisplaySession
```v
interface DisplaySession {
mut:
	close() !
	set_size(w int, h int)
	set_title(t string)
	set_position(x int, y int)
}
```

DisplaySession is a live, presented window. It exposes only what a backend can meaningfully do after launch; all request/response traffic flows over WebSocket and never touches this interface.

[[Return to contents]](#Contents)

## BrowserSession
## close
```v
fn (mut s BrowserSession) close() !
```

[[Return to contents]](#Contents)

## set_size
```v
fn (mut s BrowserSession) set_size(w int, h int)
```

[[Return to contents]](#Contents)

## set_title
```v
fn (mut s BrowserSession) set_title(t string)
```

[[Return to contents]](#Contents)

## set_position
```v
fn (mut s BrowserSession) set_position(x int, y int)
```

[[Return to contents]](#Contents)

## EventHandler
```v
type EventHandler = fn (EventData)
```

EventHandler is a callback function type for events

[[Return to contents]](#Contents)

## WebViewSession
## close
```v
fn (mut s WebViewSession) close() !
```

[[Return to contents]](#Contents)

## set_size
```v
fn (mut s WebViewSession) set_size(w int, h int)
```

[[Return to contents]](#Contents)

## set_title
```v
fn (mut s WebViewSession) set_title(t string)
```

[[Return to contents]](#Contents)

## set_position
```v
fn (mut s WebViewSession) set_position(x int, y int)
```

[[Return to contents]](#Contents)

## BrowserType
```v
enum BrowserType {
	chrome
	firefox
	safari
	edge
	brave
	chromium
	unknown
}
```

BrowserType represents different browser types

[[Return to contents]](#Contents)

## DisplayKind
```v
enum DisplayKind {
	browser // external system browser (default)
	webview // reserved: in-process platform WebView/WebKit (not yet implemented)
}
```

DisplayKind selects which display backend renders the UI.

[[Return to contents]](#Contents)

## EventType
```v
enum EventType {
	before_start
	after_start
	client_connecting
	client_connected
	client_disconnected
	before_shutdown
	error
	js_execution
	before_request
	after_request
}
```

EventType represents different lifecycle events

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

## VxuiError
```v
enum VxuiError {
	unknown
	client_not_found
	no_clients
	no_valid_connection
	js_timeout
	js_validation_failed
	js_result_too_large
	auth_failed
	auth_invalid_token
	connection_error
	connection_closed
	port_not_available
	browser_not_found
	file_not_found
	path_traversal
	route_not_found
	invalid_message
	request_timeout
	// Additional error codes for unified error handling
	profile_create_failed
	process_fork_failed
	hidden_file_access
	null_byte_detected
	absolute_path_not_allowed
	invalid_method
	method_not_allowed
	attribute_parse_error
}
```

VxuiError represents error codes

[[Return to contents]](#Contents)

## WindowMode
```v
enum WindowMode {
	app    // standalone window WITHOUT address bar/tab strip (default)
	kiosk  // borderless fullscreen
	normal // an ordinary browser tab
}
```

WindowMode selects how the page window is presented. Only meaningful for Chromium-family browsers; Firefox/Safari open a normal tab regardless.

[[Return to contents]](#Contents)

## BrowserConfig
```v
struct BrowserConfig {
pub mut:
	custom_args       []string // Additional custom arguments
	profile_dir       string   // Custom profile directory (empty = default)
	headless          bool     // Run in headless mode (for testing)
	devtools          bool     // Open DevTools automatically
	no_sandbox        bool     // Disable sandbox (for root/CI)
	window_mode       WindowMode = .app // presentation of the app window (see WindowMode)
	user_data_dir     string // Custom user data directory
	preferred_path    string // Preferred browser path (skip detection)
	remote_debug_port int    // Chrome remote debugging port (0 = disabled)
}
```

BrowserConfig holds browser startup configuration

[[Return to contents]](#Contents)

## BrowserDisplay
```v
struct BrowserDisplay {
	config &BrowserConfig
}
```

BrowserDisplay launches an external browser process.

[[Return to contents]](#Contents)

## spawn
```v
fn (mut b BrowserDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
```

[[Return to contents]](#Contents)

## Client
```v
struct Client {
pub:
	id            string
	token         string
	connected     time.Time
	request_count int
	last_request  time.Time
pub mut:
	connection ?&websocket.Client
	last_ping  time.Time
}
```

Client represents a connected browser client

[[Return to contents]](#Contents)

## Config
```v
struct Config {
pub mut:
	// Application settings
	app_name string = default_app_name

	// Development settings
	dev DevConfig // Development mode settings

	// Connection settings
	close_timer_ms      int = 5000  // Close app after N ms with no browser
	ws_ping_interval_ms int = 30000 // WebSocket ping interval
	ws_pong_timeout_ms  int = 60000 // Timeout for pong response

	// Security settings
	token        string // Security token (auto-generated if empty)
	require_auth bool = true // Require token authentication
	allow_remote bool // Accept connections from non-loopback interfaces (default false)

	// Client settings
	multi_client bool // Allow multiple browser clients
	// When multi_client is off, let a NEW successful authentication evict
	// stale sessions instead of letting a restored/crashed browser tab hold
	// the single slot forever. Defaults to true: without it, a simple F5
	// reload races the async client cleanup and the fresh connection gets
	// rejected — the app appears dead after a refresh.
	evict_on_new bool = true
	max_clients  int  = 10 // Maximum concurrent clients (0 = unlimited)

	// JavaScript execution settings
	js_timeout int = 5000 // Default timeout for run_js()
	js_poll_ms int = 10   // Polling interval for JS result
	js_sandbox JsSandboxConfig // JS execution sandbox

	// Window settings
	window WindowConfig

	// Browser settings
	browser BrowserConfig

	// WebView settings (reserved: in-process WebView/WebKit backend, not yet implemented)
	webview WebViewConfig

	// Display backend selection
	display DisplayConfig

	// Logging settings
	log LogConfig
}
```

Config is the unified configuration for vxui

[[Return to contents]](#Contents)

## Context
```v
struct Context {
mut:
	ws_port            u16
	ws                 websocket.Server
	display            Display
	display_session    ?DisplaySession
	display_sessions   []DisplaySession
	routes             map[string]Route
	clients            map[string]Client
	mu                 sync.RwMutex
	js_callbacks       map[string]chan string
	event_handlers     map[EventType][]EventHandler
	client_remove_chan chan ClientRemoveMsg // channel for serialized client removal
pub mut:
	config Config
	logger &log.Log = &log.Log{}
}
```

[[Return to contents]](#Contents)

## on_event
```v
fn (mut ctx Context) on_event(event_type EventType, handler EventHandler)
```

on_event registers an event handler

[[Return to contents]](#Contents)

## run_js
```v
fn (mut ctx Context) run_js(js_code string, timeout_ms int) !string
```

run_js executes JavaScript in the frontend and returns the result

[[Return to contents]](#Contents)

## run_js_client
```v
fn (mut ctx Context) run_js_client(client_id string, js_code string, timeout_ms int) !string
```

run_js_client executes JavaScript on a specific client

[[Return to contents]](#Contents)

## post_js
```v
fn (mut ctx Context) post_js(js_code string) !
```

post_js executes JavaScript in the frontend fire-and-forget: the result (or error) is discarded and the pending callback is unregistered immediately. Safe to call from INSIDE route handlers, unlike run_js(timeout_ms > 0), which deadlocks there: a handler runs on the connection read loop, the very goroutine that would deliver js_result.

[[Return to contents]](#Contents)

## post_js_client
```v
fn (mut ctx Context) post_js_client(client_id string, js_code string) !
```

post_js_client is post_js targeting one specific client.

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

## get_client
```v
fn (mut ctx Context) get_client(client_id string) ?Client
```

get_client returns client info by ID

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

broadcast sends a message to all connected clients. A write failure on one client (e.g. a stale connection) is skipped so the remaining clients still receive the message.

[[Return to contents]](#Contents)

## broadcast_except
```v
fn (mut ctx Context) broadcast_except(message string, except_client_id string) !
```

broadcast_except sends a message to all clients except one. Per-client write failures are skipped, see broadcast().

[[Return to contents]](#Contents)

## send_to_client
```v
fn (mut ctx Context) send_to_client(client_id string, message string) !
```

send_to_client sends a message to a specific client

[[Return to contents]](#Contents)

## ping_client
```v
fn (mut ctx Context) ping_client(client_id string) !
```

ping_client sends a ping to a specific client

[[Return to contents]](#Contents)

## ping_all_clients
```v
fn (mut ctx Context) ping_all_clients()
```

ping_all_clients sends a ping to all connected clients

[[Return to contents]](#Contents)

## process_client_removals
```v
fn (mut ctx Context) process_client_removals()
```

process_client_removals handles client removal requests from the channel This should be run in a separate goroutine to serialize removal operations

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

set_window_position sets the window position

[[Return to contents]](#Contents)

## set_window_title
```v
fn (mut ctx Context) set_window_title(title string)
```

set_window_title sets the window title

[[Return to contents]](#Contents)

## open_window
```v
fn (mut ctx Context) open_window(html_filename string) !
```

open_window opens an additional display window using the current window configuration and security token.

[[Return to contents]](#Contents)

## open_window_with
```v
fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) !
```

open_window_with opens an additional display window with an explicit window configuration. Backend-specific options come from ctx.config.browser.

[[Return to contents]](#Contents)

## set_js_sandbox
```v
fn (mut ctx Context) set_js_sandbox(config JsSandboxConfig)
```

set_js_sandbox configures JavaScript execution security

[[Return to contents]](#Contents)

## set_browser_config
```v
fn (mut ctx Context) set_browser_config(config BrowserConfig)
```

set_browser_config configures browser startup options

[[Return to contents]](#Contents)

## set_webview_config
```v
fn (mut ctx Context) set_webview_config(config WebViewConfig)
```

set_webview_config configures WebView/WebKit backend options (used when display.kind == .webview).

[[Return to contents]](#Contents)

## close_displays
```v
fn (mut ctx Context) close_displays()
```

close_displays tears down all live display sessions. No-op for the detached external-browser backend; REQUIRED for in-process backends (WebView) so native windows/handles are released on shutdown.

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

## get_config
```v
fn (ctx Context) get_config() Config
```

get_config returns the current configuration

[[Return to contents]](#Contents)

## trigger_hot_reload
```v
fn (mut ctx Context) trigger_hot_reload() !
```

trigger_hot_reload sends a reload command to all connected clients. Per-client write failures are skipped, see broadcast().

[[Return to contents]](#Contents)

## DevConfig
```v
struct DevConfig {
pub mut:
	enabled       bool // Enable development mode
	hot_reload    bool = true // Enable hot reload (refresh browser on file change)
	watch_dirs    []string // Directories to watch for changes (default: html file dir)
	watch_ms      int  = 500  // File watch interval in milliseconds
	auto_devtools bool = true // Auto-open DevTools in dev mode
	show_errors   bool = true // Show error overlay in browser
}
```

DevConfig holds development mode settings

[[Return to contents]](#Contents)

## DisplayConfig
```v
struct DisplayConfig {
pub mut:
	kind DisplayKind = .browser
}
```

DisplayConfig selects and scopes the display backend.

[[Return to contents]](#Contents)

## DisplaySessionConfig
```v
struct DisplaySessionConfig {
	port   u16
	token  string
	width  int
	height int
	x      int
	y      int
	title  string
}
```

DisplaySessionConfig carries the generic, backend-agnostic parameters needed to present one UI window. Backend-specific options (e.g. Chromium window mode, WebView runtime flags) live on the backend's own config and are merged by the backend during spawn — the core never hardcodes them.

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

## EventData
```v
struct EventData {
pub:
	event_type EventType
	client_id  string
	message    string
	data       map[string]json2.Any
	request    ?Request
	response   ?Response
	err        ?VxuiErrorDetail
}
```

EventData contains event information

[[Return to contents]](#Contents)

## JsSandboxConfig
```v
struct JsSandboxConfig {
pub mut:
	enabled            bool = true        // Enable sandbox restrictions
	timeout_ms         int  = 5000        // Max execution time
	max_result_size    int  = 1024 * 1024 // Max result size in bytes (1MB)
	allow_eval         bool // Allow eval() in frontend (dangerous!)
	forbidden_patterns []string = [// Forbidden patterns
		'eval(',
		'Function(',
		'setTimeout(',
		'setInterval(',
		'XMLHttpRequest',
		'fetch(',
		'WebSocket',
		'import(',
	]
}
```

JsSandboxConfig controls JavaScript execution security

[[Return to contents]](#Contents)

## LogConfig
```v
struct LogConfig {
pub mut:
	level  log.Level = .info
	output string    = 'stderr'
}
```

LogConfig holds logging settings. `output` accepts 'stderr' (default), 'stdout', or a file path. The previous max_file_size/rotate_files/show_* fields never had any effect and were removed (see CHANGELOG).

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

## Request
```v
struct Request {
pub:
	id          string
	verb        Verb
	path        string
	parameters  map[string]string
	headers     map[string]string
	body        string
	client_id   string
	timestamp   time.Time
	raw_message map[string]json2.Any // Original message for compatibility
}
```

Request represents a type-safe request

[[Return to contents]](#Contents)

## Response
```v
struct Response {
pub mut:
	status  int               = 200
	headers map[string]string = {}
	body    string
}
```

Response represents a type-safe response

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

## VxuiErrorDetail
```v
struct VxuiErrorDetail {
pub:
	code    VxuiError
	message string
	details map[string]string
	cause   ?IError // Underlying error that caused this error
}
```

VxuiErrorDetail represents a structured error with code and details

[[Return to contents]](#Contents)

## msg
```v
fn (e VxuiErrorDetail) msg() string
```

msg returns the error message (implements IError interface)

[[Return to contents]](#Contents)

## code
```v
fn (e VxuiErrorDetail) code() int
```

code returns the error code (implements IError interface)

[[Return to contents]](#Contents)

## str
```v
fn (e VxuiErrorDetail) str() string
```

str returns the error message

[[Return to contents]](#Contents)

## with_cause
```v
fn (e VxuiErrorDetail) with_cause(cause IError) VxuiErrorDetail
```

with_cause creates a new error with an underlying cause

[[Return to contents]](#Contents)

## with_detail
```v
fn (e VxuiErrorDetail) with_detail(key string, value string) VxuiErrorDetail
```

with_detail adds a detail to the error

[[Return to contents]](#Contents)

## WebViewConfig
```v
struct WebViewConfig {}
```

WebViewConfig holds in-process WebView/WebKit backend options. Empty today; filled when a real WebView backend lands. @[heap] so a reference can be taken.

[[Return to contents]](#Contents)

## WebViewDisplay
```v
struct WebViewDisplay {
	config &WebViewConfig
}
```

WebViewDisplay is a reserved in-process WebView/WebKit backend. Its spawn is not yet implemented; it exists to prove the wiring is backend-agnostic — a real backend only needs to implement spawn() (and fill WebViewConfig).

[[Return to contents]](#Contents)

## spawn
```v
fn (mut b WebViewDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
```

[[Return to contents]](#Contents)

## WindowConfig
```v
struct WindowConfig {
pub mut:
	width  int = 800
	height int = 600
	x      int = -1 // -1 means center
	y      int = -1 // -1 means center
	title  string // window/page title; falls back to config.app_name when set
}
```

WindowConfig holds window configuration.

Note: only size/position/title are actually enforced by the browser launch; the previous resizable/min-size/frameless fields never had any effect and were removed (see CHANGELOG).

[[Return to contents]](#Contents)

#### Powered by vdoc. Generated on: 26 Aug 2026 12:04:03
