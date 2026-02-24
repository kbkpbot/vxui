module vxui

// embed.v - Support for embedding frontend resources into executable
//
// Usage:
// ```v
// module main
//
// import vxui
//
// // Embed your frontend files
// const index_html = $embed_file('ui/index.html')
// const app_css = $embed_file('ui/style.css')
// const app_js = $embed_file('ui/app.js')
//
// struct App {
//     vxui.Context
// }
//
// fn main() {
//     mut app := App{}
//
//     // Create packed resources
//     mut packed := vxui.new_packed_app()
//     packed.add_file('index.html', index_html)
//     packed.add_file('style.css', app_css)
//     packed.add_file('app.js', app_js)
//
//     // Run with packed resources (extracts to temp dir)
//     vxui.run_packed(mut app, packed)!
// }
// ```
//
// Build single executable:
// ```bash
// v -prod -compress myapp.v
// ```
import os
import time
import rand

// PackedApp holds embedded frontend resources
pub struct PackedApp {
pub mut:
	files map[string]EmbeddedFile
}

// EmbeddedFile represents an embedded file
pub struct EmbeddedFile {
pub:
	data []u8
	size int
}

// new_packed_app creates a new PackedApp instance
pub fn new_packed_app() PackedApp {
	return PackedApp{
		files: map[string]EmbeddedFile{}
	}
}

// add_file adds an embedded file to the packed app
// Accepts both []u8 and EmbedFileData (from $embed_file)
pub fn (mut p PackedApp) add_file(path string, data []u8) {
	p.files[path] = EmbeddedFile{
		data: data
		size: data.len
	}
}

// add_file_string adds an embedded file from string
pub fn (mut p PackedApp) add_file_string(path string, content string) {
	p.files[path] = EmbeddedFile{
		data: content.bytes()
		size: content.len
	}
}

// extract_to extracts all files to a directory
pub fn (p PackedApp) extract_to(dir string) ! {
	// Create directory if not exists
	if !os.exists(dir) {
		os.mkdir_all(dir)!
	}

	for path, file in p.files {
		full_path := os.join_path(dir, path)

		// Create parent directories
		parent := os.dir(full_path)
		if !os.exists(parent) {
			os.mkdir_all(parent)!
		}

		// Write file
		os.write_file(full_path, file.data.bytestr())!
	}
}

// extract_to_temp extracts all files to a temp directory and returns the path
pub fn (p PackedApp) extract_to_temp() !string {
	temp_dir := os.join_path(os.temp_dir(), 'vxui_${time.now().unix()}_${rand.u32()}')
	p.extract_to(temp_dir)!
	return temp_dir
}

// get_file retrieves a file by path
pub fn (p PackedApp) get_file(path string) !EmbeddedFile {
	return p.files[path] or { error('File not found: ${path}') }
}

// get_file_content retrieves file content as string
pub fn (p PackedApp) get_file_content(path string) !string {
	file := p.get_file(path)!
	return file.data.bytestr()
}

// has_file checks if a file exists
pub fn (p PackedApp) has_file(path string) bool {
	return path in p.files
}

// list_files returns all file paths
pub fn (p PackedApp) list_files() []string {
	mut paths := []string{}
	for path, _ in p.files {
		paths << path
	}
	return paths
}

// total_size returns total size of all embedded files
pub fn (p PackedApp) total_size() int {
	mut total := 0
	for _, file in p.files {
		total += file.size
	}
	return total
}

// cleanup removes extracted files
pub fn (p PackedApp) cleanup(dir string) {
	if os.exists(dir) {
		os.rmdir_all(dir) or {}
	}
}
