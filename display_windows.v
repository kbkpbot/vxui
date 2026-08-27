module vxui

import os

$if windows {
	// Windows implementation of the embedded (native WebView) display family:
	// Microsoft Edge WebView2 hosting the vxui HTML.
	//
	// Selected by V's platform-dependent file mechanism: this file compiles ONLY on
	// Windows (`_windows` suffix). It must provide the embedded-family hook
	// contract shared with the other variants: embedded_native_id / embedded_spawn
	// / embedded_session_*.
	//
	// Strategy: link WebView2Loader (C-linkage export
	// CreateCoreWebView2EnvironmentWithOptions) and drive the asynchronous creation
	// through completion-handler COM objects we allocate ourselves. Win32 APIs
	// (HWND, message loop, window management) are used directly.
	//
	// The main thread owns the Win32 message loop (mirrors GTK's gtk_main):
	// wait_closed() parks inside wv2_message_loop() until PostQuitMessage.

	#flag windows -luser32
	#flag windows -lole32
	#flag windows -loleaut32
	#flag windows -lWebView2Loader

	// ---- Win32 types ----
	type HWND = voidptr
	type HINSTANCE = voidptr
	type ATOM = u16
	type LRESULT = voidptr

	struct POINT {
		x i32
		y i32
	}

	struct MSG {
		hwnd    voidptr
		message u32
		wparam  voidptr
		lparam  voidptr
		time    u32
		pt      POINT
	}

	struct WNDCLASSEXW {
		cb_size         u32
		style           u32
		lpfn_wnd_proc   voidptr
		cb_cls_extra    int
		cb_wnd_extra    int
		h_instance      voidptr
		h_icon          voidptr
		h_cursor        voidptr
		hbr_background  voidptr
		lpsz_menu_name  voidptr
		lpsz_class_name voidptr
		h_icon_sm       voidptr
	}

	// ---- WebView2 vtable structs ----
	// Every WebView2 interface starts with the 3 IUnknown methods, then its own.
	struct ICoreWebView2EnvironmentVtbl {
		query_interface                 fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref                         fn (this voidptr) u32
		release                         fn (this voidptr) u32
		create_core_webview2_controller fn (this voidptr, hwnd voidptr, handler voidptr) int
	}

	struct ICoreWebView2Environment {
		vtbl &ICoreWebView2EnvironmentVtbl
	}

	// ICoreWebView2Controller vtable. The method order follows the WebView2 SDK
	// (icorewebview2controller.h): IUnknown (3) + 24 controller methods.
	// Only get_CoreWebView2 (index 27) is used; others are placeholder slots.
	struct ICoreWebView2ControllerVtbl {
		// IUnknown (indices 0-2)
		query_interface fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref         fn (this voidptr) u32
		release         fn (this voidptr) u32
		// ICoreWebView2Controller (indices 3-27)
		get_is_visible                       fn (this voidptr, visible voidptr) int
		put_is_visible                       fn (this voidptr, visible int) int
		show                                 fn (this voidptr) int
		hide                                 fn (this voidptr) int
		close                                fn (this voidptr) int
		get_parent_window                    fn (this voidptr, hwnd voidptr) int
		put_parent_window                    fn (this voidptr, hwnd voidptr) int
		notify_parent_window_position_changed fn (this voidptr) int
		get_bounds                           fn (this voidptr, rect voidptr) int
		put_bounds                           fn (this voidptr, rect voidptr) int
		get_zoom_factor                      fn (this voidptr, factor voidptr) int
		put_zoom_factor                      fn (this voidptr, factor f64) int
		set_bounds_and_zoom_factor           fn (this voidptr, rect voidptr, factor f64) int
		move_focus                           fn (this voidptr, reason int) int
		add_got_focus                        fn (this voidptr, handler voidptr, token voidptr) int
		remove_got_focus                     fn (this voidptr, token voidptr) int
		add_lost_focus                       fn (this voidptr, handler voidptr, token voidptr) int
		remove_lost_focus                    fn (this voidptr, token voidptr) int
		add_move_focus_requested             fn (this voidptr, handler voidptr, token voidptr) int
		remove_move_focus_requested          fn (this voidptr, token voidptr) int
		add_accelerator_key_pressed          fn (this voidptr, handler voidptr, token voidptr) int
		remove_accelerator_key_pressed       fn (this voidptr, token voidptr) int
		add_zoom_factor_changed              fn (this voidptr, handler voidptr, token voidptr) int
		remove_zoom_factor_changed           fn (this voidptr, token voidptr) int
		get_core_webview2                    fn (this voidptr, core voidptr) int
	}

	struct ICoreWebView2Controller {
		vtbl &ICoreWebView2ControllerVtbl
	}

	// ICoreWebView2 vtable. NOTE: the method order below is reconstructed from the
	// WebView2 SDK and MUST be regenerated from the installed icorewebview2.h if
	// indices drift. Only `navigate` is used.
	struct ICoreWebView2Vtbl {
		query_interface fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref         fn (this voidptr) u32
		release         fn (this voidptr) u32
		get_settings    fn (this voidptr, settings voidptr) int
		get_source      fn (this voidptr, source voidptr) int
		navigate        fn (this voidptr, uri voidptr) int
	}

	struct ICoreWebView2 {
		vtbl &ICoreWebView2Vtbl
	}

	// Completion-handler interfaces we implement.
	struct IEnvCompletedVtbl {
		query_interface fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref         fn (this voidptr) u32
		release         fn (this voidptr) u32
		invoke          fn (this voidptr, errcode int, env voidptr) int
	}

	struct IEnvCompleted {
		vtbl &IEnvCompletedVtbl
		ctx  voidptr
	}

	struct ICtrlCompletedVtbl {
		query_interface fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref         fn (this voidptr) u32
		release         fn (this voidptr) u32
		invoke          fn (this voidptr, errcode int, ctrl voidptr) int
	}

	struct ICtrlCompleted {
		vtbl &ICtrlCompletedVtbl
		ctx  voidptr
	}

	// ---- shared context passed through the handlers ----
	struct Wv2Ctx {
		hwnd       voidptr
		env        voidptr
		controller voidptr
		core       voidptr
		done_event voidptr
		url        voidptr // wide string (malloc'd)
		session    voidptr // &WebViewSession, nilled on WM_DESTROY so is_closed() works
	}

	// ---- FFI: Win32 + WebView2Loader ----
	fn C.CreateCoreWebView2EnvironmentWithOptions(browser_exe_path voidptr, user_data_path voidptr, options voidptr, handler voidptr) int
	fn C.RegisterClassExW(wndclass voidptr) ATOM
	fn C.CreateWindowExW(ex_style u32, class_name voidptr, window_name voidptr, style u32, x int, y int, width int, height int, parent voidptr, menu voidptr, instance voidptr, param voidptr) HWND
	fn C.ShowWindow(hwnd HWND, cmd_show int) int
	fn C.UpdateWindow(hwnd HWND) int
	fn C.DestroyWindow(hwnd HWND) int
	fn C.PostQuitMessage(exit_code int)
	fn C.PostMessageW(hwnd HWND, msg u32, wparam voidptr, lparam voidptr) int
	fn C.SetWindowTextW(hwnd HWND, text voidptr) int
	fn C.MoveWindow(hwnd HWND, x int, y int, width int, height int, repaint int) int
	fn C.SetWindowLongPtrW(hwnd HWND, index int, new_long isize) isize
	fn C.GetWindowLongPtrW(hwnd HWND, index int) isize

	const gwlp_userdata = isize(-21)
	fn C.GetMessageW(msg voidptr, hwnd HWND, msg_filter_min u32, msg_filter_max u32) int
	fn C.TranslateMessage(msg voidptr) int
	fn C.DispatchMessageW(msg voidptr) LRESULT
	fn C.CreateEventW(attrs voidptr, manual_reset int, initial_state int, name voidptr) voidptr
	fn C.SetEvent(h voidptr) int
	fn C.WaitForSingleObject(h voidptr, ms u32) int
	fn C.GetModuleHandleW(module_name voidptr) HINSTANCE
	fn C.DefWindowProcW(hwnd HWND, msg u32, wparam voidptr, lparam voidptr) LRESULT
	fn C.malloc(size usize) voidptr
	fn C.free(ptr voidptr)

	// ---- UTF-8 -> UTF-16LE helper (caller frees with C.free) ----
	fn to_wide(s string) voidptr {
		mut n := 0
		for ch in s {
			c := ch.int()
			if c < 0x10000 {
				n++
			} else {
				n += 2
			}
		}
		buf := &u16(C.malloc(usize((n + 1) * 2)))
		mut i := 0
		for ch in s {
			c := ch.int()
			if c < 0x10000 {
				buf[i] = u16(c)
				i++
			} else {
				c2 := c - 0x10000
				buf[i] = u16(0xD800 + (c2 >> 10))
				buf[i + 1] = u16(0xDC00 + (c2 & 0x3FF))
				i += 2
			}
		}
		buf[i] = 0
		return voidptr(buf)
	}

	fn wide_free(p voidptr) {
		C.free(p)
	}

	// ---- COM completion handlers ----
	// QueryInterface: return `this` for anything (simple-handler hack).
	fn env_handler_qi(this voidptr, _riid voidptr, ppv voidptr) int {
		unsafe {
			*()&voidptr(ppv) = this
		}
		return 0 // S_OK
	}

	fn env_handler_addref(_this voidptr) u32 {
		return 1
	}

	fn env_handler_release(_this voidptr) u32 {
		return 1
	}

	fn env_handler_invoke(this voidptr, errcode int, env voidptr) int {
		if errcode != 0 || env == unsafe { nil } {
			C.SetEvent(()*Wv2Ctx(this).done_event)
			return 0
		}
		ctx := ()*Wv2Ctx(this)
		ctx.env = env
		// Create the controller against our host window.
		p := ()*ICoreWebView2Environment(env)
		f := p.vtbl.create_core_webview2_controller
		f(env, ctx.hwnd, make_ctrl_completed_handler(ctx))
		return 0 // S_OK
	}

	fn ctrl_handler_qi(this voidptr, _riid voidptr, ppv voidptr) int {
		unsafe {
			*()&voidptr(ppv) = this
		}
		return 0
	}

	fn ctrl_handler_addref(_this voidptr) u32 {
		return 1
	}

	fn ctrl_handler_release(_this voidptr) u32 {
		return 1
	}

	fn ctrl_handler_invoke(this voidptr, errcode int, controller voidptr) int {
		ctx := ()*Wv2Ctx(this)
		defer {
			C.SetEvent(ctx.done_event)
		}
		if errcode != 0 || controller == unsafe { nil } {
			return errcode
		}
		ctx.controller = controller
		// ICoreWebView2Controller::get_CoreWebView2 (vtable index 3).
		pc := ()*ICoreWebView2Controller(controller)
		get_core := pc.vtbl.get_core_webview2
		mut core := unsafe { nil }
		hr := get_core(controller, voidptr(&core))
		if hr != 0 || core == unsafe { nil } {
			return -1
		}
		ctx.core = core
		// ICoreWebView2::Navigate.
		p := ()*ICoreWebView2(core)
		nav := p.vtbl.navigate
		return nav(core, ctx.url)
	}

	fn make_env_completed_handler(ctx voidptr) voidptr {
		vt := unsafe { &IEnvCompletedVtbl(C.malloc(sizeof(IEnvCompletedVtbl))) }
		vt.query_interface = env_handler_qi
		vt.add_ref = env_handler_addref
		vt.release = env_handler_release
		vt.invoke = env_handler_invoke
		h := unsafe { &IEnvCompleted(C.malloc(sizeof(IEnvCompleted))) }
		h.vtbl = vt
		h.ctx = ctx
		return voidptr(h)
	}

	fn make_ctrl_completed_handler(ctx voidptr) voidptr {
		vt := unsafe { &ICtrlCompletedVtbl(C.malloc(sizeof(ICtrlCompletedVtbl))) }
		vt.query_interface = ctrl_handler_qi
		vt.add_ref = ctrl_handler_addref
		vt.release = ctrl_handler_release
		vt.invoke = ctrl_handler_invoke
		h := unsafe { &ICtrlCompleted(C.malloc(sizeof(ICtrlCompleted))) }
		h.vtbl = vt
		h.ctx = ctx
		return voidptr(h)
	}

	// ---- Win32 window + message loop ----
	// ---- Win32 constants ----
	const wm_destroy = u32(0x0002)
	const wm_close = u32(0x0010)

	fn wv2_wnd_proc(hwnd HWND, msg u32, wparam voidptr, lparam voidptr) LRESULT {
		if msg == wm_destroy {
			// Nil the session's window so the service worker's is_closed()
			// poll breaks its loop and the process exits with the UI.
			ud := C.GetWindowLongPtrW(hwnd, gwlp_userdata)
			if ud != 0 {
				unsafe {
					ctx := &Wv2Ctx(voidptr(ud))
					if ctx.session != unsafe { nil } {
						sess := &WebViewSession(ctx.session)
						sess.window = unsafe { nil }
					}
				}
			}
			C.PostQuitMessage(0)
			return LRESULT(0)
		}
		return C.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	fn wv2_create_host_window(title string, width int, height int) HWND {
		inst := C.GetModuleHandleW(unsafe { nil })
		class_name := to_wide('vxui_webview2')
		wc := WNDCLASSEXW{
			cb_size:         u32(sizeof(WNDCLASSEXW))
			style:           u32(0x0003) // CS_HREDRAW | CS_VREDRAW
			lpfn_wnd_proc:   voidptr(wv2_wnd_proc)
			h_instance:      inst
			lpsz_class_name: class_name
		}
		C.RegisterClassExW(voidptr(&wc))
		wtitle := to_wide(title)
		hwnd := C.CreateWindowExW(u32(0), class_name, wtitle, u32(0x00CF_0000), // WS_OVERLAPPEDWINDOW
		 0x8000_0000, 0x8000_0000, // CW_USEDEFAULT x2
		 width, height, unsafe { nil }, unsafe { nil }, inst, unsafe { nil })
		wide_free(wtitle)
		C.ShowWindow(hwnd, 5) // SW_SHOW
		C.UpdateWindow(hwnd)
		return hwnd
	}

	fn wv2_message_loop() {
		mut msg := MSG{}
		for {
			r := C.GetMessageW(voidptr(&msg), HWND(0), u32(0), u32(0))
			if r <= 0 {
				break
			}
			C.TranslateMessage(voidptr(&msg))
			C.DispatchMessageW(voidptr(&msg))
		}
	}

	// ---- embedded-family hook contract ----

	// embedded_native_id reports the native WebView backend carried by this build.
	fn embedded_native_id() string {
		return 'webview2'
	}

	fn embedded_spawn(id string, html_path string, cfg DisplaySessionConfig) !DisplaySession {
		if id != 'webview2' {
			return error('native WebView FFI not implemented on this platform (${id})')
		}
		return wv2_spawn(html_path, cfg)
	}

	fn wv2_spawn(html_path string, cfg DisplaySessionConfig) !DisplaySession {
		abs_path := os.abs_path(html_path)
		if !os.exists(abs_path) {
			return error('HTML file not found: ${abs_path}')
		}
		url := launch_url(abs_path, cfg.port, cfg.token)
		ctx := unsafe { &Wv2Ctx(C.malloc(sizeof(Wv2Ctx))) }
		ctx.hwnd = unsafe { nil }
		ctx.env = unsafe { nil }
		ctx.controller = unsafe { nil }
		ctx.core = unsafe { nil }
		ctx.url = to_wide(url)

		hwnd := wv2_create_host_window(cfg.title, cfg.width, cfg.height)
		ctx.hwnd = hwnd
		ctx.done_event = C.CreateEventW(unsafe { nil }, 1, 0, unsafe { nil })

		env_handler := make_env_completed_handler(voidptr(ctx))
		user_data := os.join_path(os.temp_dir(), 'vxui_webview2')
		os.mkdir_all(user_data) or {}
		udw := to_wide(user_data)

		// Async environment creation; the completion handler chains into
		// CreateCoreWebView2Controller and then Navigate.
		hr := C.CreateCoreWebView2EnvironmentWithOptions(unsafe { nil }, udw, unsafe { nil },
			env_handler)
		wide_free(udw)
		if hr != 0 {
			return error('webview2: CreateCoreWebView2EnvironmentWithOptions failed (${hr})')
		}

		// Wait until the CoreWebView2 is created and has navigated.
		res := C.WaitForSingleObject(ctx.done_event, 15000)
		if res != 0 {
			return error('webview2: timed out waiting for WebView creation')
		}
		C.free(ctx.done_event)
		return WebViewSession{
			window:     hwnd
			view:       ctx.core
			controller: ctx.controller
		}
	}

	fn embedded_session_close(s &WebViewSession) {
		if s.window != unsafe { nil } {
			// Call ICoreWebView2Controller::Close() to release WebView2
			// resources before destroying the host window.
			if s.controller != unsafe { nil } {
				pc := unsafe { &ICoreWebView2Controller(s.controller) }
				close_fn := pc.vtbl.close
				close_fn(s.controller)
			}
			// Post WM_CLOSE to the message loop (thread-safe); the default
			// handler calls DestroyWindow which emits WM_DESTROY → PostQuitMessage.
			C.PostMessageW(HWND(s.window), wm_close, unsafe { nil }, unsafe { nil })
		}
	}

	// wait_closed parks the MAIN thread inside the Win32 message loop until
	// the window is destroyed (PostQuitMessage). Mirrors the GTK approach:
	// the toolkit owns the main thread.
	fn embedded_session_wait_closed(_s &WebViewSession) {
		wv2_message_loop()
	}

	fn embedded_session_set_size(s &WebViewSession, w int, h int) {
		if s.window != unsafe { nil } {
			C.MoveWindow(HWND(s.window), 0, 0, w, h, 1)
		}
	}

	fn embedded_session_set_title(s &WebViewSession, t string) {
		if s.window != unsafe { nil } {
			wt := to_wide(t)
			C.SetWindowTextW(HWND(s.window), wt)
			wide_free(wt)
		}
	}

	fn embedded_session_set_position(s &WebViewSession, x int, y int) {
		if s.window != unsafe { nil } {
			C.MoveWindow(HWND(s.window), x, y, 0, 0, 1)
		}
	}
}
