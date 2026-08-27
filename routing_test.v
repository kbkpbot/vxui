module vxui

import x.json2

// =============================================================================
// Routing & Request Tests
// =============================================================================

fn test_verb_enum() {
	assert int(Verb.any_verb) == 0
	assert int(Verb.get) == 1
	assert int(Verb.post) == 2
	assert int(Verb.put) == 3
	assert int(Verb.delete) == 4
	assert int(Verb.patch) == 5
}

fn test_request_struct() {
	req := Request{
		verb:      Verb.post
		path:      '/api/test'
		client_id: 'client-1'
	}
	assert req.verb == Verb.post
	assert req.path == '/api/test'
	assert req.client_id == 'client-1'
}

fn test_response_struct() {
	mut resp := Response{
		status: 200
		body:   '{"result": "ok"}'
	}
	assert resp.status == 200
	assert resp.body == '{"result": "ok"}'

	resp.status = 404
	assert resp.status == 404
}

fn test_response_default_status() {
	resp := Response{}
	assert resp.status == 200
}

fn test_verb_strings_map() {
	assert 'get' in verb_strings
	assert 'post' in verb_strings
	assert 'put' in verb_strings
	assert 'delete' in verb_strings
	assert 'patch' in verb_strings

	assert verb_strings['get'] == Verb.get
	assert verb_strings['post'] == Verb.post
}

fn test_route_struct() {
	route := Route{
		verb: [Verb.get, Verb.post]
		path: '/api/test'
	}
	assert route.path == '/api/test'
	assert route.verb.len == 2
	assert Verb.get in route.verb
}

fn test_generate_routes_registers_only_tagged_methods() {
	mut app := RoutingTestApp{}
	routes := generate_routes(app)!
	assert 'tagged_handler' in routes
	assert routes['tagged_handler'].path == '/tagged'
	// untagged methods are not registered, neither by fn name nor path alias
	assert 'untagged_handler' !in routes
	assert '/untagged_handler' !in routes
	assert 'track_call' !in routes
}

fn test_fire_call_rejects_untagged_method() {
	mut app := RoutingTestApp{}
	result := fire_call(mut app, 'tagged_handler', {})!
	assert result == 'tagged-ok'
	// untagged methods are unreachable through dispatch
	res := fire_call(mut app, 'untagged_handler', {}) or {
		assert err.code() == int(VxuiError.route_not_found)
		'blocked'
	}
	assert res == 'blocked'
}

fn test_generate_routes_rejects_tagged_non_string_method() {
	mut app := BadReturnApp{}
	generate_routes(app) or {
		assert '${err}'.contains('return string'), 'unexpected error: ${err}'
		return
	}
	assert false, 'tagged method returning non-string must be rejected at startup'
}

fn test_parse_attrs_empty() {
	verbs, path := parse_attrs('test', []) or {
		assert false
		return
	}
	assert path == '/test'
	assert verbs.len == 1
	assert Verb.any_verb in verbs
}

fn test_parse_attrs_with_path() {
	verbs, path := parse_attrs('test', ['/custom']) or {
		assert false
		return
	}
	assert path == '/custom'
}

fn test_parse_attrs_with_verb() {
	verbs, path := parse_attrs('test', ['get', 'post']) or {
		assert false
		return
	}
	assert verbs.len == 2
	assert Verb.get in verbs
	assert Verb.post in verbs
}

fn test_parse_attrs_duplicate_path() {
	parse_attrs('test', ['/path1', '/path2']) or { return }
	assert false
}

fn test_parse_attrs_invalid_verb() {
	parse_attrs('test', ['invalid_verb']) or { return }
	assert false
}

fn test_parse_attrs_combined_verb_and_path() {
	verbs, path := parse_attrs('test', ['get', '/api/users']) or {
		assert false
		return
	}
	assert path == '/api/users'
	assert verbs.len == 1
	assert Verb.get in verbs
}

fn test_parse_attrs_multiple_verbs() {
	verbs, path := parse_attrs('api', ['get', 'post', 'put']) or {
		assert false
		return
	}
	assert verbs.len == 3
	assert Verb.get in verbs
	assert Verb.post in verbs
	assert Verb.put in verbs
	assert path == '/api'
}

fn test_parse_attrs_all_http_verbs() {
	for verb_name in ['get', 'post', 'put', 'delete', 'patch'] {
		verbs, _ := parse_attrs('test', [verb_name]) or {
			assert false
			return
		}
		assert verbs.len == 1
	}
}

fn test_parse_attrs_case_insensitive_verb() {
	verbs, _ := parse_attrs('test', ['GET', 'Post', 'PUT']) or {
		assert false
		return
	}
	assert verbs.len == 3
}

fn test_parse_attrs_path_normalization() {
	verbs, path := parse_attrs('MyHandler', ['/MyPath']) or {
		assert false
		return
	}
	assert path == '/mypath' // lowercase
}

fn test_build_request_defaults() {
	message := map[string]json2.Any{}
	req := build_request(message, 'client-1')

	assert req.verb == Verb.get
	assert req.path == '/'
	assert req.client_id == 'client-1'
}

fn test_build_request_with_verb() {
	mut message := map[string]json2.Any{}
	message['verb'] = json2.Any('POST')
	req := build_request(message, 'client-1')

	assert req.verb == Verb.post
}

fn test_build_request_with_path() {
	mut message := map[string]json2.Any{}
	message['path'] = json2.Any('/api/users')
	req := build_request(message, 'client-1')

	assert req.path == '/api/users'
}
