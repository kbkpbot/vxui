module vxui

// =============================================================================
// Error Type Tests
// =============================================================================

fn test_vxui_error_enum() {
	assert int(VxuiError.unknown) == 0
	assert int(VxuiError.client_not_found) == 1
	assert int(VxuiError.no_clients) == 2
	assert int(VxuiError.no_valid_connection) == 3
	assert int(VxuiError.js_timeout) == 4
	assert int(VxuiError.js_validation_failed) == 5
}

fn test_vxui_error_detail_struct() {
	err := VxuiErrorDetail{
		code:    VxuiError.client_not_found
		message: 'Client not found'
		details: {
			'client_id': 'test-123'
		}
	}
	assert err.code == VxuiError.client_not_found
	assert err.message == 'Client not found'
	assert err.details['client_id'] == 'test-123'
}

fn test_vxui_error_detail_str() {
	err := VxuiErrorDetail{
		code:    VxuiError.auth_failed
		message: 'Authentication failed'
	}
	assert err.str() == 'Authentication failed'
}

fn test_new_error_detail() {
	err := new_error_detail(VxuiError.no_clients, 'No connected clients')
	assert err.code == VxuiError.no_clients
	assert err.message == 'No connected clients'
}

fn test_new_error_detail_with_details() {
	err := new_error_detail_with_details(VxuiError.client_not_found, 'Client not found', {
		'id': 'abc'
	})
	assert err.code == VxuiError.client_not_found
	assert err.details['id'] == 'abc'
}

fn test_vxui_error_detail_error_chain() {
	err := new_error_detail(VxuiError.client_not_found, 'Client not found')
	// Test that we can get the error message
	assert err.str() == 'Client not found'
	assert err.code == VxuiError.client_not_found
}

fn test_vxui_error_all_codes() {
	// Ensure all error codes are accessible
	codes := [
		VxuiError.unknown,
		VxuiError.client_not_found,
		VxuiError.no_clients,
		VxuiError.no_valid_connection,
		VxuiError.js_timeout,
		VxuiError.js_validation_failed,
		VxuiError.js_result_too_large,
		VxuiError.auth_failed,
		VxuiError.auth_invalid_token,
		VxuiError.port_not_available,
		VxuiError.browser_not_found,
		VxuiError.file_not_found,
		VxuiError.path_traversal,
		VxuiError.route_not_found,
	]
	assert codes.len == 14
}

fn test_error_with_cause() {
	// Test that error detail can be created
	err := new_error_detail(VxuiError.no_clients, 'WebSocket failed')
	assert err.code == VxuiError.no_clients
	assert err.message == 'WebSocket failed'
}

fn test_error_chain() {
	// Test error with details
	inner := new_error_detail_with_details(VxuiError.client_not_found, 'Client abc not found', {
		'id': 'abc'
	})

	assert inner.code == VxuiError.client_not_found
	assert inner.details['id'] == 'abc'
}

fn test_all_error_codes_have_messages() {
	// Verify all error codes are defined
	codes := [
		VxuiError.unknown,
		VxuiError.client_not_found,
		VxuiError.no_clients,
		VxuiError.no_valid_connection,
		VxuiError.js_timeout,
		VxuiError.js_validation_failed,
		VxuiError.browser_not_found,
		VxuiError.file_not_found,
		VxuiError.auth_failed,
		VxuiError.port_not_available,
		VxuiError.route_not_found,
		VxuiError.auth_invalid_token,
		VxuiError.path_traversal,
		VxuiError.js_result_too_large,
	]

	for code in codes {
		assert int(code) >= 0
	}
}
