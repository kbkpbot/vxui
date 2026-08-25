module main

import vxui
import x.json2
import time
import sync
import rand

// Demonstrates: mouse-precision interaction (left = reveal, right = flag),
// the programmatic rpc() + applyResponseHtml() API pair, server-side
// timing, and first-click-safe mine generation. All rules in V; the page
// forwards mouse events and renders returned fragments.

const default_page_html_file = './ui/index.html'

const bw = 16

const bh = 16

const mine_count = 40

// App holds the authoritative field.
@[heap]
struct App {
	vxui.Context
mut:
	mu       sync.RwMutex
	mines    [bw * bh]bool
	counts   [bw * bh]int // neighbouring mine count 0..8
	revealed [bw * bh]bool
	flagged  [bw * bh]bool
	generated bool
	place_err string
	over     bool
	win      bool
	start_ms i64
	end_ms   i64
	flags    int
	opened   int // revealed non-mine cells
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

fn idx(x int, y int) int {
	return y * bw + x
}

// =============================================================================
// Rules (backend-authoritative)
// =============================================================================

// generate lays mines avoiding the 3x3 area around the first click, then
// computes the neighbour counts.
fn (mut app App) generate(safe_x int, safe_y int) {
	app.mines = [bw * bh]bool{}
	app.counts = [bw * bh]int{}
	mut placed := 0
	for placed < mine_count {
		x := rand.int_in_range(0, bw - 1) or { 0 }
		y := rand.int_in_range(0, bh - 1) or { 0 }
		i := idx(x, y)
		if app.mines[i] {
			continue
		}
		// first-click safety: nothing within Chebyshev distance 1 of the click
		if x >= safe_x - 1 && x <= safe_x + 1 && y >= safe_y - 1 && y <= safe_y + 1 {
			continue
		}
		app.mines[i] = true
		placed++
	}
	for y in 0 .. bh {
		for x in 0 .. bw {
			if app.mines[idx(x, y)] {
				continue
			}
			mut n := 0
			for dy in -1 .. 2 {
				for dx in -1 .. 2 {
					if dx == 0 && dy == 0 {
						continue
					}
					xx := x + dx
					yy := y + dy
					if xx >= 0 && xx < bw && yy >= 0 && yy < bh && app.mines[idx(xx, yy)] {
						n++
					}
				}
			}
			app.counts[idx(x, y)] = n
		}
	}
	app.generated = true
	app.start_ms = time.now().unix_milli()
}

// reveal uncovers (x,y). Flood-fills zero regions. Returns a user-facing
// rejection via place_err-style field semantics: '' on success.
fn (mut app App) reveal(x int, y int) {
	app.place_err = ''
	if app.over {
		app.place_err = 'Game over — New Board to retry'
		return
	}
	i := idx(x, y)
	if app.flagged[i] {
		app.place_err = 'Cell is flagged — unflag it first'
		return
	}
	if app.revealed[i] {
		return // no-op, not an error
	}
	if !app.generated {
		app.generate(x, y)
	}
	if app.mines[i] {
		app.revealed[i] = true
		app.over = true
		app.win = false
		app.end_ms = time.now().unix_milli()
		return
	}
	// flood fill
	mut stack := [i]
	for stack.len > 0 {
		cur := stack[stack.len - 1]
		stack = stack[..stack.len - 1].clone()
		if app.revealed[cur] || app.flagged[cur] || app.mines[cur] {
			continue
		}
		app.revealed[cur] = true
		app.opened++
		if app.counts[cur] == 0 {
			cx := cur % bw
			cy := cur / bw
			for dy in -1 .. 2 {
				for dx in -1 .. 2 {
					if dx == 0 && dy == 0 {
						continue
					}
					xx := cx + dx
					yy := cy + dy
					if xx >= 0 && xx < bw && yy >= 0 && yy < bh {
						ni := idx(xx, yy)
						if !app.revealed[ni] && !app.flagged[ni] {
							stack << ni
						}
					}
				}
			}
		}
	}
	app.check_win()
}

// toggle_flag places/removes a flag.
fn (mut app App) toggle_flag(x int, y int) {
	app.place_err = ''
	if app.over {
		app.place_err = 'Game over — New Board to retry'
		return
	}
	i := idx(x, y)
	if app.revealed[i] {
		app.place_err = 'Cell already revealed'
		return
	}
	app.flagged[i] = !app.flagged[i]
	if app.flagged[i] {
		app.flags++
	} else {
		app.flags--
	}
}

// check_win declares victory when every non-mine cell is revealed.
fn (mut app App) check_win() {
	if app.opened == bw * bh - mine_count {
		app.over = true
		app.win = true
		app.end_ms = time.now().unix_milli()
	}
}

// reset starts a fresh board.
fn (mut app App) reset() {
	app.mines = [bw * bh]bool{}
	app.counts = [bw * bh]int{}
	app.revealed = [bw * bh]bool{}
	app.flagged = [bw * bh]bool{}
	app.generated = false
	app.over = false
	app.win = false
	app.start_ms = 0
	app.end_ms = 0
	app.flags = 0
	app.opened = 0
}

// place_err doubles as the rejection field for both actions.
// (kept on App: void helpers cannot return errors — see AGENTS.md)

// =============================================================================
// Rendering
// =============================================================================

// elapsed_str formats the running or final timer.
fn (app &App) elapsed_str() string {
	if app.start_ms == 0 {
		return '0s'
	}
	end := if app.end_ms > 0 { app.end_ms } else { time.now().unix_milli() }
	s := (end - app.start_ms) / 1000
	return '${s}s'
}

// render_board_inner returns the grid WITHOUT the #board wrapper — the page
// applies it into #board via applyResponseHtml.
fn (app &App) render_board_inner() string {
	mut sb := []string{}
	sb << '<div class="grid">'
	for y in 0 .. bh {
		for x in 0 .. bw {
			i := idx(x, y)
			mut cls := 'cell'
			mut inner := ''
			if app.over && app.mines[i] && !app.flagged[i] {
				cls = 'cell mine-shown'
				inner = '*'
			} else if app.flagged[i] {
				cls = 'cell flagged'
				inner = '⚑'
			} else if app.revealed[i] {
				if app.mines[i] {
					cls = 'cell mine-hit'
					inner = '*'
				} else {
					n := app.counts[i]
					cls = 'cell open n${n}'
					inner = if n > 0 { '${n}' } else { '' }
				}
			} else {
				cls = 'cell hidden'
			}
			// data attributes for the page's click bridge
			sb << '<div class="${cls}" data-x="${x}" data-y="${y}">${inner}</div>'
		}
	}
	sb << '</div>'
	return sb.join('\n')
}

// render_hud_oob returns score/time/status as an out-of-band fragment.
fn (app &App) render_hud_oob() string {
	status := if app.over {
		if app.win { '<span class="msg win">CLEARED in ${app.elapsed_str()} — New Board to replay</span>' } else { '<span class="msg lose">BOOM — New Board to retry</span>' }
	} else {
		'<span class="msg">mines ${mine_count - app.flags} · ${app.elapsed_str()}</span>'
	}
	return '<div id="hud" hx-swap-oob="innerHTML:#hud">${status}</div>'
}

// full_response is what /reveal and /flag return: board inner + hud oob.
fn (app &App) full_response() string {
	return app.render_board_inner() + '\n' + app.render_hud_oob()
}

// =============================================================================
// Routes — responses are consumed by the page via rpc() + applyResponseHtml()
// =============================================================================

// reveal uncovers a cell (left click).
@['/reveal']
fn (mut app App) reveal_handler(message map[string]json2.Any) string {
	x := param(message, 'x').int()
	y := param(message, 'y').int()
	app.mu.lock()
	app.reveal(x, y)
	resp := app.full_response()
	app.mu.unlock()
	return resp
}

// flag toggles a flag (right click).
@['/flag']
fn (mut app App) flag_handler(message map[string]json2.Any) string {
	x := param(message, 'x').int()
	y := param(message, 'y').int()
	app.mu.lock()
	app.toggle_flag(x, y)
	resp := app.full_response()
	app.mu.unlock()
	return resp
}

// new_board resets.
@['/new']
fn (mut app App) new_board(_ map[string]json2.Any) string {
	app.mu.lock()
	app.reset()
	resp := app.full_response()
	app.mu.unlock()
	return resp
}

fn main() {
	mut app := App{}
	app.config.app_name = 'minesweeper'
	app.config.close_timer_ms = 60_000
	app.config.window = vxui.WindowConfig{
		width:  640
		height: 780
		title:  'Minesweeper — vxui'
	}

	vxui.run(mut app, default_page_html_file)!
}
