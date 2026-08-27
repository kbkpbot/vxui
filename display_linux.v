module vxui

import os
import x.json2

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
	// KEY DESIGN: this backend does NOT render in-process. embedded_spawn launches a
	// *child copy of the same vxui binary* in host mode (--vxui-host); that child
	// owns one GTK window + the GLib main loop and renders the page the parent
	// framework serves over WebSocket. Window ops (resize/title/position/close) are
	// forwarded to the child over an inherited control pipe. This keeps every
	// GTK/WebKit call on the child's own thread - no cross-thread hazards, process
	// isolation, and the framework reuses the external-browser lifecycle verbatim.

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
	fn C.gtk_main()
	fn C.gtk_main_quit()
	fn C.gtk_scrolled_window_new(hadj voidptr, vadj voidptr) voidptr
	fn C.webkit_web_view_new() voidptr
	fn C.webkit_web_view_load_uri(view voidptr, uri &char)
	fn C.g_idle_add(cb voidptr, data voidptr) u32
	fn C.g_signal_connect_data(instance voidptr, detailed_signal &char, c_handler voidptr, data voidptr, destroy_notify voidptr, connect_flags int) u64
	fn C.prctl(option int, arg int) int

	// --- native id ---------------------------------------------------------------
	fn embedded_native_id() string {
		return 'webkitgtk'
	}

	// embedded_spawn launches a child copy of THIS binary in host mode and returns a
	// HostSession handle. The child owns the GTK window + main loop; the parent keeps
	// running the framework's WebSocket service loop, unchanged.
	fn embedded_spawn(id string, html_path string, cfg DisplaySessionConfig) !DisplaySession {
		if id != 'webkitgtk' {
			return error('native WebView FFI not implemented on this platform (${id})')
		}
		abs_path := os.abs_path(html_path)
		if !os.exists(abs_path) {
			return error('HTML file not found: ${abs_path}')
		}
		url := launch_url(abs_path, cfg.port, cfg.token)
		mut fds := [2]int{}
		if C.pipe(&fds[0]) != 0 {
			return error('failed to create host control pipe')
		}
		r := fds[0]
		w := fds[1]
		C.fcntl(r, 2, voidptr(0))
		mut self := os.executable()
		if self == '' {
			self = '/proc/self/exe'
		}
		pid := os.fork()
		if pid < 0 {
			return error('failed to fork host process')
		}
		if pid == 0 {
			C.prctl(1, 15)
			os.execvp(self, [self, '--vxui-host', '${r}']) or {
				eprintln('vxui: failed to launch host: ${err}')
				exit(1)
			}
		}
		C.close(r)
		return finish_embedded_spawn(pid, w, HostHandshake{
			url: url, token: cfg.token, width: cfg.width, height: cfg.height,
			x: cfg.x, y: cfg.y, title: cfg.title,
		})
	}

	// host_run builds one WebKitGTK window, loads the page, and runs the GLib main
	// loop until the window is destroyed. It is only ever called inside a host-mode
	// child process (see run()'s is_host_mode guard).
	fn host_run(ctl_fd int) {
		hs := read_host_handshake(ctl_fd)
		if hs.url == '' {
			return
		}
		if !C.gtk_init_check(unsafe { nil }, unsafe { nil }) {
			eprintln('vxui host: gtk_init_check failed (no display?)')
			return
		}
		window := C.gtk_window_new(0)
		if window == unsafe { nil } {
			return
		}
		if hs.width > 0 && hs.height > 0 {
			C.gtk_window_set_default_size(window, hs.width, hs.height)
		}
		if hs.title != '' {
			C.gtk_window_set_title(window, &char(hs.title.str))
		}
		C.gtk_window_set_position(window, 1)
		scrolled := C.gtk_scrolled_window_new(unsafe { nil }, unsafe { nil })
		C.gtk_container_add(window, scrolled)
		view := C.webkit_web_view_new()
		C.gtk_container_add(scrolled, view)
		C.webkit_web_view_load_uri(view, &char(hs.url.str))
		C.gtk_widget_show_all(window)
		eprintln('vxui host: window opened')
		C.g_signal_connect_data(window, &char(c'delete-event'), voidptr(gtk_host_on_delete),
			voidptr(0), unsafe { nil }, 0)
		C.g_signal_connect_data(window, &char(c'destroy'), voidptr(gtk_host_on_destroy),
			voidptr(0), unsafe { nil }, 0)
		// Forward control commands to the GTK thread via g_idle_add.
		spawn fn [ctl_fd, window] () {
			host_read_control(ctl_fd, window)
		}()
		C.gtk_main()
	}

	fn host_read_control(fd int, window voidptr) {
		host_read_lines(fd, window, apply_host_control_line)
	}

	struct HostCmdJob {
	mut:
		window voidptr
		cmd   string
		w     int
		h     int
		x     int
		y     int
		title string
	}

	fn host_apply_idle(data voidptr) int {
		mut j := unsafe { &HostCmdJob(data) }
		if j.window != unsafe { nil } {
			match j.cmd {
				'resize' { C.gtk_window_resize(j.window, j.w, j.h) }
				'move' { C.gtk_window_move(j.window, j.x, j.y) }
				'title' { C.gtk_window_set_title(j.window, &char(j.title.str)) }
				'close' { C.gtk_widget_destroy(j.window) }
				else {}
			}
		}
		C.free(data)
		return 0
	}

	fn apply_host_control_line(line string, ctx voidptr) {
		mut j := unsafe { &HostCmdJob(C.malloc(sizeof(HostCmdJob))) }
		ctrl := json2.decode[HostControl](line) or {
			C.free(j)
			return
		}
		window := ctx
		j.window = window
		j.cmd = ctrl.cmd
		j.w = ctrl.w
		j.h = ctrl.h
		j.x = ctrl.x
		j.y = ctrl.y
		j.title = ctrl.title
		C.g_idle_add(voidptr(host_apply_idle), voidptr(j))
	}

	fn gtk_host_on_delete(_window voidptr, _event voidptr, _data voidptr) int {
		return 0 // FALSE: allow the default destroy chain
	}

	fn gtk_host_on_destroy(_window voidptr, _data voidptr) int {
		C.gtk_main_quit()
		return 0
	}
}
