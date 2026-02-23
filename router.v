module vxui

import x.json2

// Verb represents HTTP methods
pub enum Verb {
	any_verb
	get
	post
	put
	delete
	patch
}

// verb_strings maps string to Verb enum
const verb_strings = {
	'get':    Verb.get
	'post':   .post
	'put':    .put
	'delete': .delete
	'patch':  .patch
}

// Route represents a registered route
pub struct Route {
	verb []Verb
	path string
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
				return error("[${name}]:Can't assign multiply path for a route.")
			} else {
				path = x
			}
		} else {
			if x.to_lower() in verb_strings.keys() {
				verbs << verb_strings[x.to_lower()]
			} else {
				return error('[${name}]:Unknown verb: ${x}')
			}
		}
	}
	if verbs.len == 0 {
		verbs << Verb.any_verb
	}
	// Use default path if not specified
	if path == '' {
		path = '/${name}'
	}
	// Make path lowercase for case-insensitive comparisons
	return verbs, path.to_lower()
}

// generate_routes generates route structs for an app
pub fn generate_routes[T](app &T) !map[string]Route {
	// Parsing methods attributes
	mut routes := map[string]Route{}
	$for method in T.methods {
		verbs, route_path := parse_attrs(method.name, method.attrs) or {
			return error('error parsing method attributes: ${err}')
		}

		routes[method.name] = Route{
			verb: verbs
			path: route_path
		}
	}
	return routes
}

// handle_message checks routes and calls the handler
pub fn handle_message[T](mut app T, message map[string]json2.Any) !string {
	mut tmp := message['path'] or { json2.Null{} }
	mut path := ''
	if tmp is json2.Null {
		return error("Can't parse path [null]")
	} else {
		path = tmp.str()
	}
	if !path.starts_with('/') {
		return error("Can't parse path [${path}]")
	}

	tmp = message['verb'] or { json2.Null{} }
	mut verb_str := ''
	mut verb := Verb.get
	if tmp is json2.Null {
		return error("Can't parse verb [null]")
	} else {
		verb_str = tmp.str().to_lower()
	}
	if verb_str !in verb_strings.keys() {
		return error('Unknown verb [${verb}]')
	} else {
		verb = verb_strings[verb_str]
	}

	for key, val in app.routes {
		if val.path == path && (verb in val.verb || Verb.any_verb in val.verb) {
			return fire_call[T](mut app, key, message)
		}
	}
	return error('No handler for message ${path} ${verb}')
}

// fire_call calls the method
pub fn fire_call[T](mut app T, method_name string, message map[string]json2.Any) !string {
	$for method in T.methods {
		if method.name == method_name {
			$if method.return_type is string {
				return app.$method(message)
			} $else {
				return error('[${method_name}] should return string.(${method.return_type})')
			}
		}
	}
	return error("Can't find method [${method_name}]")
}
