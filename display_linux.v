module vxui

import os

$if linux {
	fn C.malloc(size usize) voidptr
	fn C.free(ptr voidptr)
	fn C.memcpy(dst voidptr, src voidptr, n usize) voidptr

	// Linux implementation of the embedded (native WebView) display family:
	// WebKitGTK hosting the vxui HTML in a native GTK window.
	//
	// Selected by V's platform-dependent file mechanism: this file compiles ONLY on
	// Linux (`_linux` suffix); other platforms compile display_default.v (stub) or
	// their own variant (display_windows.v -> WebView2, future display_macos.v ->
	// WKWebView, future display_android.v -> JNI android.webkit.WebView).
	//
	// It must provide the embedded-family hook contract shared with the other
	// variants: embedded_native_id / embedded_spawn / embedded_session_*.

	// NOTE: pointer params/returns use `voidptr` (not `&C.GtkWidget`). When a `fn
	// C.*` lives in an imported module, V can otherwise emit an implicit `int`
	// prototype and truncate 64-bit pointers to 32 bits.
	#pkgconfig webkit2gtk-4.1
	#pkgconfig gtk+-3.0
	// Pull in the real GTK/WebKit headers so the C compiler sees correct prototypes
	// for the `fn C.*` calls below. V does not emit prototypes for `fn C.*`
	// declarations, so without these the compiler assumes `int` returns and
	// truncates 64-bit pointers (e.g. gtk_window_new) to 32 bits.
	#include <gtk/gtk.h>
	#include <gdk/gdkx.h>
	#include <webkit2/webkit2.h>


	fn C.gtk_init_check(argc voidptr, argv voidptr) bool
	fn C.gtk_window_new(typ int) voidptr
	fn C.gtk_window_set_default_size(w voidptr, width int, height int)
	fn C.gtk_window_set_title(w voidptr, title &char)
	fn C.gtk_window_set_position(w voidptr, pos int)
	fn C.gtk_window_close(w voidptr)
	fn C.gtk_window_resize(w voidptr, width int, height int)
	fn C.gtk_window_move(w voidptr, x int, y int)
	fn C.gtk_container_add(c voidptr, child voidptr)
	fn C.gtk_widget_show_all(w voidptr)
	fn C.gtk_widget_destroy(w voidptr)
	fn C.gtk_scrolled_window_new(hadj voidptr, vadj voidptr) voidptr
	fn C.webkit_web_view_new() voidptr
	fn C.webkit_web_view_load_uri(view voidptr, uri &char)
	fn C.g_idle_add(cb voidptr, data voidptr) u32
	fn C.g_signal_connect_data(instance voidptr, detailed_signal &char, c_handler voidptr, data voidptr, destroy_notify voidptr, connect_flags int) u64
	// GLib main-loop primitives: we drive the loop ourselves with
	// g_main_context_iteration (instead of gtk_main) so we can stop it via a
	// flag and drain pending events on teardown — mirroring webview/webview.
	fn C.g_main_context_iteration(context voidptr, may_block int) int
	fn C.exit(code int)

	// --- raw shared-state helpers -------------------------------------------------
	// V's managed references (@[heap] structs, &bool literals) corrupt when they
	// round-trip through voidptr into a C callback (they get collected/relocated
	// by V's GC, and a &bool literal lowers to a NULL pointer). So the close flag
	// is plain C-managed memory, mirroring webview/webview.
	fn set_bool(p voidptr, v bool) {
		unsafe { *(&bool(p)) = v }
	}

	fn get_bool(p voidptr) bool {
		return unsafe { *(&bool(p)) }
	}

	// gtk_on_delete_event handles the window-close request (WM_DELETE_WINDOW).
	// GTK's delete-event signal callback is (widget, event, user_data): the
	// shared session pointer arrives as the 3rd argument, so the handler MUST
	// declare all three parameters or user_data is dropped (a V FFI footgun that
	// previously handed the handler a garbage pointer and crashed teardown).
	// We set the raw quit flag and return FALSE so GTK runs its normal destroy
	// chain (-> WebKit teardown), which is clean in V once the flag is raw memory.
	fn gtk_on_delete_event(_window voidptr, _event voidptr, data voidptr) int {
		mut s := unsafe { &WebViewSession(data) }
		set_bool(s.quit, true)
		return 0 // FALSE: allow the default destroy to proceed
	}

	// gtk_on_destroy runs during the normal destroy chain. It records closure so
	// wait_closed()/is_closed() observe it. The destroy signal callback is
	// (widget, user_data) - 2 arguments - so user_data maps cleanly here.
	fn gtk_on_destroy(_window voidptr, data voidptr) int {
		mut s := unsafe { &WebViewSession(data) }
		set_bool(s.quit, true)
		s.window = unsafe { nil }
		return 0
	}

	// close_idle asks the main-loop thread to destroy the window. Called from a
	// g_idle_add marshaled out of another thread (e.g. the WebSocket worker).
	fn close_idle(data voidptr) int {
		mut s := unsafe { &WebViewSession(data) }
		set_bool(s.quit, true)
		if s.window != unsafe { nil } {
			C.gtk_widget_destroy(s.window)
		}
		return 0
	}

	// set_done_idle is the drain sentinel: once the loop has seen quit, we queue
	// one more iteration so pending teardown events are fully processed before
	// wait_closed returns.
	fn set_done_idle(data voidptr) int {
		set_bool(data, true)
		return 0
	}

	// embedded_native_id reports the native WebView backend carried by this build.
	fn embedded_native_id() string {
		return 'webkitgtk'
	}

	// embedded_spawn runs on the CALLER'S thread — which for native UI is the
	// process MAIN thread (vxui.run hands it over). GTK/WebKit are initialized
	// here and every later touch happens either here or via g_idle_add marshaling
	// from other threads. wait_closed() then parks this same thread in gtk_main().
	fn embedded_spawn(id string, html_path string, cfg DisplaySessionConfig) !DisplaySession {
		if id != 'webkitgtk' {
			return error('native WebView FFI not implemented on this platform (${id})')
		}
		abs_path := os.abs_path(html_path)
		if !os.exists(abs_path) {
			return error('HTML file not found: ${abs_path}')
		}
		url := launch_url(abs_path, cfg.port, cfg.token)
		if !C.gtk_init_check(unsafe { nil }, unsafe { nil }) {
			return error('webkitgtk: gtk_init_check failed (no display?)')
		}
		window := C.gtk_window_new(0) // GTK_WINDOW_TOPLEVEL
		if window == unsafe { nil } {
			return error('webkitgtk: gtk_window_new returned null')
		}
		C.gtk_window_set_default_size(window, cfg.width, cfg.height)
		if cfg.title != '' {
			C.gtk_window_set_title(window, &char(cfg.title.str))
		}
		C.gtk_window_set_position(window, 1) // GTK_WIN_POS_CENTER
		scrolled := C.gtk_scrolled_window_new(unsafe { nil }, unsafe { nil })
		C.gtk_container_add(window, scrolled)
		view := C.webkit_web_view_new()
		C.gtk_container_add(scrolled, view)
		quit := C.malloc(1)
		set_bool(quit, false)
		session := &WebViewSession{
			window: window
			view:   view
			quit:   quit
		}
		// Window-close (WM_DELETE_WINDOW) and the normal destroy chain share the
		// session pointer as user_data. Both set the raw quit flag; the destroy
		// handler also nils the window so is_closed() reports closure.
		C.g_signal_connect_data(window, &char(c'delete-event'), voidptr(gtk_on_delete_event),
			voidptr(session), unsafe { nil }, 0)
		C.g_signal_connect_data(window, &char(c'destroy'), voidptr(gtk_on_destroy),
			voidptr(session), unsafe { nil }, 0)
		C.webkit_web_view_load_uri(view, &char(url.str))
		C.gtk_widget_show_all(window)
		return session
	}

	// embedded_session_close asks the window to close through its own GTK chain
	// (posted on the main-loop thread via g_idle_add). When the window is the
	// user-closed one this is a no-op; otherwise it triggers the same clean
	// destroy path. wait_closed() then returns normally so framework cleanup runs.
	fn embedded_session_close(s &WebViewSession) {
		if s.window == unsafe { nil } {
			return
		}
		C.g_idle_add(voidptr(close_idle), voidptr(s))
	}

	// ---- idle-queue marshaling for window mutations ----
	enum GtkJobKind {
		resize
		move_win
		set_title
	}

	struct GtkJob {
	mut:
		kind GtkJobKind
		win  voidptr
		a    int
		b    int
		cstr voidptr // NUL-terminated copy, freed after run (set_title only)
	}

	fn heap_cstr(s string) voidptr {
		p := C.malloc(usize(s.len + 1))
		C.memcpy(p, voidptr(s.str), usize(s.len + 1))
		return p
	}

	fn gtk_job_idle(data voidptr) int {
		j := &GtkJob(data)
		match j.kind {
			.resize { C.gtk_window_resize(j.win, j.a, j.b) }
			.move_win { C.gtk_window_move(j.win, j.a, j.b) }
			.set_title { C.gtk_window_set_title(j.win, &char(j.cstr)) }
		}
		if j.cstr != unsafe { nil } {
			C.free(j.cstr)
		}
		C.free(data)
		return 0 // remove the source after one run
	}

	fn post_gtk_job(kind GtkJobKind, win voidptr, a int, b int, s string) {
		mut job := unsafe { &GtkJob(C.malloc(sizeof(GtkJob))) }
		job.kind = kind
		job.win = win
		job.a = a
		job.b = b
		job.cstr = unsafe { nil }
		if kind == .set_title {
			job.cstr = heap_cstr(s)
		}
		C.g_idle_add(voidptr(gtk_job_idle), job)
	}

	fn embedded_session_set_size(s &WebViewSession, w int, h int) {
		if s.window != unsafe { nil } {
			post_gtk_job(.resize, s.window, w, h, '')
		}
	}

	fn embedded_session_set_title(s &WebViewSession, t string) {
		if s.window != unsafe { nil } {
			post_gtk_job(.set_title, s.window, 0, 0, t)
		}
	}

	fn embedded_session_set_position(s &WebViewSession, x int, y int) {
		if s.window != unsafe { nil } {
			post_gtk_job(.move_win, s.window, x, y, '')
		}
	}

	// embedded_session_wait_closed drives the GLib main loop on the caller's
	// thread until the window is destroyed. The delete-event and destroy handlers
	// (and programmatic close) set the raw quit flag, so we stop once it is seen,
	// then drain one more iteration to finish pending teardown (window destroy +
	// WebKit shutdown). On return the caller runs framework cleanup and the
	// process exits normally - no forced _exit/exit(0) in the close path.
	fn embedded_session_wait_closed(mut _s WebViewSession) {
		for !get_bool(_s.quit) {
			C.g_main_context_iteration(unsafe { nil }, 1)
		}
		done := C.malloc(1)
		set_bool(done, false)
		C.g_idle_add(voidptr(set_done_idle), done)
		for !get_bool(done) {
			C.g_main_context_iteration(unsafe { nil }, 1)
		}
		C.free(done)
		C.free(_s.quit)
	}
}
