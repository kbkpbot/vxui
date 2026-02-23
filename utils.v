module vxui

import rand
import net

// sanitize_path validates and sanitizes the file path
pub fn sanitize_path(path string) !string {
	// Check for path traversal attempts
	if path.contains('..') || path.contains('~') {
		return error('Invalid path: path traversal detected')
	}
	// Ensure path starts with ./ or is a relative path
	if path.starts_with('/') {
		return error('Invalid path: absolute paths not allowed')
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
