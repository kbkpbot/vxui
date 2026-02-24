module vxui

import rand
import net

// url_decode decodes URL-encoded strings
fn url_decode(s string) string {
	mut result := []u8{}
	mut i := 0
	bytes := s.bytes()
	for i < bytes.len {
		if bytes[i] == `%` && i + 2 < bytes.len {
			// Try to parse hex
			mut hex := ''
			hex += bytes[i + 1].ascii_str()
			hex += bytes[i + 2].ascii_str()
			if val := hex_to_byte(hex) {
				result << val
				i += 3
				continue
			}
		}
		if bytes[i] == `+` {
			result << ` `
			i++
			continue
		}
		result << bytes[i]
		i++
	}
	return result.bytestr()
}

// hex_to_byte converts a 2-char hex string to a byte
fn hex_to_byte(hex string) ?u8 {
	if hex.len != 2 {
		return none
	}
	mut result := u8(0)
	for c in hex.to_lower().bytes() {
		result <<= 4
		if c >= u8(`0`) && c <= u8(`9`) {
			result |= c - u8(`0`)
		} else if c >= u8(`a`) && c <= u8(`f`) {
			result |= c - u8(`a`) + 10
		} else {
			return none
		}
	}
	return result
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
			return error('Invalid path: path traversal detected')
		}
	}
	
	// Check for encoded traversal patterns
	lower_path := path.to_lower()
	encoded_patterns := ['%2e%2e', '%252e%252e', '..%2f', '..%5c', '%2e%2e%2f', '%2e%2e%5c']
	for pattern in encoded_patterns {
		if lower_path.contains(pattern) {
			return error('Invalid path: path traversal detected')
		}
	}
	
	// Ensure path is relative (not absolute)
	for check_path in [path, decoded] {
		if check_path.starts_with('/') {
			return error('Invalid path: absolute paths not allowed')
		}
	}
	
	// Prevent null byte injection
	if path.contains('\x00') || decoded.contains('\x00') {
		return error('Invalid path: null byte detected')
	}
	
	// Prevent access to sensitive hidden files
	path_parts := decoded.split('/')
	for part in path_parts {
		// Block hidden files (except . for current directory reference)
		if part.starts_with('.') && part != '.' && part.len > 1 {
			// Allow .html, .css, .js etc but block .env, .git, .htaccess
			allowed_extensions := ['.html', '.htm', '.css', '.js', '.json', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot']
			mut is_allowed := false
			for ext in allowed_extensions {
				if part.to_lower().ends_with(ext) {
					is_allowed = true
					break
				}
			}
			if !is_allowed {
				return error('Invalid path: hidden files not allowed')
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
	return error('Failed to find a free port after ${max_attempts} attempts')
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