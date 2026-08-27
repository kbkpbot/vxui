module vxui

// vxui = browser + htmx + websocket + v

// vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!
import net.websocket
import os
import time
import log
import sync
import x.json2


// verb_strings maps string to Verb enum
// default_app_name is the fallback window/page title marker; a user-changed
// app_name (or an explicit window.title) is pushed to connected clients
const default_app_name = 'vxui-app'

const verb_strings = {
	'get':    Verb.get
	'post':   .post
	'put':    .put
	'delete': .delete
	'patch': .patch
}

// vxui_signal_handler asks the run loop to shut down by writing one byte to the
// reserved self-pipe write fd. This is async-signal-safe (a stack local plus a
// plain C write, no allocation and no V runtime calls); the loop polls the read
// end and breaks, running the normal cleanup path. The write fd (23) is reserved
// by run() via dup2; if that reservation failed the handler is never installed,
// so Ctrl-C falls back to the default termination (the host child still exits via
// PR_SET_PDEATHSIG, so no orphan webview remains).
fn vxui_signal_handler(_sig os.Signal) {
	mut b := u8(1)
	C.write(23, voidptr(&b), 1)
}

// Context is the main struct of vxui
pub struct Context {
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
	// A copy of this binary launched with --vxui-host is a native "browser"
	// child: it owns one OS window + its own main thread and renders the page
	// the parent framework serves over WebSocket. It must NOT start the
	// framework (WS server, routes, lifecycle) - just the window.
	if is_host_mode() {
		host_main()
		return
	}
	mut ctx := context_of(mut app)
	mut cleaned := false

	ctx.trigger_event(EventType.before_start, '', 'Starting application', {}, none, none, none)

	// Apply an optional config file (--config / VXUI_CONFIG / vxui.json) BEFORE
	// init()/new_display() so backend selection and other settings take effect.
	cp := resolve_config_path()
	if cp != '' {
		apply_config_file(mut ctx.config, cp) or { ctx.logger.warn('config file: ${err}') }
	}

	init(mut app)!

	// Graceful shutdown on Ctrl-C / SIGTERM. A self-pipe lets the OS signal
	// handler (which runs in a C/signal context and must stay async-signal-safe)
	// wake the run loop without touching V state: it writes one byte to a reserved
	// write fd, and the loop polls the read end. This closes both native-WebView
	// (the host child is sent 'close') and external-browser backends cleanly,
	// instead of leaving a detached browser open on Ctrl-C.
	ctx.setup_signal_shutdown()

	ctx.routes = generate_routes(app)!

	// Start client removal handler goroutine (serializes removal to prevent races)
	rm_thread := spawn fn [mut ctx] () {
		ctx.process_client_removals()
	}()

	// On any early `!` exit from run(), terminate host children and log shutdown.
	// (True panics are not interceptable in this V version; robustness there comes
	// from PR_SET_PDEATHSIG in the host child, which exits when the parent dies.)
	defer {
		if !cleaned {
			ctx.close_displays()
			ctx.teardown_signal_shutdown()
			ctx.logger.info('vxui shutdown complete')
		}
	}

