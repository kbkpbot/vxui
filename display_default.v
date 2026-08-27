module vxui

// Platform guard: active only where no dedicated display_<os>.v variant exists
// (macOS / Android today). Belt-and-suspenders: V applies filename filtering in
// directory builds but NOT when a module is imported from .vmodules, so the
// compile-time conditions guarantee exactly one variant defines the symbols.
$if linux {
} $else $if windows {
} $else {
	// Fallback implementation of the embedded (native WebView) display family for
	// platforms without a native variant.
	//
	// V's platform-dependent file mechanism guarantees exactly ONE variant of this
	// family compiles per platform:
	//   display_windows.v -> WebView2          (Windows)
	//   display_linux.v   -> WebKitGTK         (Linux)
	//   display_default.v -> this stub         (everything else: macOS, Android, ...)
	// so on those other platforms every embedded backend id reports a clear error
	// instead of failing to link.
	//
	// Adding a new platform = dropping in a sibling file that provides the same
	// hook contract (embedded_native_id / embedded_spawn / embedded_session_*):
	//   - display_macos.v   : WKWebView via Objective-C runtime FFI
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

	fn embedded_session_close(_s &WebViewSession) {}

	fn embedded_session_wait_closed(_s &WebViewSession) {}

	fn embedded_session_set_size(_s &WebViewSession, _w int, _h int) {}

	fn embedded_session_set_title(_s &WebViewSession, _t string) {}

	fn embedded_session_set_position(_s &WebViewSession, _x int, _y int) {}
}
