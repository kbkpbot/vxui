module vxui

import os
import x.json2

#flag macos -framework Cocoa
#flag macos -framework WebKit
#flag macos -lobjc

$if macos {
	#include <objc/runtime.h>
	#include <objc/message.h>
	#include <AppKit/AppKit.h>
	#include <WebKit/WebKit.h>

	// ---- libc / runtime FFI ----
	fn C.pipe(fds &int) int
	fn C.fcntl(fd int, cmd int, arg int) int
	fn C.read(fd int, buf voidptr, count usize) int
	fn C.close(fd int) int
	fn C.malloc(size usize) voidptr
	fn C.free(ptr voidptr)
	fn C.memcpy(dst voidptr, src voidptr, n usize) voidptr
	fn C.objc_getClass(name &char) voidptr
	fn C.sel_registerName(name &char) voidptr
	fn C.dispatch_get_main_queue() voidptr
	fn C.dispatch_async_f(queue voidptr, context voidptr, work voidptr)

	// ---- typed objc_msgSend wrappers (avoids variadic ABI pitfalls) ----
	fn C.objc_msgSend(a voidptr, b voidptr) voidptr
	fn C.objc_msgSend_id(a voidptr, b voidptr, c voidptr) voidptr
	fn C.objc_msgSend_ptr(a voidptr, b voidptr, c voidptr) voidptr
	fn C.objc_msgSend_void(a voidptr, b voidptr)
	fn C.objc_msgSend_void_id(a voidptr, b voidptr, c voidptr)
	fn C.objc_msgSend_void_ptr(a voidptr, b voidptr, c voidptr)
	fn C.objc_msgSend_void_int(a voidptr, b voidptr, c int)
	fn C.objc_msgSend_void_size(a voidptr, b voidptr, c NSSize)
	fn C.objc_msgSend_void_point(a voidptr, b voidptr, c NSPoint)
	fn C.objc_msgSend_bool(a voidptr, b voidptr) int
	fn C.objc_msgSend_dbl(a voidptr, b voidptr, c f64) voidptr
	fn C.objc_msgSend_rect(a voidptr, b voidptr, c NSRect, d int, e int, f int) voidptr
	fn C.objc_msgSend_rect_cfg(a voidptr, b voidptr, c NSRect, d voidptr) voidptr

	// ---- Cocoa geometry types ----
	struct NSPoint {
		x f64
		y f64
	}

	struct NSSize {
		width  f64
		height f64
	}

	struct NSRect {
		origin NSPoint
		size   NSSize
	}

	fn sel(name string) voidptr {
		return C.sel_registerName(&char(name.str))
	}

	fn nsstring(s string) voidptr {
		return C.objc_msgSend_ptr(C.objc_getClass(c'NSString'), sel('stringWithUTF8String:'),
			&char(s.str))
	}

	fn cstr_dup(s string) &char {
		if s.len == 0 {
			return unsafe { nil }
		}
		buf := C.malloc(usize(s.len + 1))
		unsafe {
			C.memcpy(buf, voidptr(s.str), usize(s.len))
			(&char(buf))[s.len] = i8(0)
		}
		return &char(buf)
	}

	fn embedded_native_id() string {
		return 'wkwebview'
	}

	// embedded_spawn forks a child copy of THIS binary in host mode and returns a
	// HostSession handle. The child owns the NSWindow + WKWebView and runs the
	// NSApplication run loop; the parent keeps running the framework's WebSocket
	// service loop, unchanged.
	fn embedded_spawn(mut _b WebViewDisplay, id string, html_path string, cfg DisplaySessionConfig) !DisplaySession {
		if id != 'wkwebview' {
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
		C.fcntl(r, 2, 0)
		mut self := os.executable()
		if self == '' {
			self = '/proc/self/exe'
		}
		pid := os.fork()
		if pid < 0 {
			return error('failed to fork host process')
		}
		if pid == 0 {
			os.execvp(self, [self, '--vxui-host', '${r}']) or {
				eprintln('vxui: failed to launch host: ${err}')
				exit(1)
			}
		}
		C.close(r)
		write_host_handshake(w, HostHandshake{
			url:    url
			token:  cfg.token
			width:  cfg.width
			height: cfg.height
			x:      cfg.x
			y:      cfg.y
			title:  cfg.title
		})
		return HostSession{
			pid:       pid
			ctl_write: w
		}
	}

	// HostCmdJob is a malloc'd command marshalled from the pipe reader onto the
	// main thread via dispatch_async_f. win/nsapp are carried explicitly so no
	// global state is needed.
	struct HostCmdJob {
		code    int
		w       int
		h       int
		x       int
		y       int
		title_c &char
		win     voidptr
		nsapp   voidptr
	}

	// apply_host_job runs on the main thread (dispatched from the pipe reader).
	fn apply_host_job(job voidptr) {
		mut j := unsafe { &HostCmdJob(job) }
		match j.code {
			0 {
				sz := NSSize{f64(j.w), f64(j.h)}
				C.objc_msgSend_void_size(j.win, sel('setContentSize:'), sz)
			}
			1 {
				pt := NSPoint{f64(j.x), f64(j.y)}
				C.objc_msgSend_void_point(j.win, sel('setFrameOrigin:'), pt)
			}
			2 {
				if j.title_c != unsafe { nil } {
					ns := C.objc_msgSend_ptr(C.objc_getClass(c'NSString'),
						sel('stringWithUTF8String:'), voidptr(j.title_c))
					C.objc_msgSend_void_id(j.win, sel('setTitle:'), ns)
				}
			}
			3 {
				C.objc_msgSend_void(j.nsapp, sel('terminate:'), unsafe { nil })
			}
			else {}
		}
		if j.title_c != unsafe { nil } {
			C.free(voidptr(j.title_c))
		}
		C.free(job)
	}

	fn dispatch_job(code int, ctrl HostControl, win voidptr, nsapp voidptr) {
		mut j := unsafe { &HostCmdJob(C.malloc(sizeof(HostCmdJob))) }
		j.code = code
		j.w = ctrl.width
		j.h = ctrl.height
		j.x = ctrl.x
		j.y = ctrl.y
		j.title_c = cstr_dup(ctrl.title)
		j.win = win
		j.nsapp = nsapp
		C.dispatch_async_f(C.dispatch_get_main_queue(), voidptr(j), voidptr(apply_host_job))
	}

	// host_read_lines reads the control pipe until EOF, marshalling every parsed
	// HostControl command onto the main thread. EOF (parent gone) dispatches a
	// synthetic 'close' so the app terminates cleanly.
	fn host_read_lines(fd int, win voidptr, nsapp voidptr) {
		mut buf := ''
		mut chunk := [4096]u8{}
		for {
			n := C.read(fd, voidptr(&chunk[0]), usize(4096))
			if n <= 0 {
				eprintln('vxui host: control pipe closed, closing window')
				dispatch_job(3, HostControl{ cmd: 'close' }, win, nsapp)
				break
			}
			buf += chunk[..n].bytestr()
			for {
				mut nl := -1
				for i in 0 .. buf.len {
					if buf[i] == 10 {
						nl = i
						break
					}
				}
				if nl < 0 {
					break
				}
				line := buf[..nl].trim_space()
				buf = buf[nl + 1..]
				if line.len > 0 {
					apply_host_control_line(line, win, nsapp)
				}
			}
		}
	}

	fn apply_host_control_line(line string, win voidptr, nsapp voidptr) {
		ctrl := json2.decode[HostControl](line) or { return }
		code := match ctrl.cmd {
			'resize' { 0 }
			'move' { 1 }
			'title' { 2 }
			'close' { 3 }
			else { -1 }
		}
		if code < 0 {
			return
		}
		dispatch_job(code, ctrl, win, nsapp)
	}

	fn read_host_handshake(ctl_fd int) HostHandshake {
		mut buf := ''
		mut chunk := [4096]u8{}
		for {
			n := C.read(ctl_fd, voidptr(&chunk[0]), usize(4096))
			if n <= 0 {
				break
			}
			buf += chunk[..n].bytestr()
			for i in 0 .. buf.len {
				if buf[i] == 10 {
					return json2.decode[HostHandshake](buf[..i].trim_space()) or { HostHandshake{} }
				}
			}
		}
		return HostHandshake{}
	}

	// host_run builds one NSWindow + WKWebView, loads the page, and runs the
	// NSApplication run loop (in short bursts) until the window is closed or the
	// parent disconnects.
	fn host_run(ctl_fd int) {
		hs := read_host_handshake(ctl_fd)
		if hs.url == '' {
			return
		}

		nsapp := C.objc_msgSend(C.objc_getClass(c'NSApplication'), sel('sharedApplication'))
		C.objc_msgSend_void_int(nsapp, sel('setActivationPolicy:'), 0)

		rect := NSRect{
			origin: NSPoint{0, 0}
			size:   NSSize{f64(hs.width), f64(hs.height)}
		}
		win_alloc := C.objc_msgSend(C.objc_getClass(c'NSWindow'), sel('alloc'))
		win := C.objc_msgSend_rect(win_alloc, sel('initWithContentRect:styleMask:backing:defer:'),
			rect, 15, 2, 0)
		if win == unsafe { nil } {
			return
		}
		if hs.title != '' {
			C.objc_msgSend_void_id(win, sel('setTitle:'), nsstring(hs.title))
		}

		cfg := C.objc_msgSend(C.objc_msgSend(C.objc_getClass(c'WKWebViewConfiguration'),
			sel('alloc')), sel('init'))
		wv_alloc := C.objc_msgSend(C.objc_getClass(c'WKWebView'), sel('alloc'))
		wv := C.objc_msgSend_rect_cfg(wv_alloc, sel('initWithFrame:configuration:'), rect, cfg)
		C.objc_msgSend_void_id(win, sel('setContentView:'), wv)

		url := C.objc_msgSend_ptr(C.objc_getClass(c'NSURL'), sel('URLWithString:'),
			&char(hs.url.str))
		req := C.objc_msgSend_ptr(C.objc_getClass(c'NSURLRequest'), sel('requestWithURL:'), url)
		C.objc_msgSend_void_id(wv, sel('loadRequest:'), req)

		C.objc_msgSend_void_ptr(win, sel('makeKeyAndOrderFront:'), unsafe { nil })
		C.objc_msgSend_void_int(nsapp, sel('activateIgnoringOtherApps:'), 1)
		eprintln('vxui host: window opened')

		spawn fn [ctl_fd, win, nsapp] () {
			host_read_lines(ctl_fd, win, nsapp)
		}()

		rl := C.objc_msgSend(C.objc_getClass(c'NSRunLoop'), sel('currentRunLoop'))
		for {
			if C.objc_msgSend_bool(win, sel('isVisible')) == 0 {
				break
			}
			date := C.objc_msgSend_dbl(C.objc_getClass(c'NSDate'),
				sel('dateWithTimeIntervalSinceNow:'), 0.1)
			C.objc_msgSend_void_id(rl, sel('runUntilDate:'), date)
		}
	}
}
