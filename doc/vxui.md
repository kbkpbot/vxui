module vxui

fn apply_config_file(mut cfg Config, path string) !
fn backend_family(id string) DisplayFamily
fn escape_js(input string) string
fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string
fn generate_routes[T](app &T) !map[string]Route
fn get_free_port() !u16
fn load_config_file(path string) !FileConfig
fn new_display(id string, app_cfg &Config) !Display
fn new_error_detail(code VxuiError, message string) VxuiErrorDetail
fn new_error_detail_with_cause(code VxuiError, message string, cause IError) VxuiErrorDetail
fn new_error_detail_with_details(code VxuiError, message string, details map[string]string) VxuiErrorDetail
fn new_packed_app() PackedApp
fn parse_attrs(name string, attrs []string) !([]Verb, string)
fn resolve_auto(cfg &Config) string
fn resolve_backend_id(cfg &Config, override_id string) string
fn run[T](mut app T, html_filename string) !
fn run_packed[T](mut app T, mut packed PackedApp, entry_file string) !
fn sanitize_path(path string) !string
fn sanitize_utf8(s string) string
fn BrowserEngine.from[W](input W) !BrowserEngine
fn BrowserType.from[W](input W) !BrowserType
fn DisplayFamily.from[W](input W) !DisplayFamily
fn EventType.from[W](input W) !EventType
fn Verb.from[W](input W) !Verb
fn VxuiError.from[W](input W) !VxuiError
fn WindowMode.from[W](input W) !WindowMode
interface Display {
mut:
	spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
}
interface DisplaySession {
mut:
	close() !
	set_size(w int, h int)
	set_title(t string)
	set_position(x int, y int)
	// wait_closed blocks until the window is gone. Backends that hand the
	// caller's thread to a native toolkit loop (GTK/WebView2) park inside it;
	// detached backends (external browser) return immediately.
	wait_closed() !
	// is_closed reports whether the window has already been destroyed (e.g. the
	// user closed it). The service worker uses it to break its loop promptly.
	is_closed() bool
}
type EventHandler = fn (EventData)
fn (mut d NullDisplay) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
fn (mut s ProcessSession) close() !
fn (mut s ProcessSession) set_size(w int, h int)
fn (mut s ProcessSession) set_title(t string)
fn (mut s ProcessSession) set_position(x int, y int)
fn (mut s ProcessSession) wait_closed() !
fn (mut s ProcessSession) is_closed() bool
enum BrowserEngine {
	auto   // probe system (default)
	chrome // Chromium-family (google-chrome / chromium)
	firefox
	edge   // Chromium-family (microsoft-edge)
	brave  // Chromium-family (brave)
	safari // macOS Safari
	system // platform default launcher
}
enum BrowserType {
	chrome
	firefox
	safari
	edge
	brave
	chromium
	unknown
}
enum DisplayFamily {
	process  // external child process (e.g. a system browser)
	embedded // hosted native view in an independent child process (e.g. WebView2 / WKWebView / WebKitGTK)
}
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
enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}
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
	port_not_available
	browser_not_found
	file_not_found
	path_traversal
	route_not_found
	// Additional error codes for unified error handling
	profile_create_failed
	process_fork_failed
	hidden_file_access
	null_byte_detected
	absolute_path_not_allowed
	invalid_method
	attribute_parse_error
}
enum WindowMode {
	app    // standalone window WITHOUT address bar/tab strip (default)
	kiosk  // borderless fullscreen
	normal // an ordinary browser tab
}
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
	engine            BrowserEngine = .auto // Which engine/executable to launch
}
struct Client {
pub:
	id    string
	token string
pub mut:
	connection ?&websocket.Client
	last_ping  time.Time
}
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

	// WebView settings: native WebView/WebKit host backends (WebKitGTK on Linux,
	// WKWebView on macOS, WebView2 on Windows). Each is hosted in an independent
	// lightweight child process via the --vxui-host control-pipe protocol; the
	// `android` id is still a reserved placeholder.
	webview WebViewConfig // reserved placeholder; not yet applied by host backends (see WebViewConfig)

	// Display backend selection
	display DisplayConfig

	// Logging settings
	log LogConfig
}
struct Context {
mut:
	ws_port            u16
	ws                 websocket.Server
	shutdown_read_fd   int
	shutdown_write_fd  int
	display            Display = NullDisplay{}
	display_session    ?DisplaySession
	display_sessions   []DisplaySession
	routes             map[string]Route
	clients            map[string]Client
	mu                 sync.RwMutex
	js_callbacks       map[string]chan string
	event_handlers     map[EventType][]EventHandler
	client_remove_chan chan ClientRemoveMsg // channel for serialized client removal
	// app_ptr is an erased pointer to the concrete user App struct (set at
	// startup). It lets the non-generic WebSocket callbacks reach the user's
	// route methods via `dispatch` without making the callbacks generic.
	app_ptr voidptr
	// dispatch is a type-erased trampoline (monomorphized per App type) that
	// runs the registered route handler for a message. Initialized to nil;
	// startup_ws_server sets it before the server accepts any frame.
	dispatch fn (mut ctx Context, _method_name string, message map[string]json2.Any) !Response = unsafe { nil }
pub mut:
	config Config
	logger &log.Log = &log.Log{}
}
fn (mut ctx Context) broadcast(message string) !
fn (mut ctx Context) broadcast_except(message string, except_client_id string) !
fn (mut ctx Context) close_client(client_id string) !
fn (mut ctx Context) close_displays()
fn (mut ctx Context) get_client(client_id string) ?Client
fn (mut ctx Context) get_client_count() int
fn (mut ctx Context) get_clients() []string
fn (ctx Context) get_config() Config
fn (ctx Context) get_port() u16
fn (ctx Context) get_token() string
fn (mut ctx Context) on_event(event_type EventType, handler EventHandler)
fn (mut ctx Context) open_window(html_filename string) !
fn (mut ctx Context) open_window_with(html_filename string, window WindowConfig) !
fn (mut ctx Context) ping_all_clients()
fn (mut ctx Context) ping_client(client_id string) !
fn (mut ctx Context) post_js(js_code string) !
fn (mut ctx Context) post_js_client(client_id string, js_code string) !
fn (mut ctx Context) process_client_removals()
fn (mut ctx Context) run_js(js_code string, timeout_ms int) !string
fn (mut ctx Context) run_js_client(client_id string, js_code string, timeout_ms int) !string
fn (mut ctx Context) send_to_client(client_id string, message string) !
fn (mut ctx Context) set_browser_config(config BrowserConfig)
fn (mut ctx Context) set_js_sandbox(config JsSandboxConfig)
fn (mut ctx Context) set_webview_config(config WebViewConfig)
fn (mut ctx Context) trigger_hot_reload() !
struct DevConfig {
pub mut:
	enabled       bool // Enable development mode
	hot_reload    bool = true // Enable hot reload (refresh browser on file change)
	watch_dirs    []string // Directories to watch for changes (default: html file dir)
	watch_ms      int  = 500  // File watch interval in milliseconds
	auto_devtools bool = true // Auto-open DevTools in dev mode
	show_errors   bool = true // Show error overlay in browser
}
struct DisplayBackend {
pub mut:
	family  DisplayFamily
	id      string
	engine  BrowserEngine  // .process family
	browser &BrowserConfig // .process family
	webview &WebViewConfig // .embedded family
}
fn (mut b DisplayBackend) spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession
struct DisplayConfig {
pub mut:
	id string = 'auto'
}
struct DisplaySessionConfig {
	port   u16
	token  string
	width  int
	height int
	x      int
	y      int
	title  string
}
struct EmbeddedFile {
pub:
	data []u8
	size int
}
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
struct FileConfig {
mut:
	display        map[string]json2.Any
	browser        map[string]json2.Any
	webview        map[string]json2.Any
	window         map[string]json2.Any
	dev            map[string]json2.Any
	token          string
	multi_client   ?bool
	evict_on_new   ?bool
	close_timer_ms ?int
}
struct HostControl {
	cmd   string
	w     int
	h     int
	x     int
	y     int
	title string
}
struct HostHandshake {
	url    string
	token  string
	width  int
	height int
	x      int
	y      int
	title  string
}
struct HostSession {
mut:
	pid       int
	ctl_write int
	reaped    bool
}
fn (mut s HostSession) close() !
fn (mut s HostSession) set_size(w int, h int)
fn (mut s HostSession) set_title(t string)
fn (mut s HostSession) set_position(x int, y int)
fn (mut s HostSession) wait_closed() !
fn (mut s HostSession) is_closed() bool
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
struct LogConfig {
pub mut:
	level  log.Level = .info
	output string    = 'stderr'
}
struct PackedApp {
pub mut:
	files map[string]EmbeddedFile
}
fn (mut p PackedApp) add_file(path string, data []u8)
fn (mut p PackedApp) add_file_string(path string, content string)
fn (p PackedApp) extract_to(dir string) !
fn (p PackedApp) extract_to_temp() !string
fn (p PackedApp) get_file(path string) !EmbeddedFile
fn (p PackedApp) get_file_content(path string) !string
fn (p PackedApp) has_file(path string) bool
fn (p PackedApp) list_files() []string
fn (p PackedApp) total_size() int
fn (p PackedApp) cleanup(dir string)
struct Request {
pub:
	verb        Verb
	path        string
	client_id   string
	raw_message map[string]json2.Any // Original message for compatibility
}
struct Response {
pub mut:
	status int = 200
	body   string
}
struct Route {
	verb []Verb
	path string
}
struct VxuiErrorDetail {
pub:
	code    VxuiError
	message string
	details map[string]string
	cause   ?IError // Underlying error that caused this error
}
fn (e VxuiErrorDetail) msg() string
fn (e VxuiErrorDetail) code() int
fn (e VxuiErrorDetail) str() string
fn (e VxuiErrorDetail) with_cause(cause IError) VxuiErrorDetail
fn (e VxuiErrorDetail) with_detail(key string, value string) VxuiErrorDetail
struct WebViewConfig {}
struct WindowConfig {
pub mut:
	width  int = 800
	height int = 600
	x      int = -1 // -1 means center
	y      int = -1 // -1 means center
	title  string // window/page title; falls back to config.app_name when set
}