	// Apply dev mode settings
	resolved_backend := resolve_backend_id(&ctx.config, ctx.config.display.id)
	if ctx.config.dev.enabled {
		if backend_family(resolved_backend) == .process {
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
		// A failed spawn (e.g. no browser found, or a backend id without a
		// native implementation such as the reserved `android`) must not leave
		// the WS server/port bound; the deferred cleanup closes displays and
		// frees the WS server.
		return err
	}

	frontend_kind := if backend_family(resolved_backend) == .embedded {
		'native WebView [${resolved_backend}]'
	} else {
		'browser [${resolved_backend}]'
	}
	ctx.logger.info('Frontend: ${frontend_kind}, waiting for connections on port ${ctx.ws_port}...')
	ctx.logger.debug('Auth token generated (hidden from logs)')

	ctx.trigger_event(EventType.after_start, '', 'Application started', {}, none, none, none)

	// Native WebView backends are now hosted in a child process (see
	// DisplayBackend.spawn), so the framework's main thread is free to run the
	// WebSocket service loop directly - identical to the external-browser path.
	// A window close surfaces as that child exiting, which the WS layer observes
	// as a client disconnect. No main-thread GTK ownership, no separate branch.
	ctx.serve_forever(html_filename, chan int{cap: 1})

	cleaned = true

	// Browser / detached-backend shutdown: serve_forever has returned on the
	// main thread (all clients gone / close timer), so the cleanup below runs
	// single-threaded. Stop the WS server, close the client-removal channel and
	// join its worker, fire before_shutdown, free displays, then return - the
	// process exits normally rather than via a forced C.exit.
	ctx.ws.free()
	ctx.client_remove_chan.close()
	rm_thread.wait()
	ctx.trigger_event(EventType.before_shutdown, '', 'Application shutting down', {}, none, none,
		none)
	ctx.close_displays()
	ctx.teardown_signal_shutdown()
	ctx.logger.info('vxui shutdown complete')
	return
}

// serve_forever runs the WebSocket service loop (client counting/grace window,
// heartbeat, hot reload). Non-generic: V 0.5.2 closures calling generic
// methods require explicit type params, so the unused `app` param was dropped.
fn (mut ctx Context) serve_forever(html_filename string, done chan int) {
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
		if ctx.shutdown_read_fd > 0 {
			mut b := u8(0)
			n := C.read(ctx.shutdown_read_fd, voidptr(&b), 1)
			if n > 0 {
				ctx.logger.info('Shutdown signal received')
				break_now = true
			}
		}
		if break_now {
			// Ask the native window to close through its own GTK/Win32 chain
			// so the UI loop unwinds and the process exits cleanly.
			if mut sess := ctx.display_session {
				sess.close() or {}
			}
			break
		}

		ctx.check_client_timeouts()

		// Heartbeat: send ping to all clients periodically
		last_ping_time = ctx.maybe_heartbeat(last_ping_time, client_count)

		// Hot reload check
		last_hot_reload_check = ctx.maybe_hot_reload(watch_dirs, mut file_mtimes,
			last_hot_reload_check, client_count)

		// If the UI window was closed (destroy handler nilled the native
		// window), break immediately so the worker exits with the UI.
		if mut sess := ctx.display_session {
			if sess.is_closed() {
				break
			}
		}

		time.sleep(10 * time.millisecond)
	}

	// When the UI owns the main thread, this worker finishing means shutdown
	// was requested from here (timer / all-clients-gone): ask the window to
	// close so the UI loop unwinds and the main thread resumes.
	done <- 1
}

// is_host_mode reports whether THIS process is a native "browser" child launched
// by DisplayBackend.spawn (rather than the framework application itself).
fn is_host_mode() bool {
	return os.args.contains('--vxui-host')
}

// host_main is the entry point for a native-browser child process. The parent
// passes the inherited control-pipe read fd as the argument right after
// `--vxui-host` (no env, so the token/url never leak via `ps`). host_main reads
// it, builds its one window, and runs that platform's UI loop until the window
// is closed - then exits. The framework (the parent) keeps running its
// WebSocket service loop untouched.
fn host_main() {
	mut ctl_fd := 0
	for i, a in os.args {
		if a == '--vxui-host' && i + 1 < os.args.len {
			ctl_fd = os.args[i + 1].int()
		}
	}
	if ctl_fd <= 0 {
		eprintln('vxui host: control pipe fd not provided')
		exit(1)
	}
	host_run(ctl_fd)
	exit(0)
}

// setup_signal_shutdown installs SIGINT/SIGTERM handlers that request a graceful
// shutdown, using a self-pipe so the handler stays async-signal-safe. The write
// end is dup2'd onto fd 23 (kept open, non-CLOEXEC) and the read end is made
// non-blocking; serve_forever polls it. On Windows there are no POSIX signals, so
// this is a no-op there.
fn (mut ctx Context) setup_signal_shutdown() {
	$if !windows {
		mut sp := [2]int{}
		if C.pipe(&sp[0]) != 0 {
			return
		}
		wfd := C.dup2(sp[1], 23)
		C.close(sp[1])
		if wfd != 23 {
			C.close(sp[0])
			return
		}
		// Make the read end non-blocking so the poll in the loop never blocks.
		flags := int(C.fcntl(sp[0], 3, voidptr(0))) // F_GETFL
		C.fcntl(sp[0], 4, voidptr(flags | 2048)) // F_SETFL | O_NONBLOCK
		ctx.shutdown_read_fd = sp[0]
		ctx.shutdown_write_fd = 23
		os.signal_opt(.int, vxui_signal_handler) or {}
		os.signal_opt(.term, vxui_signal_handler) or {}
	}
}

// teardown_signal_shutdown closes the self-pipe fds (idempotent). Safe to call
// from both the normal and error cleanup paths.
fn (mut ctx Context) teardown_signal_shutdown() {
	if ctx.shutdown_read_fd > 0 {
		C.close(ctx.shutdown_read_fd)
		ctx.shutdown_read_fd = 0
	}
	if ctx.shutdown_write_fd > 0 {
		C.close(ctx.shutdown_write_fd)
		ctx.shutdown_write_fd = 0
	}
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
