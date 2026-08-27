module vxui

import os
import x.json2

$if windows {
	// Windows implementation of the embedded (native WebView) display family:
	// Microsoft Edge WebView2 hosting the vxui HTML.
	//
	// Like the Linux/WebKitGTK variant, each native window is a *separate* child
	// copy of the same vxui binary, launched in `--vxui-host` mode (self-reexec).
	// The parent and host talk over an inherited control pipe using the shared
	// HostHandshake / HostControl protocol (see display.v). This keeps one uniform
	// code path across platforms and isolates every window on its own main thread.
	//
	// The host process owns the Win32 message loop on its main thread (mirrors
	// GTK's gtk_main). Control messages read from the pipe are marshalled onto
	// that thread via PostMessage.

	#flag windows -luser32
	#flag windows -lole32
	#flag windows -loleaut32
	#flag windows -lWebView2Loader
	#flag windows -ladvapi32

	// ---- Win32 types ----
	type HWND = voidptr
	type HINSTANCE = voidptr
	type HANDLE = voidptr
	type ATOM = u16
	type LRESULT = voidptr
	type BOOL = int
	type DWORD = u32

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

	struct SECURITY_ATTRIBUTES {
		n_length             u32
		lp_security_descriptor voidptr
		b_inherit_handle     BOOL
	}

	struct STARTUPINFOW {
		cb              u32
		lp_reserved     voidptr
		lp_desktop      voidptr
		lp_title        voidptr
		dw_x            u32
		dw_y            u32
		dw_x_size       u32
		dw_y_size       u32
		dw_x_count_chars u32
		dw_y_count_chars u32
		dw_fill_attribute u32
		dw_flags        u32
		w_show_window   u16
		cb_reserved2    u16
		lp_reserved2    voidptr
		h_std_input     voidptr
		h_std_output    voidptr
		h_std_error     voidptr
	}

	struct PROCESS_INFORMATION {
		h_process    voidptr
		h_thread     voidptr
		dw_process_id u32
		dw_thread_id u32
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
	struct ICoreWebView2EnvironmentVtbl {
		query_interface                  fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref                          fn (this voidptr) u32
		release                          fn (this voidptr) u32
		create_core_webview2_controller  fn (this voidptr, hwnd voidptr, handler voidptr) int
	}

	struct ICoreWebView2Environment {
		vtbl &ICoreWebView2EnvironmentVtbl
	}

	struct ICoreWebView2ControllerVtbl {
		query_interface fn (this voidptr, riid voidptr, ppv voidptr) int
		add_ref         fn (this voidptr) u32
		release         fn (this voidptr) u32
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
		remove_zoom_factor_changed          fn (this voidptr, token voidptr) int
		get_core_webview2                    fn (this voidptr, core voidptr) int
	}

	struct ICoreWebView2Controller {
		vtbl &ICoreWebView2ControllerVtbl
	}

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

	// ---- shared context passed through the WebView2 handlers ----
	struct Wv2Ctx {
		hwnd       voidptr
		env        voidptr
		controller voidptr
		core       voidptr
		done_event voidptr
		url        voidptr // wide string (malloc'd)
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
	fn C.CreatePipe(read voidptr, write voidptr, sa voidptr, size u32) int
	fn C.CreateProcessW(app_name voidptr, cmd_line voidptr, proc_attr voidptr, thread_attr voidptr, inherit BOOL, flags DWORD, env voidptr, cwd voidptr, si voidptr, pi voidptr) int
	fn C.CloseHandle(h HANDLE) int
	fn C._open_osfhandle(h HANDLE, flags int) int
	fn C._close(fd int) int

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
		p := ()*ICoreWebView2Environment(env)
		f := p.vtbl.create_core_webview2_controller
		f(env, ctx.hwnd, make_ctrl_completed_handler(voidptr(ctx)))
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
		pc := ()*ICoreWebView2Controller(controller)
		get_core := pc.vtbl.get_core_webview2
		mut core := unsafe { nil }
		hr := get_core(controller, voidptr(&core))
		if hr != 0 || core == unsafe { nil } {
			return -1
		}
		ctx.core = core
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
	const wm_destroy = u32(0x0002)
	const wm_close = u32(0x0010)
	const wm_user_cmd = u32(0x0400 + 1) // WM_USER + 1: apply a HostControl command

	// Control job marshalled from the pipe reader onto the UI thread.
	struct Wv2CmdJob {
		code  int // 0=resize, 1=move, 2=title, 3=close
		w     int
		h     int
		x     int
		y     int
		title voidptr // wide string (malloc'd, freed by handler) or nil
	}

	fn wv2_wnd_proc(hwnd HWND, msg u32, wparam voidptr, lparam voidptr) LRESULT {
		if msg == wm_destroy {
			C.PostQuitMessage(0)
			return LRESULT(0)
		}
		if msg == wm_user_cmd {
			job := &Wv2CmdJob(lparam)
			match job.code {
				0 { C.MoveWindow(hwnd, 0, 0, job.w, job.h, 1) }
				1 { C.MoveWindow(hwnd, job.x, job.y, 0, 0, 1) }
				2 { if job.title != unsafe { nil } { C.SetWindowTextW(hwnd, job.title) } }
				3 { C.DestroyWindow(hwnd) }
				else {}
			}
			if job.title != unsafe { nil } {
				C.free(job.title)
			}
			C.free(voidptr(job))
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

	// ---- embedded-family hook contract (self-reexec host) ----

	fn embedded_native_id() string {
		return 'webview2'
	}

	// embedded_spawn forks a child copy of the same binary in --vxui-host mode,
	// passing an inherited read end of a control pipe. The parent keeps the write
	// end and feeds it the handshake + control commands.
	fn embedded_spawn(id string, html_path string, cfg DisplaySessionConfig) !DisplaySession {
		if id != 'webview2' {
			return error('native WebView FFI not implemented on this platform (${id})')
		}
		abs_path := os.abs_path(html_path)
		if !os.exists(abs_path) {
			return error('HTML file not found: ${abs_path}')
		}
		url := launch_url(abs_path, cfg.port, cfg.token)

		mut fds := [0, 0]int
		mut sa := SECURITY_ATTRIBUTES{ n_length: u32(sizeof(SECURITY_ATTRIBUTES)), b_inherit_handle: 1 }
		if C.CreatePipe(voidptr(&fds[0]), voidptr(&fds[1]), voidptr(&sa), 0) != 0 {
			return error('failed to create host control pipe')
		}
		read_h := HANDLE(fds[0])
		write_h := HANDLE(fds[1])
		// Convert the write HANDLE to a CRT fd so the shared write_host_handshake /
		// write_host_cmd (which call C.write) work on Windows too.
		wfd := C._open_osfhandle(write_h, 1) // _O_WRONLY
		if wfd < 0 {
			return error('failed to wrap host control pipe write end')
		}

		self := os.executable()
		if self == '' {
			self = 'vxui'
		}
		arg := '${u64(read_h)}'
		cmdline := to_wide('${self} --vxui-host ${arg}')
		mut si := STARTUPINFOW{ cb: u32(sizeof(STARTUPINFOW)) }
		mut pi := PROCESS_INFORMATION{}
		ok := C.CreateProcessW(unsafe { nil }, cmdline, unsafe { nil }, unsafe { nil },
			BOOL(1), DWORD(0), unsafe { nil }, unsafe { nil }, voidptr(&si), voidptr(&pi))
		wide_free(cmdline)
		if ok == 0 {
			C._close(wfd)
			return error('failed to launch host process')
		}
		// The read HANDLE was inherited by the child; close our copy.
		C.CloseHandle(read_h)
		C.CloseHandle(pi.h_thread)
		C.CloseHandle(pi.h_process)

		return finish_embedded_spawn(int(pi.dw_process_id), wfd, HostHandshake{
			url:    url
			token:  cfg.token
			width:  cfg.width
			height: cfg.height
			x:      cfg.x
			y:      cfg.y
			title:  cfg.title
		})
	}

	// host_run is executed inside the --vxui-host child: it reads the handshake,
	// builds one WebView2 window, loads the page, and runs the message loop until
	// the window is destroyed.
	fn host_run(ctl_fd int) {
		hs := read_host_handshake(ctl_fd)
		if hs.url == '' {
			return
		}
		url_w := to_wide(hs.url)
		ctx := unsafe { &Wv2Ctx(C.malloc(sizeof(Wv2Ctx))) }
		ctx.hwnd = unsafe { nil }
		ctx.env = unsafe { nil }
		ctx.controller = unsafe { nil }
		ctx.core = unsafe { nil }
		ctx.url = url_w

		hwnd := wv2_create_host_window(hs.title, hs.width, hs.height)
		ctx.hwnd = hwnd
		eprintln('vxui host: window opened')
		// Store ctl_fd on the window so the pipe reader can target this window.
		C.SetWindowLongPtrW(hwnd, gwlp_userdata, isize(ctl_fd))
		ctx.done_event = C.CreateEventW(unsafe { nil }, 1, 0, unsafe { nil })

		env_handler := make_env_completed_handler(voidptr(ctx))
		user_data := to_wide(os.join_path(os.temp_dir(), 'vxui_webview2'))
		os.mkdir_all(os.temp_dir()) or {}

		hr := C.CreateCoreWebView2EnvironmentWithOptions(unsafe { nil }, user_data, unsafe { nil },
			env_handler)
		wide_free(user_data)
		if hr != 0 {
			C.free(url_w)
			return
		}

		res := C.WaitForSingleObject(ctx.done_event, 15000)
		if res != 0 {
			C.free(url_w)
			return
		}
		C.free(ctx.done_event)

		// Forward control commands onto the UI thread via PostMessage.
		spawn fn [ctl_fd, hwnd] () {
			host_read_control(ctl_fd, hwnd)
		}()

		wv2_message_loop()
		C.free(url_w)
	}

	fn host_read_control(fd int, hwnd HWND) {
		host_read_lines(fd, voidptr(hwnd), apply_host_control_line)
	}

	fn apply_host_control_line(line string, ctx voidptr) {
		hwnd := HWND(ctx)
		mut j := unsafe { &Wv2CmdJob(C.malloc(sizeof(Wv2CmdJob))) }
		ctrl := json2.decode[HostControl](line) or {
			C.free(j)
			return
		}
		j.w = ctrl.width
		j.h = ctrl.height
		j.x = ctrl.x
		j.y = ctrl.y
		j.title = unsafe { nil }
		match ctrl.cmd {
			'resize' { j.code = 0 }
			'move' { j.code = 1 }
			'title' { j.code = 2; j.title = to_wide(ctrl.title) }
			'close' { j.code = 3 }
			else { j.code = -1 }
		}
		C.PostMessageW(hwnd, wm_user_cmd, voidptr(0), voidptr(j))
	}
}
