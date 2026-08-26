module vxui

import x.json2

// =============================================================================
// Event System - Lifecycle Hooks
// =============================================================================

// EventType represents different lifecycle events
pub enum EventType {
	before_start
	after_start
	client_connecting
	client_connected
	client_disconnected
	before_shutdown
	error
	js_execution
	before_request
	after_request
}

// EventData contains event information
pub struct EventData {
pub:
	event_type EventType
	client_id  string
	message    string
	data       map[string]json2.Any
	request    ?Request
	response   ?Response
	err        ?VxuiErrorDetail
}

// EventHandler is a callback function type for events
pub type EventHandler = fn (EventData)

// trigger_event fires an event to all registered handlers
fn (mut ctx Context) trigger_event(event_type EventType, client_id string, message string, data map[string]json2.Any, request ?Request, response ?Response, err ?VxuiErrorDetail) {
	event := EventData{
		event_type: event_type
		client_id:  client_id
		message:    message
		data:       data
		request:    request
		response:   response
		err:        err
	}

	// NOTE: deliberately NOT `if handlers := m[key]` — that or-init form
	// silently skipped existing array values in this V build (0.5.2).
	mut handlers := []EventHandler{}
	if event_type in ctx.event_handlers {
		handlers = ctx.event_handlers[event_type]
	}
	for handler in handlers {
		handler(event)
	}
}

// on_event registers an event handler
pub fn (mut ctx Context) on_event(event_type EventType, handler EventHandler) {
	if ctx.event_handlers.len == 0 {
		// nil-map guard: handlers may be registered before init() runs
		ctx.event_handlers = map[EventType][]EventHandler{}
	}
	if event_type !in ctx.event_handlers {
		ctx.event_handlers[event_type] = []
	}
	ctx.event_handlers[event_type] << handler
}
