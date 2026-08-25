module main

import os
import time

fn path_errs(p string) bool {
	check_editable_path(p) or { return true }
	return false
}

fn test_headings() {
	h := render_markdown('# Title' + '\n' + '## Sub' + '\n' + '### Deep')
	assert h.contains('<h1>Title</h1>')
	assert h.contains('<h2>Sub</h2>')
	assert h.contains('<h3>Deep</h3>')
	assert !h.contains('# Title')
}

fn test_bold_italic_code() {
	h := render_markdown('**bold** and *italic* and `code()`')
	assert h.contains('<strong>bold</strong>')
	assert h.contains('<em>italic</em>')
	assert h.contains('<code>code()</code>')
}

fn test_inline_code_protects_html() {
	h := render_markdown('use `<b>literal</b>` tags')
	assert h.contains('<code>&lt;b&gt;literal&lt;/b&gt;</code>')
}

fn test_html_is_escaped() {
	h := render_markdown('<script>alert(1)</script>')
	assert !h.contains('<script>')
	assert h.contains('&lt;script&gt;')
}

fn test_lists() {
	src := '- one' + '\n' + '- two' + '\n\n' + '1. first' + '\n' + '2. second'
	h := render_markdown(src)
	assert h.contains('<ul>')
	assert h.contains('<li>one</li>')
	assert h.contains('<li>two</li>')
	assert h.contains('<ol>')
	assert h.contains('<li>first</li>')
	assert h.contains('<li>second</li>')
	assert h.contains('</ul>') && h.contains('</ol>')
}

fn test_code_block_preserves_and_escapes() {
	src := '```' + '\n' + 'if (x < 1) { y = "&"; }' + '\n' + '```'
	h := render_markdown(src)
	assert h.contains('<pre><code>')
	assert h.contains('&lt; 1')
	assert h.contains('&amp;')
}

fn test_blockquote_and_hr() {
	src := '> quoted text' + '\n\n' + '---'
	h := render_markdown(src)
	assert h.contains('<blockquote>quoted text</blockquote>')
	assert h.contains('<hr/>')
}

fn test_paragraphs_split_on_blank_lines() {
	src := 'first para' + '\n\n' + 'second para'
	h := render_markdown(src)
	assert h.contains('<p>first para</p>')
	assert h.contains('<p>second para</p>')
}

fn test_path_accepts_absolute_and_relative() {
	assert check_editable_path('/home/user/notes/x.md')! == '/home/user/notes/x.md'
	assert check_editable_path('notes/x.md')! == 'notes/x.md'
	assert check_editable_path('../sibling/x.md')! == '../sibling/x.md'
	assert check_editable_path('  /tmp/a.md  ')! == '/tmp/a.md'
}

fn test_path_rejects_empty_and_nul() {
	assert path_errs('')
	assert path_errs('   ')
	assert path_errs('a' + '\x00' + 'b')
}

fn test_save_then_open_round_trip() {
	mut app := App{}
	dir := os.join_path(os.temp_dir(), 'mdeditor_test_' + time.now().unix_nano().str())
	os.mkdir_all(dir) or {}
	p := os.join_path(dir, 'note.md')
	content := '# Note' + '\n\n' + 'body **text**'

	app.save_file(p, content)!
	got_path, got_content := app.open_file(p)!
	assert got_path == p
	assert got_content == content
	assert app.save_count == 1
	assert app.open_count == 1
	assert app.current_path == p
	assert !app.dirty
	os.rmdir_all(dir) or {}
}

fn test_open_missing_file_errors() {
	mut app := App{}
	app.open_file('/nonexistent/definitely/missing.md') or {
		return
	}
	assert false, 'open of a missing file should have failed'
}

fn test_open_directory_errors() {
	mut app := App{}
	app.open_file(os.temp_dir()) or {
		return
	}
	assert false, 'open of a directory should have failed'
}
