module main

import vxui
import x.json2
import sync

// Demonstrates: multi-window real-time play on one backend session.
// Two browser windows join as BLACK/WHITE (later windows spectate); every
// move is validated against the caller's identity (message.client_id,
// injected by dispatch_rpc) and broadcast to ALL windows via oob_update.
//
// The page holds no game logic: cells are declarative htmx triggers, the
// backend renders fragments, and synchronization is pure broadcast.

const default_page_html_file = './ui/index.html'

const board_size = 15

const win_len = 5

// App holds the authoritative match state.
@[heap]
struct App {
	vxui.Context
mut:
	mu       sync.RwMutex
	board    [board_size][board_size]int // 0 empty, 1 black, 2 white
	black_id string // client_id of the black player
	white_id string // client_id of the white player
	turn     int = 1 // 1 black, 2 white
	over      bool
	winner    int
	place_err  string // last rule rejection (void helpers can't return errors)
	invite_err string // last second-window launch failure
	last_x   int = -1
	last_y   int = -1
	move_no  int
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
// Rules (backend-authoritative)
// =============================================================================

// role_of maps a client_id to its stone color: 1 black, 2 white, 0 spectator.
fn (app &App) role_of(client_id string) int {
	if client_id != '' && client_id == app.black_id {
		return 1
	}
	if client_id != '' && client_id == app.white_id {
		return 2
	}
	return 0
}

// place tries to put a stone for `color` at (x,y). The rejection reason, if
// any, lands in place_err (void return: string-returning helpers with custom
// parameters trip fire_call's comptime dispatch — see AGENTS.md).
fn (mut app App) place(x int, y int, color int) {
	app.place_err = ''
	if app.over {
		app.place_err = 'Game over — start a new match'
		return
	}
	if color == 0 {
		app.place_err = 'You are a spectator'
		return
	}
	if color != app.turn {
		app.place_err = 'Not your turn'
		return
	}
	if x < 0 || x >= board_size || y < 0 || y >= board_size {
		app.place_err = 'Out of board'
		return
	}
	if app.board[y][x] != 0 {
		app.place_err = 'Cell occupied'
		return
	}
	app.board[y][x] = color
	app.last_x = x
	app.last_y = y
	app.move_no++
	if app.check_win(x, y, color) {
		app.over = true
		app.winner = color
	} else if app.move_no == board_size * board_size {
		app.over = true // draw
		app.winner = 0
	} else {
		app.turn = 3 - color // swap turns
	}
}

// check_win counts contiguous stones through (x,y) on all four axes.
fn (app &App) check_win(x int, y int, color int) bool {
	dirs := [[1, 0], [0, 1], [1, 1], [1, -1]]
	for d in dirs {
		mut count := 1
		for s in 1 .. win_len {
			xx := x + d[0] * s
			yy := y + d[1] * s
			if xx < 0 || xx >= board_size || yy < 0 || yy >= board_size
				|| app.board[yy][xx] != color {
				break
			}
			count++
		}
		for s in 1 .. win_len {
			xx := x - d[0] * s
			yy := y - d[1] * s
			if xx < 0 || xx >= board_size || yy < 0 || yy >= board_size
				|| app.board[yy][xx] != color {
				break
			}
			count++
		}
		if count >= win_len {
			return true
		}
	}
	return false
}

// seat assigns a joining client to a color: first = BLACK, second = WHITE,
// later = spectator (0). Returns the assigned color.
fn (mut app App) seat(client_id string) int {
	app.mu.lock()
	defer {
		app.mu.unlock()
	}
	mut color := 0
	if client_id == '' {
		return 0
	}
	if app.black_id == '' {
		app.black_id = client_id
		color = 1
	} else if app.white_id == '' {
		app.white_id = client_id
		color = 2
	}
	return color
}

// reset starts a fresh match; player seats are kept.
fn (mut app App) reset() {
	app.board = [board_size][board_size]int{}
	app.turn = 1
	app.over = false
	app.winner = 0
	app.last_x = -1
	app.last_y = -1
	app.move_no = 0
}

// =============================================================================
// Rendering
// =============================================================================

// render_board renders the full grid. Each empty cell is its own htmx
// trigger posting /place with fixed coordinates — 225 declarative triggers,
// zero custom JS. The container is swapped via oob by broadcast.
fn (app &App) render_board() string {
	mut sb := []string{}
	sb << '<div id="board" hx-swap-oob="outerHTML">'
	sb << '<div class="grid">'
	for y in 0 .. board_size {
		for x in 0 .. board_size {
			v := app.board[y][x]
			last := app.last_x == x && app.last_y == y
			if v == 0 {
				star := ((x == 3 || x == 11) && (y == 3 || y == 11)) || (x == 7 && y == 7)
				star_cls := if star { ' star' } else { '' }
				sb << '<div class="cell empty${star_cls}" hx-post="/place" hx-vals=\'{"x":${x},"y":${y}}\' hx-swap="none"></div>'
			} else {
				mut cls := if v == 1 { 'cell stone black' } else { 'cell stone white' }
				if last {
					cls += ' last'
				}
				sb << '<div class="${cls}"></div>'
			}
		}
	}
	sb << '</div></div>'
	return sb.join('\n')
}

// render_hud_oob returns the status line as an out-of-band fragment.
fn (app &App) render_hud_oob() string {
	turn_name := if app.turn == 1 { 'BLACK ●' } else { 'WHITE ○' }
	msg := if app.over {
		if app.winner == 0 {
			'DRAW'
		} else {
			'${if app.winner == 1 { 'BLACK ●' } else { 'WHITE ○' }} WINS — New Match to replay'
		}
	} else {
		'${turn_name} to move (move ${app.move_no + 1})'
	}
	return '<div id="hud" hx-swap-oob="innerHTML:#hud"><span class="msg ${if app.over { "end" } else { "" }}">{{MSG}}</span></div>'.replace('{{MSG}}', msg)
}

// broadcast_state pushes board + hud to every connected window.
fn (mut app App) broadcast_state() {
	html := app.render_board() + '\n' + app.render_hud_oob()
	payload := {'cmd': 'oob_update', 'html': html}
	wire := json2.encode(payload)
	app.broadcast(wire) or {
	}
}

// =============================================================================
// Routes
// =============================================================================

// state returns the current fragments WITHOUT resetting — new windows and
// reconnects fetch it on load. This is also the SEATING point: the caller's
// client_id (injected by dispatch_rpc) claims BLACK/WHITE here, idempotently.
@['/state']
fn (mut app App) state(message map[string]json2.Any) string {
	// client_id is injected at the TOP level of the message by dispatch_rpc
	client_id := message['client_id'] or { json2.Any('') }.str()
	color := app.seat(client_id)
	if color > 0 {
		label := if color == 1 { 'YOU PLAY BLACK ●' } else { 'YOU PLAY WHITE ○' }
		app.post_js_client(client_id, "document.getElementById('mycolor').textContent='${label}'") or {}
	} else {
		app.post_js_client(client_id, "document.getElementById('mycolor').textContent='YOU SPECTATE'") or {}
	}
	app.mu.rlock()
	defer {
		app.mu.runlock()
	}
	return app.render_board() + '\n' + app.render_hud_oob()
}

// new_match resets the game (any window may request it) and syncs everyone.
@['/new']
fn (mut app App) new_match(_ map[string]json2.Any) string {
	app.mu.lock()
	app.reset()
	app.broadcast_state()
	app.mu.unlock()
	return ''
}

// place handles one stone. The caller identity comes from message.client_id
// (injected by dispatch_rpc); the response body is empty because the move is
// propagated to EVERY window — including the caller — via broadcast.
@['/place']
fn (mut app App) place_handler(message map[string]json2.Any) string {
	client_id := message['client_id'] or { json2.Any('') }.str()
	x := param(message, 'x').int()
	y := param(message, 'y').int()

	app.mu.lock()
	color := app.role_of(client_id)
	app.place(x, y, color)
	err := app.place_err
	if err == '' {
		app.broadcast_state()
	}
	app.mu.unlock()
	if err != '' {
		// surface the rejection on the offending window only
		payload := {'cmd': 'oob_update', 'html': '<div id="notice" hx-swap-oob="innerHTML:#notice"><span class="warn">${err}</span></div>'}
		app.send_to_client(client_id, json2.encode(payload)) or {}
	}
	return ''
}

// invite launches a SECOND browser window pointed at the same match —
// the framework's browser management doubles as the "invite player"
// button. The second instance gets its own profile (independent window)
// and a debug port so tooling can inspect both players.
@['/invite']
fn (mut app App) invite(_ map[string]json2.Any) string {
	// fire-and-forget: browser startup takes seconds and must not block the
	// read loop (spawn keeps this handler instant)
	spawn fn [mut app] () {
		defer {
			app.mu.lock()
			err := app.invite_err
			app.invite_err = ''
			app.mu.unlock()
			// ALWAYS close the loop: silence here looks exactly like a dead
			// button to the player who clicked it
			msg := if err != '' {
				'<span class="warn">${err}</span>'
			} else {
				'<span class="msg">Second window launched — it plays WHITE ○</span>'
			}
			payload := {'cmd': 'oob_update', 'html': '<div id="notice" hx-swap-oob="innerHTML:#notice">${msg}</div>'}
			app.broadcast(json2.encode(payload)) or {}
		}
		cfg := vxui.BrowserConfig{
			custom_args: [
				'--disable-features=Translate,TranslateUI,TranslateMessageUI',
				'--lang=en-US',
				'--remote-debugging-port=9555',
				'--remote-allow-origins=*',
			]
		}
		vxui.start_browser_with_config(default_page_html_file, app.ws_port,
			app.config.token, vxui.WindowConfig{
				width:  640
				height: 900
				x:      120
				y:      120
				title:  'Gomoku — Player 2'
			}, cfg) or {
			app.mu.lock()
			app.invite_err = 'Could not launch the second window: ${err.msg()}'
			app.mu.unlock()
			return
		}
	}()
	return ''
}

// render_page serves the complete shell around the live fragments.
fn (app &App) render_page() string {
	head := '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Gomoku — vxui</title>
<link rel="stylesheet" href="./stylesheet.css"/>
<script src="./js/htmx.js"></script>
<script src="./js/vxui-ws.js"></script>
</head>
<body hx-ext="vxui-ws">
<header>
<h1>Gomoku</h1>
<div id="mycolor" class="mycolor">…</div>
<div id="hud"><span class="msg">connecting…</span></div>
<button hx-post="/new" hx-swap="none" class="ghost">New Match</button>
<p class="hint">Open a <b>second browser window</b> on the same page: the first
window plays BLACK, the second WHITE, further windows spectate. Every move is
validated against the caller identity and broadcast to all windows.</p>
</header>
<div id="notice"><span class="warn"></span></div>
<div id="board"><div class="grid"></div></div>
<script>
document.body.addEventListener("vxui:authenticated", function () {
	// pull the current match without resetting it
	htmx.ajax("POST", "/state", { target: "#board", swap: "innerHTML" });
});
</script>
</body>
</html>'
	return head
}

fn main() {
	mut app := App{}
	app.config.app_name = 'gomoku'
	app.config.close_timer_ms = 60_000
	app.config.window = vxui.WindowConfig{
		width:  640
		height: 900
		title:  'Gomoku — vxui'
	}
	app.config.multi_client = true

	vxui.run(mut app, default_page_html_file)!
}
