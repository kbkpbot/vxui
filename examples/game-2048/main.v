module main

import vxui
import x.json2
import rand

// Demonstrates: backend-authoritative game state (all 2048 rules in V),
// keyboard-driven declarative htmx triggers, one WS round-trip per keypress,
// multi-target partial updates (#board swap + #hud oob).
//
// Latency note: the framework's loopback RPC RTT is ~0.6ms p50 / 1.3ms p99
// (see perf_rtt_test.v), so even fast key-mashing stays far below human
// perception thresholds. The page holds no game logic — the browser is just a
// screen with a keyboard.

const default_page_html_file = './ui/index.html'

const board_size = 4

const win_tile = 2048

// App holds the authoritative game state. The browser never sees it — only
// rendered fragments after every move.
@[heap]
struct App {
	vxui.Context
mut:
	board   [board_size][board_size]int
	score   int
	best    int
	over    bool
	won     bool
	move_no int
	// animation hints for the next render: the freshly spawned cell and the
	// cells created by merges (they get distinct pop effects in CSS)
	spawn_at  [2]int
	has_spawn bool
	merged    [][]int
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
// Game rules (backend-authoritative)
// =============================================================================

// slide_row_left slides and merges one row towards index 0. Returns the
// points gained; mutates the row in place.
fn slide_row_left(mut row []int) int {
	mut gain := 0
	mut vals := []int{}
	for v in row {
		if v != 0 {
			vals << v
		}
	}
	mut merged := []int{}
	mut i := 0
	for i < vals.len {
		if i + 1 < vals.len && vals[i] == vals[i + 1] {
			merged << vals[i] * 2
			gain += vals[i] * 2
			i += 2
		} else {
			merged << vals[i]
			i++
		}
	}
	for j in 0 .. row.len {
		row[j] = if j < merged.len { merged[j] } else { 0 }
	}
	return gain
}

fn (app &App) get_row(r int) []int {
	mut out := []int{cap: board_size}
	for c in 0 .. board_size {
		out << app.board[r][c]
	}
	return out
}

fn (mut app App) set_row(r int, vals []int) {
	for c in 0 .. board_size {
		app.board[r][c] = vals[c]
	}
}

fn (app &App) get_col(c int) []int {
	mut out := []int{cap: board_size}
	for r in 0 .. board_size {
		out << app.board[r][c]
	}
	return out
}

fn (mut app App) set_col(c int, vals []int) {
	for r in 0 .. board_size {
		app.board[r][c] = vals[r]
	}
}

// apply_move applies one 2048 move. Returns true when the board changed
// (standard rule: only then spawn a new tile).
fn (mut app App) apply_move(direction string) bool {
	board_before := app.board
	mut changed := false
	match direction {
		'left' {
			for r in 0 .. board_size {
				before := app.get_row(r)
				mut row_vals := before.clone()
				gain := slide_row_left(mut row_vals)
				app.score += gain
				if row_vals != before {
					changed = true
				}
				app.set_row(r, row_vals)
			}
		}
		'right' {
			for r in 0 .. board_size {
				before := app.get_row(r)
				mut row_vals := before.clone()
				row_vals.reverse_in_place()
				gain := slide_row_left(mut row_vals)
				app.score += gain
				row_vals.reverse_in_place()
				if row_vals != before {
					changed = true
				}
				app.set_row(r, row_vals)
			}
		}
		'up' {
			for c in 0 .. board_size {
				before := app.get_col(c)
				mut col_vals := before.clone()
				gain := slide_row_left(mut col_vals)
				app.score += gain
				if col_vals != before {
					changed = true
				}
				app.set_col(c, col_vals)
			}
		}
		'down' {
			for c in 0 .. board_size {
				before := app.get_col(c)
				mut col_vals := before.clone()
				col_vals.reverse_in_place()
				gain := slide_row_left(mut col_vals)
				app.score += gain
				col_vals.reverse_in_place()
				if col_vals != before {
					changed = true
				}
				app.set_col(c, col_vals)
			}
		}
		else {}
	}
	if changed {
		app.mark_merges(board_before)
	}
	return changed
}

fn (app &App) has_empty() bool {
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			if app.board[r][c] == 0 {
				return true
			}
		}
	}
	return false
}

// can_move reports whether any merge or empty cell remains.
fn (app &App) can_move() bool {
	if app.has_empty() {
		return true
	}
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			v := app.board[r][c]
			if c + 1 < board_size && app.board[r][c + 1] == v {
				return true
			}
			if r + 1 < board_size && app.board[r + 1][c] == v {
				return true
			}
		}
	}
	return false
}

