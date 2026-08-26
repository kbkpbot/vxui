module vxui

import x.json2

// =============================================================================
// Request/Response - Type-Safe Message Handling
// =============================================================================

// Verb represents HTTP methods
pub enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}

// Request represents a type-safe request
pub struct Request {
pub:
	verb        Verb
	path        string
	client_id   string
	raw_message map[string]json2.Any // Original message for compatibility
}

// Response represents a type-safe response
pub struct Response {
pub mut:
	status int = 200
	body   string
}

// Route represents a registered route
pub struct Route {
	verb []Verb
	path string
}

// build_request creates a type-safe Request from raw message
fn build_request(message map[string]json2.Any, client_id string) Request {
	mut verb := Verb.get
	if v := message['verb'] {
		verb_str := v.str().to_lower()
		if verb_str in verb_strings {
			verb = verb_strings[verb_str]
		}
	}

	mut path := '/'
	if p := message['path'] {
		path = p.str()
	}

	return Request{
		verb:        verb
		path:        path
		client_id:   client_id
		raw_message: message
	}
}

// handle_request processes a request through routes
fn handle_request[T](mut app T, ctx &Context, req Request, message map[string]json2.Any) !Response {
	for key, val in ctx.routes {
		if val.path == req.path && (req.verb in val.verb || Verb.any_verb in val.verb) {
			result := fire_call[T](mut app, key, message) or {
				mut err_m := map[string]json2.Any{}
				err_m['error'] = json2.Any('${err}')
				return Response{
					status: 500
					body:   json2.encode(err_m)
				}
			}
			return Response{
				status: 200
				body:   result
			}
		}
	}
	return Response{
		status: 404
		body:   '{"error": "Route not found"}'
	}
}

// fire_call calls the method
// Only methods carrying route attributes (@['/path'] and/or a verb) are
// dispatchable; untagged helper methods are invisible to routing.
//
// NOTE on V comptime limits (tested on V 0.5.2 / 9142d68): the dispatch call
// below is instantiated ONCE FOR EVERY string-returning method of T,
// regardless of attributes — runtime `if` guards do not gate comptime
// instantiation, `$for attr in method.attributes` nesting parses but does
// not gate it either, and `continue` is illegal inside `$for`. Helpers on
// the app struct must therefore return void/non-string types (or take no
// parameters): a string-returning helper with custom parameters will not
// compile. generate_routes fails fast when a TAGGED method has the wrong
// return type, which keeps this constraint discoverable at startup.
pub fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
	$for method in T.methods {
		if method.attrs.len > 0 && method.name == method_name {
			$if method.return_type is string {
				return app.$method(message)
			}
			// Method found but doesn't return string - compile time error would be better
			// but we handle it gracefully at runtime
			return error('Method ${method_name} must return string')
		}
	}
	return new_error_detail_with_details(VxuiError.route_not_found, 'Method not found', {
		'method': method_name
	})
}

// parse_attrs parses function attributes for verbs and path
pub fn parse_attrs(name string, attrs []string) !([]Verb, string) {
	if attrs.len == 0 {
		return [Verb.any_verb], '/${name}'
	}

	mut verbs := []Verb{}
	mut path := ''

	for x in attrs {
		if x.starts_with('/') {
			if path != '' {
				return new_error_detail_with_details(VxuiError.route_not_found,
					'Cannot assign multiple paths to a route', {
					'function': name
				})
			} else {
				path = x
			}
		} else {
			if x.to_lower() in verb_strings.keys() {
				verbs << verb_strings[x.to_lower()]
			} else {
				return new_error_detail_with_details(VxuiError.invalid_method, 'Unknown verb', {
					'function': name
					'verb':     x
				})
			}
		}
	}
	if verbs.len == 0 {
		verbs << Verb.any_verb
	}
	if path == '' {
		path = '/${name}'
	}
	return verbs, path.to_lower()
}

// generate_routes generates route structs for an app
pub fn generate_routes[T](app &T) !map[string]Route {
	mut routes := map[string]Route{}
	$for method in T.methods {
		$if method.return_type is string {
			// Only attribute-tagged methods become routes; untagged methods
			// are plain helpers and must not be reachable from the frontend.
			if method.attrs.len > 0 {
				verbs, route_path := parse_attrs(method.name, method.attrs) or {
					return new_error_detail_with_cause(VxuiError.attribute_parse_error,
						'Error parsing method attributes', err)
				}
				routes[method.name] = Route{
					verb: verbs
					path: route_path
				}
			}
		} $else {
			// Tagged methods are dispatched with (mut app, message) and MUST
			// return string; anything else tagged is a configuration mistake
			// worth failing fast on (mirrors veb's route validation).
			if method.attrs.len > 0 {
				return new_error_detail_with_details(VxuiError.attribute_parse_error,
					'method `${method.name}` has route attributes but must return string', {
					'method':      method.name
					'return_type': '${method.return_type}'
				})
			}
		}
	}
	return routes
}
