module main

import vxui
import x.json2
import time
import os
import sync

// Demonstrates the desktop differentiator: reading and writing REAL files on
// this machine (something a web app cannot do), continuous text input via a
// debounced rpc, backend markdown rendering, and structured JSON responses.
//
// Security note: paths are validated with check_editable_path (rejects empty
// and NUL-injected paths) — NOT with sanitize_path, whose ../-traversal
// semantics target web request parameters. A local desktop editor is
// *supposed* to reach the whole filesystem.

const default_page_html_file = './ui/index.html'

// App tracks editor session state.
@[heap]
struct App {
	vxui.Context
mut:
	mu           sync.RwMutex
	current_path string
	dirty        bool
	save_count   int
	open_count   int
}

// param pulls a string parameter from the request.
fn param(message map[string]json2.Any, key string) string {
	if params := message['parameters'] {
		if v := params.as_map()[key] {
			return v.str()
		}
	}
	return ''
}

// =============================================================================
// Path validation (desktop semantics — see module comment)
// =============================================================================

// check_editable_path accepts any non-empty, NUL-free path. Absolute and
// relative paths, ~ and .. are all legitimate for a local editor.
fn check_editable_path(path string) !string {
	p := path.trim_space()
	if p == '' {
		return error('path is empty')
	}
	if p.contains('\x00') {
		return error('path contains a NUL byte')
	}
	return p
}

// =============================================================================
// Markdown rendering (lightweight, dependency-free)
// =============================================================================

// escape_html escapes &, <, > for safe interpolation.
fn escape_html(s string) string {
	return s.replace_each(['&', '&amp;', '<', '&lt;', '>', '&gt;'])
}

// render_pairs replaces marker-delimited pairs (non-greedy, left to right).
// An unpaired trailing marker is restored verbatim.
fn render_pairs(s string, marker string, open_tag string, close_tag string) string {
	mut out := ''
	mut rest := s
	mut open_state := true
	for {
		i := rest.index(marker) or {
			out += rest
			break
		}
		out += rest[..i]
		out += if open_state { open_tag } else { close_tag }
		rest = rest[i + marker.len..]
		open_state = !open_state
	}
	if !open_state {
		// dangling opener: restore the literal marker
		if out.ends_with(open_tag) {
			out = out[..out.len - open_tag.len] + marker
		} else {
			out += marker
		}
	}
	return out
}

// render_inline escapes the raw text and renders bold, italic and inline
// code. Inline code spans are escaped but protected from the style rules.
fn render_inline(raw string) string {
	s := escape_html(raw)
	parts := s.split('`')
	mut out := []string{}
	for i, part in parts {
		if i % 2 == 1 {
			out << '<code>' + part + '</code>'
			continue
		}
		mut seg := render_pairs(part, '**', '<strong>', '</strong>')
		seg = render_pairs(seg, '*', '<em>', '</em>')
		out << seg
	}
	return out.join('')
}

// render_markdown renders a practical markdown subset: headings, hr,
// blockquotes, ul/ol lists, fenced code blocks, paragraphs, and inline
// styles. Good enough for live preview; not a full CommonMark implementation.
fn render_markdown(src string) string {
	lines := src.split('\n')
	mut out := []string{}
	mut in_code := false
	mut code_buf := []string{}
	mut para := []string{}
	mut list_tag := '' // '' | 'ul' | 'ol'

	for raw in lines {
		line := raw.trim_space()
		if line.starts_with('```') {
			if list_tag != '' {
				out << '</${list_tag}>'
				list_tag = ''
			}
			if para.len > 0 {
				out << '<p>' + render_inline(para.join(' ')) + '</p>'
				para = []
			}
			if in_code {
				out << '<pre><code>' + escape_html(code_buf.join('\n')) + '</code></pre>'
				code_buf = []
				in_code = false
			} else {
				in_code = true
			}
			continue
		}
		if in_code {
			code_buf << raw
			continue
		}
		if line == '' {
			if list_tag != '' {
				out << '</${list_tag}>'
				list_tag = ''
			}
			if para.len > 0 {
				out << '<p>' + render_inline(para.join(' ')) + '</p>'
				para = []
			}
			continue
		}
		// headings
		if line.starts_with('#') {
			mut level := 0
			for ch in line {
				if ch == `#` {
					level++
				} else {
					break
				}
			}
			if level >= 1 && level <= 6 && line.len > level && line[level] == ` ` {
				if list_tag != '' {
					out << '</${list_tag}>'
					list_tag = ''
				}
				if para.len > 0 {
					out << '<p>' + render_inline(para.join(' ')) + '</p>'
					para = []
				}
				text := render_inline(escape_html(line[level + 1..].trim_space()))
				out << '<h${level}>' + text + '</h${level}>'
				continue
			}
		}
		// horizontal rule
		if line == '---' || line == '***' || line == '___' {
			if list_tag != '' {
				out << '</${list_tag}>'
				list_tag = ''
			}
			if para.len > 0 {
				out << '<p>' + render_inline(para.join(' ')) + '</p>'
				para = []
			}
			out << '<hr/>'
			continue
		}
		// blockquote
		if line.starts_with('> ') || line == '>' {
			if list_tag != '' {
				out << '</${list_tag}>'
				list_tag = ''
			}
			if para.len > 0 {
				out << '<p>' + render_inline(para.join(' ')) + '</p>'
				para = []
			}
			out << '<blockquote>' + render_inline(escape_html(line.trim_left('> ').trim_space())) + '</blockquote>'
			continue
		}
		// unordered list
		if (line.starts_with('- ') || line.starts_with('* ') || line.starts_with('+ ')) && list_tag != 'ol' {
			if list_tag == '' {
				if para.len > 0 {
					out << '<p>' + render_inline(para.join(' ')) + '</p>'
					para = []
				}
				out << '<ul>'
				list_tag = 'ul'
			}
			out << '<li>' + render_inline(escape_html(line[2..].trim_space())) + '</li>'
			continue
		}
		// ordered list: digits followed by '. '
		mut ol_len := 0
		for ch in line {
			if ch.is_digit() {
				ol_len++
			} else {
				break
			}
		}
		if ol_len > 0 && ol_len + 1 < line.len && line[ol_len] == `.` && line[ol_len + 1] == ` ` {
			if list_tag != 'ol' {
				if para.len > 0 {
					out << '<p>' + render_inline(para.join(' ')) + '</p>'
					para = []
				}
				out << '<ol>'
				list_tag = 'ol'
			}
			out << '<li>' + render_inline(escape_html(line[ol_len + 2..].trim_space())) + '</li>'
			continue
		}
		if list_tag == 'ul' || list_tag == 'ol' {
			// continuation line: append to the previous <li> as a soft break
			if out.len > 0 {
				prev := out[out.len - 1]
				if prev.ends_with('</li>') {
					out[out.len - 1] = prev[..prev.len - '</li>'.len] + ' ' +
						render_inline(escape_html(line)) + '</li>'
					continue
				}
			}
			para << line
		}
		para << line
	}
	// EOF flushes
	if in_code {
		out << '<pre><code>' + escape_html(code_buf.join('\n')) + '</code></pre>'
	}
	if list_tag != '' {
		out << '</${list_tag}>'
	}
	if para.len > 0 {
		out << '<p>' + render_inline(para.join(' ')) + '</p>'
	}
	return out.join('\n')
}

