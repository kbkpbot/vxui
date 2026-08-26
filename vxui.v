module vxui

// vxui = browser + htmx + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import net.websocket
import os
import time
import log
import sync

// verb_strings maps string to Verb enum
// default_app_name is the fallback window/page title marker; a user-changed
// app_name (or an explicit window.title) is pushed to connected clients
const default_app_name = 'vxui-app'

const verb_strings = {
	'get':    Verb.get
	'post':   .post
	'put':    .put
	'delete': .delete
	'patch':  .patch
}

// Context is the main struct of vxui
pub struct Context {
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

// =============================================================================
// Initialization
// =============================================================================

// context_of returns the embedded Context of a user app struct.
// The embedded field name `Context` is public, so this works across module
// boundaries while the Context internals stay private. Callers always pass
// `mut app`, so the reference is guaranteed to outlive the call.
fn context_of[T](mut app T) &Context {
	return unsafe { &app.Context }
}

// init initializes the vxui framework
fn init[T](mut app T) ! {
	mut ctx := context_of(mut app)
	ctx.ws_port = get_free_port()!

	// Generate security token if not set
	if ctx.config.token == '' {
		ctx.config.token = generate_token()
	}

	// Initialize maps
	ctx.clients = map[string]Client{}
	ctx.js_callbacks = map[string]chan string{}
	ctx.client_remove_chan = chan ClientRemoveMsg{cap: 100}

	// Setup logger (level + output destination)
	ctx.logger.set_level(ctx.config.log.level)
	match ctx.config.log.output {
		'stderr' {
			ctx.logger.set_output_stream(os.stderr())
		}
		'stdout', '' {
			// library default writes to the console
		}
		else {
			// treat anything else as a file path
			ctx.logger.set_output_path(ctx.config.log.output)
		}
	}

	ctx.ws = startup_ws_server(mut app, .ip, ctx.ws_port)!

	ctx.display = new_display(ctx.config.display.id, &ctx.config) or { return err }
}

// =============================================================================
// Main Entry Points
// =============================================================================

// run opens the `html_filename` in browser and starts the event loop
pub fn run[T](mut app T, html_filename string) ! {
	mut ctx := context_of(mut app)

	ctx.trigger_event(EventType.before_start, '', 'Starting application', {}, none, none, none)

	// Apply an optional config file (--config / VXUI_CONFIG / vxui.json) BEFORE
	// init()/new_display() so backend selection and other settings take effect.
	cp := resolve_config_path()
	if cp != '' {
		apply_config_file(mut ctx.config, cp) or { ctx.logger.warn('config file: ${err}') }
	}

	init(mut app)!

	ctx.routes = generate_routes(app)!

	// Start client removal handler goroutine (serializes removal to prevent races)
	spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// Apply dev mode settings
	if ctx.config.dev.enabled {
		if backend_family(ctx.config.display.id) == .process {
			ctx.config.browser.devtools = ctx.config.dev.auto_devtools
		}
		ctx.logger.info('Development mode enabled')
	}

	session_cfg := DisplaySessionConfig{
		port:   ctx.ws_port
		token:  ctx.config.token
		width:  ctx.config.window.width
		height: ctx.config.window.height
		x:      ctx.config.window.x
		y:      ctx.config.window.y
		title:  ctx.config.window.title
	}
	ctx.display_session = ctx.display.spawn(html_filename, session_cfg) or {
		// A failed spawn (e.g. no browser found, or a reserved backend not
		// yet implemented) must not leave the WS server/port bound.
		ctx.ws.free()
		return err
	}

	ctx.logger.info('Browser started, waiting for connections on port ${ctx.ws_port}...')
	ctx.logger.debug('Auth token generated (hidden from logs)')

	ctx.trigger_event(EventType.after_start, '', 'Application started', {}, none, none, none)

	// Hot reload: track file modification times
	mut file_mtimes := map[string]time.Time{}
	mut watch_dirs := ctx.config.dev.watch_dirs.clone()
	if watch_dirs.len == 0 {
		// Default to the directory containing the HTML file
		watch_dirs << os.dir(os.abs_path(html_filename))
	}

	if ctx.config.dev.enabled && ctx.config.dev.hot_reload {
		ctx.logger.info('Hot reload watching: ${watch_dirs}')
		file_mtimes = scan_file_mtimes(watch_dirs)
	}

	mut ws_state := websocket.State.open

	mut last_client_time := time.now()

	mut last_hot_reload_check := time.now()

	mut last_ping_time := time.now()

	mut had_clients := false // Track if we ever had clients

	mut empty_since := time.Time{} // when the last client left (grace window)

	mut break_now := false

	for {
		ws_state = ctx.ws.get_state()

		ctx.mu.rlock()

		client_count := ctx.clients.len

		ctx.mu.runlock()

		if ws_state == .closed {
			ctx.logger.info('WebSocket server closed')

			break
		}

		// Close-timer / all-clients-disconnected grace logic
		break_now, had_clients, empty_since, last_client_time = ctx.should_shutdown(had_clients,
			empty_since, last_client_time, client_count)
		if break_now {
			break
		}

		app.check_client_timeouts()

		// Heartbeat: send ping to all clients periodically
		last_ping_time = ctx.maybe_heartbeat(last_ping_time, client_count)

		// Hot reload check
		last_hot_reload_check = ctx.maybe_hot_reload(watch_dirs, mut file_mtimes,
			last_hot_reload_check, client_count)

		time.sleep(10 * time.millisecond)
	}

	ctx.trigger_event(EventType.before_shutdown, '', 'Application shutting down', {}, none, none,
		none)

	ctx.close_displays()

	ctx.ws.free()
	ctx.logger.info('vxui shutdown complete')
}

// should_shutdown encapsulates the close-timer / all-clients-disconnected
// grace logic of the run loop. It returns whether the loop should break
// plus the (possibly updated) grace-state locals had_clients / empty_since /
// last_client_time.
fn (mut ctx Context) should_shutdown(had_clients bool, empty_since time.Time, last_client_time time.Time, client_count int) (bool, bool, time.Time, time.Time) {
	if client_count == 0 {
		if had_clients {
			// Grace window: a page RELOAD delivers client_close / FIN for
			// the old connection and reconnects a moment later. Exiting
			// immediately here turned every F5 into an app suicide.
			// Wait ~1.5s; a reconnecting client clears empty_since.
			mut new_empty_since := empty_since
			if new_empty_since.is_zero() {
				new_empty_since = time.now()
			}

			if time.now().unix_milli() - new_empty_since.unix_milli() > 1500 {
				ctx.logger.info('All clients disconnected, shutting down')

				return true, had_clients, new_empty_since, last_client_time
			}

			return false, had_clients, new_empty_since, last_client_time
		} else {
			// Never had clients, wait for timeout

			elapsed_ms := time.now().unix_milli() - last_client_time.unix_milli()

			if elapsed_ms > ctx.config.close_timer_ms {
				ctx.logger.info('No clients connected for ${ctx.config.close_timer_ms}ms, shutting down')

				return true, had_clients, empty_since, last_client_time
			}
		}
	} else {
		// Had a client this tick: clear grace state
		return false, true, time.Time{}, time.now()
	}

	return false, had_clients, empty_since, last_client_time
}

// maybe_heartbeat sends a ping to all clients when the ping interval has
// elapsed and at least one client is connected. It returns the (possibly
// updated) last_ping_time.
fn (mut ctx Context) maybe_heartbeat(last_ping_time time.Time, client_count int) time.Time {
	now := time.now()

	if client_count > 0
		&& now.unix_milli() - last_ping_time.unix_milli() >= ctx.config.ws_ping_interval_ms {
		ctx.ping_all_clients()

		ctx.logger.debug('Sent heartbeat ping to all clients')

		return now
	}

	return last_ping_time
}

// maybe_hot_reload triggers a browser reload when watched files change, but
// only in dev mode with hot_reload enabled and at least one client connected.
// It returns the (possibly updated) last_hot_reload_check timestamp.
fn (mut ctx Context) maybe_hot_reload(watch_dirs []string, mut file_mtimes map[string]time.Time, last_hot_reload_check time.Time, client_count int) time.Time {
	if ctx.config.dev.enabled && ctx.config.dev.hot_reload && client_count > 0 {
		now := time.now()

		if now.unix_milli() - last_hot_reload_check.unix_milli() >= ctx.config.dev.watch_ms {
			new_mtimes := scan_file_mtimes(watch_dirs)

			if has_files_changed(file_mtimes, new_mtimes) {
				ctx.logger.info('Files changed, triggering hot reload')

				file_mtimes = new_mtimes.clone()

				ctx.trigger_hot_reload() or { ctx.logger.warn('Hot reload failed: ${err}') }
			}

			return now
		}
	}

	return last_hot_reload_check
}

// =============================================================================
// Packed/Embedded App Support
// =============================================================================

// run_packed runs the app with packed (embedded) resources
pub fn run_packed[T](mut app T, mut packed PackedApp, entry_file string) ! {
	temp_dir := packed.extract_to_temp()!
	app.logger.info('Extracted packed files to: ${temp_dir}')

	entry_path := os.join_path(temp_dir, entry_file)

	run(mut app, entry_path) or {
		packed.cleanup(temp_dir)
		return err
	}

	packed.cleanup(temp_dir)
}
