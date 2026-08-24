module main

import vxui
import os
import x.json2
import encoding.base64
import time
import sync

// FileInfo represents uploaded file metadata
struct FileInfo {
	name      string
	size      int
	size_str  string // formatted size string (precomputed for template)
	mimetype  string
	data      string // base64 encoded
	uploaded  string
}

// App inherits from vxui.Context
struct App {
	vxui.Context
mut:
	mu         sync.RwMutex
	files      []FileInfo
	upload_dir string
	// chunked uploads: filename -> accumulated base64 chunks, in order
	chunk_bufs map[string][]string
}

// init_upload_dir creates the upload directory
fn (mut app App) init_upload_dir() {
	app.upload_dir = os.join_path(os.temp_dir(), 'vxui_uploads_${time.now().unix()}')
	os.mkdir_all(app.upload_dir) or {}
}

// index serves the main page
@['/']
fn (mut app App) index(_ map[string]json2.Any) string {
	return app.render_file_list()
}

// upload handles file upload
@['/upload']
fn (mut app App) upload(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()

	// Get file data
	filename := params['filename'] or { json2.Null{} }.str()
	filedata := params['filedata'] or { json2.Null{} }.str()
	mimetype := params['mimetype'] or { json2.Any('application/octet-stream') }.str()

	if filename == '' || filedata == '' {
		return '<div id="message" class="error">No file selected</div>'
	}

	// Decode base64 data (remove data URL prefix if present)
	mut data := filedata
	if data.contains(',') {
		data = data.split(',')[1]
	}

	decoded := base64.decode_str(data)

	// Save to disk
	file_path := os.join_path(app.upload_dir, filename)
	os.write_file(file_path, decoded) or {
		return '<div id="message" class="error">Failed to save file: ${err.msg()}</div>'
	}

	// Store file info
	file_info := FileInfo{
		name:     filename
		size:     decoded.len
		size_str: format_size(decoded.len)
		mimetype: mimetype
		data:     data
		uploaded: time_now_str()
	}
	app.files << file_info

	return '<div id="message" class="success">File "${filename}" uploaded successfully!</div>' +
		app.render_file_list()
}

// upload_chunk handles ONE chunk of a chunked upload. The page slices files
// into 1MB pieces so no single WebSocket message blocks the connection read
// loop long enough to trip the protocol-level pong watchdog.
// The final chunk assembles the file and returns the standard
// message + out-of-band file-list response.
@['/upload-chunk']
fn (mut app App) upload_chunk(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	filename := params['filename'] or { json2.Null{} }.str()
	mimetype := params['mimetype'] or { json2.Any('application/octet-stream') }.str()
	index := params['index'] or { json2.Any(0) }.int()
	total := params['total'] or { json2.Any(1) }.int()
	chunk := params['chunk'] or { json2.Null{} }.str()

	if filename == '' || total < 1 || index < 0 || index >= total {
		return '<div id="message" class="error">Invalid chunk parameters</div>'
	}

	app.mu.lock()
	if index == 0 {
		app.chunk_bufs[filename] = []string{}
	}
	if filename !in app.chunk_bufs {
		app.mu.unlock()
		return '<div id="message" class="error">Upload restarted, chunk lost</div>'
	}
	// EVERY chunk arrives as a data URL ("data:...;base64,PAYLOAD") because
	// the page reads each slice with readAsDataURL — strip the prefix per
	// chunk. Stripping only the first chunk's prefix (or after joining)
	// would cut the stream at the second comma.
	mut piece := chunk
	if piece.contains(',') {
		piece = piece.split(',').last()
	}
	app.chunk_bufs[filename] << piece
	done := app.chunk_bufs[filename].len == total
	mut data := ''
	if done {
		data = app.chunk_bufs[filename].join('')
		app.chunk_bufs.delete(filename)
	}
	app.mu.unlock()

	if !done {
		// intermediate chunk: the page tracks progress via rpc() and does
		// not render anything for this response
		return ''
	}

	decoded := base64.decode_str(data)

	file_path := os.join_path(app.upload_dir, filename)
	os.write_file(file_path, decoded) or {
		return '<div id="message" class="error">Failed to save file: ${err.msg()}</div>'
	}

	app.mu.lock()
	app.files << FileInfo{
		name:     filename
		size:     decoded.len
		size_str: format_size(decoded.len)
		mimetype: mimetype
		uploaded: time_now_str()
	}
	app.mu.unlock()

	return '<div id="message" class="success">File "${filename}" uploaded successfully!</div>' +
		app.render_file_list()
}

// delete removes a file
@['/delete']
fn (mut app App) delete(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	filename := params['filename'] or { json2.Null{} }.str()

	// Remove from list
	mut new_files := []FileInfo{}
	for file in app.files {
		if file.name != filename {
			new_files << file
		}
	}
	app.files = new_files

	// Delete from disk
	file_path := os.join_path(app.upload_dir, filename)
	os.rm(file_path) or {}

	return '<div id="message" class="success">File "${filename}" deleted</div>' +
		app.render_file_list()
}

// download triggers a file download
@['/download']
fn (mut app App) download(message map[string]json2.Any) string {
	params := message['parameters'] or { json2.Null{} }.as_map()
	filename := params['filename'] or { json2.Null{} }.str()

	for file in app.files {
		if file.name == filename {
			// Return a special response that triggers download via JS
			return '<script>
				// Trigger download
				(function() {
					var link = document.createElement("a");
					link.href = "data:${file.mimetype};base64,${file.data}";
					link.download = "${file.name}";
					link.click();
				})();
			</script>'
		}
	}

	return '<div id="message" class="error">File not found</div>'
}

// render_file_list generates the HTML for the file list using $tmpl
fn (mut app App) render_file_list() string {
	// Calculate total size for template
	mut total_size := 0
	for file in app.files {
		total_size += file.size
	}
	total_size_str := format_size(total_size)
	return $tmpl('templates/file_list.html')
}

// format_size formats bytes to human readable
fn format_size(bytes int) string {
	if bytes < 1024 {
		return '${bytes} B'
	} else if bytes < 1024 * 1024 {
		return '${bytes / 1024:.1} KB'
	} else {
		return '${bytes / 1024 / 1024:.1} MB'
	}
}

// time_now_str returns current time as string
fn time_now_str() string {
	t := time.now()
	return '${t.year}-${t.month:02d}-${t.day:02d} ${t.hour:02d}:${t.minute:02d}:${t.second:02d}'
}

fn main() {
	mut html_filename := './ui/index.html'
	if os.args.len >= 2 {
		html_filename = os.args[1]
	}

	mut app := App{}
	app.chunk_bufs = map[string][]string{}
	app.init_upload_dir()
	app.config.close_timer_ms = 1000
	app.config.window = vxui.WindowConfig{
		width:  700
		height: 600
		title:  'File Manager - vxui'
	}
	app.config.log.level = .info

	vxui.run(mut app, html_filename) or {
		eprintln('Error: ${err}')
		exit(1)
	}
}
