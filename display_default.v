module vxui

// Platform guard: active only where no dedicated display_<os>.v variant exists
// (Android today, plus any future platform). Belt-and-suspenders: V applies
// filename filtering in directory builds but NOT when a module is imported from
// .vmodules, so the compile-time conditions guarantee exactly one variant
// defines the symbols.
$if linux {
} $else $if windows {
} $else $if macos {
} $else $if android {
} $else {
	// Fallback implementation of the embedded (native WebView) display family for
	// platforms without a native variant.
	//
	// V's platform-dependent file mechanism guarantees exactly ONE variant of this
	// family compiles per platform:
	//   display_windows.v -> WebView2          (Windows)
	//   display_linux.v   -> WebKitGTK         (Linux)
	//   display_macos.v   -> WKWebView         (macOS)
	//   display_default.v -> this stub         (everything else: Android, ...)
	// so on those other platforms every embedded backend id reports a clear error
	// instead of failing to link.
	//
	// Adding a new platform = dropping in a sibling file that provides the same
	// hook contract (embedded_native_id / embedded_spawn / host_run):
	//   - display_android.v : android.webkit.WebView via JNI
	// No changes to display.v are required.

	// embedded_native_id reports the native WebView backend carried by this build
	// ('' = none; resolve_auto() then falls back to the platform browser).
	fn embedded_native_id() string {
		return ''
	}

	fn embedded_spawn(id string, _html_path string, _cfg DisplaySessionConfig) !DisplaySession {
		return error('native WebView FFI not implemented on this platform (${id})')
	}

	// host_run is the entry point for a native-browser child process (see
	// vxui.v's host_main). On platforms without a native variant it is never
	// reached - embedded_spawn above errors before forking a child.
	fn host_run(_ctl_fd int) {
		eprintln('vxui host: native WebView not supported on this platform')
	}
}
