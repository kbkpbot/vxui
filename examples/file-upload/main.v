module main

import vxui
import os
import x.json2
import encoding.base64

// FileInfo represents uploaded file metadata
struct FileInfo {
	name     string
	size     int
	mime     string
	data     string // base64 encoded
	uploaded string
}

// App inherits from vxui.Context
struct App {
	vxui.Context
mut:
	files      []FileInfo
	upload_dir string
}

// init_upload_dir creates the upload directory
fn (mut app App) init_upload_dir() {
	app.upload_dir = os.join_path(os.temp_dir(), 'vxui_uploads_${os.now_unix()}')
	os.mkdir_all(app.upload_dir) or {}
}

// index serves the main page
@['/']
fn (mut app App) index(message map[string]json2.Any) string {
	return app.render_file_list()
}

// upload handles file upload
@['/upload', 'post']
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

	decoded := base64.decode_str(data) or {
		return '<div id="message" class="error">Failed to decode file data</div>'
	}

	// Save to disk
	file_path := os.join_path(app.upload_dir, filename)
	os.write_file(file_path, decoded) or {
		return '<div id="message" class="error">Failed to save file: ${err.msg()}</div>'
	}

	// Store file info
	file_info := FileInfo{
		name:     filename
		size:     decoded.len
		mime:     mimetype
		data:     data
		uploaded: time_now_str()
	}
	app.files << file_info

	return '<div id="message" class="success">File "${filename}" uploaded successfully!</div>' +
		app.render_file_list()
}

// delete removes a file
@['/delete', 'post']
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
					link.href = "data:${file.mime};base64,${file.data}";
					link.download = "${file.name}";
					link.click();
				})();
			</script>'
		}
	}

	return '<div id="message" class="error">File not found</div>'
}

// render_file_list generates the HTML for the file list
fn (mut app App) render_file_list() string {
	mut html := '<ul id="file-list" hx-swap-oob="true">'

	if app.files.len == 0 {
		html += '<li class="empty">No files uploaded yet</li>'
	} else {
		for file in app.files {
			html += '<li>
				<div class="file-info">
					<span class="file-name">${file.name}</span>
					<span class="file-meta">${format_size(file.size)} | ${file.mime}</span>
					<span class="file-time">${file.uploaded}</span>
				</div>
				<div class="file-actions">
					<button hx-get="/download" hx-vals=\'{"filename": "${file.name}"}\' hx-target="#download-area">Download</button>
					<button hx-post="/delete" hx-vals=\'{"filename": "${file.name}"}\' hx-target="#file-list" hx-swap="outerHTML" class="delete">Delete</button>
				</div>
			</li>'
		}
	}

	html += '</ul>'

	// Stats
	html += '<div id="stats" hx-swap-oob="true" class="stats">
		<span>${app.files.len} files</span>
		<span>Total: ${format_size(app.files.map(it.size).sum())}</span>
	</div>'

	return html
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
	app.init_upload_dir()
	app.config.close_timer_ms = 10000
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