// =============================================================================
// File IO (desktop semantics)
// =============================================================================

// open_file reads a local file for editing.
fn (mut app App) open_file(path string) !(string, string) {
	p := check_editable_path(path)!
	if !os.exists(p) {
		return error('file not found: ${p}')
	}
	if os.is_dir(p) {
		return error('path is a directory: ${p}')
	}
	content := os.read_file(p) or {
		return error('cannot read: ${err.msg()}')
	}
	app.mu.lock()
	app.current_path = p
	app.dirty = false
	app.open_count++
	app.mu.unlock()
	return p, content
}

// save_file writes content to a local file.
fn (mut app App) save_file(path string, content string) !string {
	p := check_editable_path(path)!
	os.write_file(p, content) or {
		return error('cannot write: ${err.msg()}')
	}
	app.mu.lock()
	app.current_path = p
	app.dirty = false
	app.save_count++
	app.mu.unlock()
	return p
}

// =============================================================================
// Routes — /open and /save return STRUCTURED JSON (the page parses it);
// /preview returns an HTML fragment (the page injects it directly).
// Both response styles are framework capabilities worth showing.
// =============================================================================

// preview renders markdown to HTML.
@['/preview']
fn (mut app App) preview_handler(message map[string]json2.Any) string {
	content := param(message, 'content')
	return render_markdown(content)
}

// open reads a local file: JSON {content, path, preview, chars}.
@['/open']
fn (mut app App) open_handler(message map[string]json2.Any) string {
	path := param(message, 'path')
	p, content := app.open_file(path) or {
		return json2.encode({'ok': json2.Any(false), 'error': json2.Any(err.msg())})
	}
	resp := {
		'ok':      json2.Any(true)
		'path':    json2.Any(p)
		'content': json2.Any(content)
		'chars':   json2.Any(content.len)
	}
	return json2.encode(resp)
}

// save writes a local file: JSON {ok, path, saved_at, chars}.
@['/save']
fn (mut app App) save_handler(message map[string]json2.Any) string {
	path := param(message, 'path')
	content := param(message, 'content')
	p := app.save_file(path, content) or {
		return json2.encode({'ok': json2.Any(false), 'error': json2.Any(err.msg())})
	}
	ts := time.now().format_ss()
	resp := {
		'ok':       json2.Any(true)
		'path':     json2.Any(p)
		'saved_at': json2.Any(ts)
		'chars':    json2.Any(content.len)
	}
	return json2.encode(resp)
}

// new_doc clears the editor (no file side effects).
@['/new']
fn (mut app App) new_handler(_ map[string]json2.Any) string {
	app.mu.lock()
	app.current_path = ''
	app.dirty = false
	app.mu.unlock()
	return json2.encode({'ok': json2.Any(true)})
}

// stats returns session counters (JSON).
@['/stats']
fn (mut app App) stats_handler(_ map[string]json2.Any) string {
	app.mu.rlock()
	defer {
		app.mu.runlock()
	}
	resp := {
		'path':     json2.Any(app.current_path)
		'dirty':    json2.Any(app.dirty)
		'saves':    json2.Any(app.save_count)
		'opens':    json2.Any(app.open_count)
		'saved_at': json2.Any(time.now().format_ss())
	}
	return json2.encode(resp)
}

fn main() {
	mut app := App{}
	app.config.app_name = 'markdown-editor'
	app.config.close_timer_ms = 60_000
	app.config.window = vxui.WindowConfig{
		width:  1160
		height: 720
		title:  'Markdown Editor — vxui'
	}

	vxui.run(mut app, default_page_html_file)!
}
