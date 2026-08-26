module vxui

// =============================================================================
// Error Types - Structured Error Handling
// =============================================================================

// VxuiError represents error codes
pub enum VxuiError {
	unknown
	client_not_found
	no_clients
	no_valid_connection
	js_timeout
	js_validation_failed
	js_result_too_large
	auth_failed
	auth_invalid_token
	port_not_available
	browser_not_found
	file_not_found
	path_traversal
	route_not_found
	// Additional error codes for unified error handling
	profile_create_failed
	process_fork_failed
	hidden_file_access
	null_byte_detected
	absolute_path_not_allowed
	invalid_method
	attribute_parse_error
}

// VxuiErrorDetail represents a structured error with code and details
pub struct VxuiErrorDetail {
pub:
	code    VxuiError
	message string
	details map[string]string
	cause   ?IError // Underlying error that caused this error
}

// msg returns the error message (implements IError interface)
pub fn (e VxuiErrorDetail) msg() string {
	mut result := e.message
	if cause := e.cause {
		result += ': ${cause.msg()}'
	}
	return result
}

// code returns the error code (implements IError interface)
pub fn (e VxuiErrorDetail) code() int {
	return int(e.code)
}

// str returns the error message
pub fn (e VxuiErrorDetail) str() string {
	return e.msg()
}

// with_cause creates a new error with an underlying cause
pub fn (e VxuiErrorDetail) with_cause(cause IError) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    e.code
		message: e.message
		details: e.details
		cause:   cause
	}
}

// with_detail adds a detail to the error
pub fn (e VxuiErrorDetail) with_detail(key string, value string) VxuiErrorDetail {
	mut new_details := e.details.clone()
	new_details[key] = value
	return VxuiErrorDetail{
		code:    e.code
		message: e.message
		details: new_details
		cause:   e.cause
	}
}

// new_error_detail creates a new VxuiErrorDetail
pub fn new_error_detail(code VxuiError, message string) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: {}
	}
}

// new_error_detail_with_details creates a new VxuiErrorDetail with details
pub fn new_error_detail_with_details(code VxuiError, message string, details map[string]string) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: details
	}
}

// new_error_detail_with_cause creates a new VxuiErrorDetail with an underlying cause
pub fn new_error_detail_with_cause(code VxuiError, message string, cause IError) VxuiErrorDetail {
	return VxuiErrorDetail{
		code:    code
		message: message
		details: {}
		cause:   cause
	}
}
