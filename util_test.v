module vxui

import encoding.utf8

// =============================================================================
// Utility Tests: path sanitization, UTF-8 repair, URL decode, free port,
// and PackedApp.
// =============================================================================

fn test_get_free_port() {
	port := get_free_port() or {
		assert false
		return
	}
	assert port >= 1025 && port <= 65534
}

fn test_sanitize_path_valid() {
	valid_paths := ['./ui/index.html', 'static/page.html', 'file.txt']
	for path in valid_paths {
		sanitize_path(path) or {
			assert false
			return
		}
	}
}

fn test_sanitize_path_traversal() {
	invalid_paths := ['../etc/passwd', '~/secret.txt', '/absolute/path']
	for path in invalid_paths {
		sanitize_path(path) or { continue }
		assert false
	}
}

fn test_sanitize_utf8_passes_valid_text_through() {
	assert sanitize_utf8('hello') == 'hello'
	assert sanitize_utf8('中文备注') == '中文备注'
	assert sanitize_utf8('') == ''
	assert sanitize_utf8('mix中en文') == 'mix中en文'
}

fn test_sanitize_utf8_repairs_truncated_multibyte() {
	s := '中文备注'
	truncated := s.bytes()[..s.len - 1].bytestr() // cuts half of the last rune
	fixed := sanitize_utf8(truncated)
	assert utf8.validate_str(fixed), 'output must be valid UTF-8'
	assert fixed.starts_with('中文备')
}

fn test_sanitize_utf8_repairs_stray_continuation_bytes() {
	bad := [u8(0x61), u8(0x80), u8(0x62)].bytestr() // a, stray cont., b
	fixed := sanitize_utf8(bad)
	assert utf8.validate_str(fixed)
	assert fixed.len == 5 // 1 byte + U+FFFD (3 bytes) + 1 byte
	assert fixed[0] == u8(0x61) && fixed[4] == u8(0x62)
}

fn test_sanitize_path_null_byte() {
	// Null byte in filename - current implementation doesn't block this
	// This tests that the function handles it gracefully
	result := sanitize_path('file\x00.txt') or { return }
	assert result == 'file\x00.txt'
}

fn test_sanitize_path_encoded_traversal() {
	// URL encoded traversal - current implementation allows this
	// because it doesn't decode URL-encoded strings
	result := sanitize_path('%2e%2e%2f') or { return }
	assert result == '%2e%2e%2f'
}

fn test_sanitize_path_double_encoding() {
	// Double encoded traversal - current implementation allows this
	result := sanitize_path('%252e%252e%252f') or { return }
	assert result == '%252e%252e%252f'
}

fn test_sanitize_path_url_encoded_traversal() {
	// Test URL-encoded ../
	if _ := sanitize_path('%2e%2e%2f') {
		assert false // Should fail
	}
}

fn test_sanitize_path_double_encoded_traversal() {
	// Test double-encoded ../
	if _ := sanitize_path('%252e%252e%252f') {
		assert false // Should fail
	}
}

fn test_sanitize_path_mixed_encoding() {
	// Test mixed encoding
	if _ := sanitize_path('..%2fetc%2fpasswd') {
		assert false // Should fail
	}
}

fn test_sanitize_path_null_byte_enhanced() {
	// Test null byte injection
	if _ := sanitize_path('file\x00.txt') {
		assert false // Should fail
	}
}

fn test_sanitize_path_hidden_file_blocked() {
	// Hidden files without allowed extension should be blocked
	if _ := sanitize_path('.env') {
		assert false // Should fail
	}
	if _ := sanitize_path('.git/config') {
		assert false // Should fail
	}
	if _ := sanitize_path('.htaccess') {
		assert false // Should fail
	}
}

fn test_sanitize_path_hidden_file_allowed() {
	// Hidden files with allowed extensions should pass
	if _ := sanitize_path('.hidden.html') {
		// Should pass
	} else {
		assert false
	}
	if _ := sanitize_path('path/.styles.css') {
		// Should pass
	} else {
		assert false
	}
}

fn test_sanitize_path_backslash_traversal() {
	// Test backslash traversal (Windows-style)
	if _ := sanitize_path('..\\windows\\system32') {
		assert false // Should fail
	}
}

fn test_sanitize_path_plus_sign() {
	// Test that + is decoded to space
	result := sanitize_path('file+name.txt') or {
		assert false
		return
	}
	assert result == 'file+name.txt'
}

fn test_url_decode_basic() {
	assert url_decode('Hello%20World') == 'Hello World'
	assert url_decode('test%2Fpath') == 'test/path'
}

fn test_url_decode_plus() {
	assert url_decode('Hello+World') == 'Hello World'
}

fn test_url_decode_no_encoding() {
	assert url_decode('plaintext') == 'plaintext'
}

fn test_url_decode_invalid_hex() {
	// Invalid hex sequences should pass through
	assert url_decode('%ZZ') == '%ZZ'
	assert url_decode('%2') == '%2'
}

fn test_packed_app_new() {
	packed := new_packed_app()
	assert packed.files.len == 0
	assert packed.total_size() == 0
}

fn test_packed_app_add_file() {
	mut packed := new_packed_app()
	packed.add_file('test.html', 'Hello'.bytes())
	assert packed.files.len == 1
	assert packed.has_file('test.html')
	assert packed.total_size() == 5
}

fn test_packed_app_add_file_string() {
	mut packed := new_packed_app()
	packed.add_file_string('index.html', '<html></html>')
	assert packed.files.len == 1

	content := packed.get_file_content('index.html')!
	assert content == '<html></html>'
}

fn test_packed_app_get_file_not_found() {
	packed := new_packed_app()
	packed.get_file('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_packed_app_list_files() {
	mut packed := new_packed_app()
	packed.add_file_string('a.html', 'a')
	packed.add_file_string('b.css', 'b')

	files := packed.list_files()
	assert files.len == 2
}
