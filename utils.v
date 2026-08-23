module vxui

import rand
import net
import net.urllib
import encoding.utf8

// sanitize_utf8 returns `s` with every invalid UTF-8 byte replaced by the
// Unicode replacement character (U+FFFD). The websocket layer REJECTS text
// frames that are not valid UTF-8, so any payload built from byte-wise
// slicing of multibyte strings must be passed through this helper before
// being returned from a route handler.
pub fn sanitize_utf8(s string) string {
	if utf8.validate_str(s) {
		return s
	}
	replacement := [u8(0xEF), u8(0xBF), u8(0xBD)] // U+FFFD
	mut out := []u8{cap: s.len + replacement.len}
	mut i := 0
	for i < s.len {
		b := s[i]
		seq_len := match true {
			b < 0x80 { 1 } // ASCII
			b >= 0xC2 && b <= 0xDF { 2 }
			b >= 0xE0 && b <= 0xEF { 3 }
			b >= 0xF0 && b <= 0xF4 { 4 }
			else { 0 } // continuation byte out of place or invalid lead
		}
		valid := seq_len > 0 && i + seq_len <= s.len && utf8.validate_str(s[i..i + seq_len])
		if valid {
			out << s[i..i + seq_len].bytes()
			i += seq_len
		} else {
			out << replacement
			i++
		}
	}
	return out.bytestr()
}

// log_write_failure records a failed text-frame write with routing context
// and a hex prefix, so non-UTF-8 or oversized payloads show up as a
// diagnosable error instead of a mysterious disconnect.
fn (ctx &Context) log_write_failure(path string, rpc_id i64, payload string, err IError) {
	n := if payload.len > 32 { 32 } else { payload.len }
	hex_preview := payload.bytes()[..n].hex()
	ctx.logger.error('WebSocket write failed for path=${path} rpcID=${rpc_id}: ${err} payload_hex[0..${n}]=${hex_preview}')
}

// url_decode decodes URL-encoded strings ('+' becomes space).
// Invalid escape sequences are left untouched, matching lenient browser behaviour.
fn url_decode(s string) string {
	return urllib.query_unescape(s) or { s }
}

// sanitize_path validates and sanitizes the file path
// Handles both plain and URL-encoded path traversal attempts
pub fn sanitize_path(path string) !string {
	// Decode URL-encoded characters (handle multiple levels of encoding)
	mut decoded := url_decode(path)
	// Double decoding for doubly-encoded attacks
	decoded2 := url_decode(decoded)

	// Check for path traversal attempts in original, decoded, and double-decoded forms
	for check_path in [path, decoded, decoded2] {
		// Check for dangerous patterns
		if check_path.contains('..') || check_path.contains('~') {
			return new_error_detail_with_details(VxuiError.path_traversal,
				'Path traversal detected', {
				'path': path
			})
		}
	}

	// Check for encoded traversal patterns
	lower_path := path.to_lower()
	encoded_patterns := ['%2e%2e', '%252e%252e', '..%2f', '..%5c', '%2e%2e%2f', '%2e%2e%5c']
	for pattern in encoded_patterns {
		if lower_path.contains(pattern) {
			return new_error_detail_with_details(VxuiError.path_traversal,
				'Encoded path traversal detected', {
				'path':    path
				'pattern': pattern
			})
		}
	}

	// Ensure path is relative (not absolute)
	for check_path in [path, decoded] {
		if check_path.starts_with('/') {
			return new_error_detail_with_details(VxuiError.absolute_path_not_allowed,
				'Absolute paths not allowed', {
				'path': path
			})
		}
	}

	// Prevent null byte injection
	if path.contains('\x00') || decoded.contains('\x00') {
		return new_error_detail_with_details(VxuiError.null_byte_detected,
			'Null byte detected in path', {
			'path': path
		})
	}

	// Prevent access to sensitive hidden files
	path_parts := decoded.split('/')
	for part in path_parts {
		// Block hidden files (except . for current directory reference)
		if part.starts_with('.') && part != '.' && part.len > 1 {
			// Allow .html, .css, .js etc but block .env, .git, .htaccess
			allowed_extensions := ['.html', '.htm', '.css', '.js', '.json', '.png', '.jpg', '.jpeg',
				'.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot']
			mut is_allowed := false
			for ext in allowed_extensions {
				if part.to_lower().ends_with(ext) {
					is_allowed = true
					break
				}
			}
			if !is_allowed {
				return new_error_detail_with_details(VxuiError.hidden_file_access,
					'Hidden file access not allowed', {
					'path': path
					'file': part
				})
			}
		}
	}

	return path
}

// get_free_port try to get a free port to websocket listen to
pub fn get_free_port() !u16 {
	mut attempts := 0
	max_attempts := 100
	for attempts < max_attempts {
		// we don't need to be root to access this ports
		port := rand.u32_in_range(1025, 65534)!
		if mut server := net.listen_tcp(.ip, 'localhost:${port}') {
			server.close()!
			return u16(port)
		}
		attempts++
	}
	return new_error_detail_with_details(VxuiError.port_not_available,
		'Failed to find a free port', {
		'attempts': max_attempts.str()
	})
}

// escape_html escapes special HTML characters to prevent XSS attacks
// Use this when outputting user-generated content in HTML
pub fn escape_html(input string) string {
	return input.replace_each([
		'&',
		'&amp;',
		'<',
		'&lt;',
		'>',
		'&gt;',
		'"',
		'&quot;',
		"'",
		'&#x27;',
	])
}

// escape_js escapes JavaScript special characters
// Use this when outputting data in JavaScript contexts
pub fn escape_js(input string) string {
	return input.replace_each([
		'\\',
		'\\\\',
		'"',
		'\\"',
		"'",
		"\\'",
		'\n',
		'\\n',
		'\r',
		'\\r',
		'\t',
		'\\t',
	])
}

// escape_attr escapes HTML attribute values
pub fn escape_attr(input string) string {
	return input.replace_each([
		'&',
		'&amp;',
		'"',
		'&quot;',
		"'",
		'&#x27;',
	])
}

// is_valid_email validates email format (basic check)
pub fn is_valid_email(email string) bool {
	if email.len < 5 || !email.contains('@') || !email.contains('.') {
		return false
	}
	parts := email.split('@')
	if parts.len != 2 || parts[0].len == 0 || parts[1].len < 3 {
		return false
	}
	domain_parts := parts[1].split('.')
	return domain_parts.len >= 2 && domain_parts[0].len > 0 && domain_parts[1].len > 0
}

// truncate_string truncates a string to max length with ellipsis
pub fn truncate_string(s string, max_len int) string {
	if s.len <= max_len {
		return s
	}
	if max_len <= 3 {
		return s[..max_len]
	}
	return s[..max_len - 3] + '...'
}

// generate_id generates a unique ID string
pub fn generate_id() string {
	return rand.hex(16)
}