// spawn_tile places a 2 (90%) or 4 (10%) on a random empty cell and records
// its position so the renderer can play the "new tile" pop.
fn (mut app App) spawn_tile() {
	mut empty := [][]int{}
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			if app.board[r][c] == 0 {
				empty << [r, c]
			}
		}
	}
	if empty.len == 0 {
		return
	}
	cell := empty[rand.int_in_range(0, empty.len - 1) or { 0 }]
	value := if rand.int_in_range(0, 9) or { 0 } == 0 { 4 } else { 2 }
	app.board[cell[0]][cell[1]] = value
	app.spawn_at[0] = cell[0]
	app.spawn_at[1] = cell[1]
	app.has_spawn = true
}

// mark_merges records which cells were created by a merge this move: after a
// move, any cell whose value exactly doubled vs. the previous board.
fn (mut app App) mark_merges(before [board_size][board_size]int) {
	app.merged = []
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			if before[r][c] > 0 && app.board[r][c] == before[r][c] * 2 {
				app.merged << [r, c]
			}
		}
	}
}

// check_endgame updates the over/won flags and the best score.
fn (mut app App) check_endgame() {
	if !app.won {
		for r in 0 .. board_size {
			for c in 0 .. board_size {
				if app.board[r][c] >= win_tile {
					app.won = true
				}
			}
		}
	}
	if !app.can_move() {
		app.over = true
	}
	if app.score > app.best {
		app.best = app.score
	}
}

// reset starts a fresh game with two spawned tiles.
fn (mut app App) reset() {
	app.board = [board_size][board_size]int{}
	app.score = 0
	app.over = false
	app.won = false
	app.move_no = 0
	app.has_spawn = false
	app.merged = []
	app.spawn_tile()
	app.spawn_tile()
}

// =============================================================================
// Rendering — the browser only ever receives these fragments
// =============================================================================

fn (app &App) render_board() string {
	mut sb := []string{}
	sb << '<div id="board">'
	sb << '<div class="grid">'
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			v := app.board[r][c]
			if v == 0 {
				sb << '<div class="cell empty"></div>'
				continue
			}
			mut cls := 'cell tile tile-${v}'
			if app.has_spawn && r == app.spawn_at[0] && c == app.spawn_at[1] {
				cls += ' spawn'
			} else {
				for m in app.merged {
					if m[0] == r && m[1] == c {
						cls += ' merged'
						break
					}
				}
			}
			sb << '<div class="${cls}">${v}</div>'
		}
	}
	sb << '</div></div>'
	return sb.join('\n')
}

fn (app &App) hud_inner() string {
	msg := if app.over {
		'<span class="msg gameover">GAME OVER — New Game to retry</span>'
	} else if app.won {
		'<span class="msg win">YOU WIN — keep going!</span>'
	} else {
		'<span class="msg">Arrow keys to play</span>'
	}
	return '<div class="scores"><div class="box">SCORE<b>${app.score}</b></div><div class="box">BEST<b>${app.best}</b></div>${msg}<span class="mv">moves ${app.move_no}</span>'
}

// render_hud_oob returns the hud as an out-of-band fragment so one response
// updates two targets (#board via the main swap, #hud via oob).
fn (app &App) render_hud_oob() string {
	return '<div id="hud" hx-swap-oob="innerHTML:#hud">' + app.hud_inner() + '</div>'
}

// =============================================================================
// Routes
// =============================================================================

// new_game restarts and returns both live fragments.
@['/new']
fn (mut app App) new_game(_ map[string]json2.Any) string {
	app.reset()
	return app.render_board() + '\n' + app.render_hud_oob()
}

// do_move applies one keyboard move — the entire rule set runs here.
@['/move']
fn (mut app App) do_move(message map[string]json2.Any) string {
	if app.over {
		return app.render_board() + '\n' + app.render_hud_oob()
	}
	direction := param(message, 'direction')
	changed := app.apply_move(direction)
	if changed {
		app.spawn_tile()
		app.move_no++
		app.check_endgame()
	}
	return app.render_board() + '\n' + app.render_hud_oob()
}

fn main() {
	mut app := App{}
	app.config.app_name = '2048'
	app.config.close_timer_ms = 60_000
	app.reset()

	vxui.run(mut app, default_page_html_file)!
}
