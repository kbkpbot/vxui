module main

import math
import os
import time
import vxui
import x.json2 as vxjson

// Demonstrates: multi_client, broadcast, oob_update, get_client_count
// Backend samples CPU/RAM/load once per second and broadcasts OOB updates
// to every connected browser window.

const default_page_html_file = './ui/index.html'

// circumference of the SVG gauge rings (2 * pi * r, r = 52)
const ring_circumference = 326.73

struct CpuSnapshot {
pub:
	idle  u64
	total u64
}

struct MemInfo {
pub:
	total_kb u64
	avail_kb u64
}

fn parse_cpu_line(line string) ?CpuSnapshot {
	fields := line.split(' ').filter(it.len > 0)
	if fields.len < 6 || fields[0] != 'cpu' {
		return none
	}
	mut total := u64(0)
	for i := 1; i < fields.len; i++ {
		total += fields[i].u64()
	}
	idle := fields[4].u64() + fields[5].u64() // idle + iowait
	return CpuSnapshot{
		idle:  idle
		total: total
	}
}

fn cpu_percent(prev CpuSnapshot, cur CpuSnapshot) f64 {
	d_total := cur.total - prev.total
	if d_total == 0 {
		return -1.0
	}
	d_idle := cur.idle - prev.idle
	return f64(d_total - d_idle) / f64(d_total) * 100.0
}

fn parse_meminfo(content string) MemInfo {
	mut total_kb := u64(0)
	mut avail_kb := u64(0)
	for line in content.split('\n') {
		if line.starts_with('MemTotal:') {
			total_kb = field_kb(line)
		} else if line.starts_with('MemAvailable:') {
			avail_kb = field_kb(line)
		}
	}
	return MemInfo{
		total_kb: total_kb
		avail_kb: avail_kb
	}
}

// field_kb extracts the numeric kB value from a "/proc/meminfo" style line
fn field_kb(line string) u64 {
	for part in line.all_after(':').split(' ') {
		if part.len > 0 {
			return part.u64()
		}
	}
	return 0
}

fn mem_percent(m MemInfo) f64 {
	if m.total_kb == 0 || m.avail_kb >= m.total_kb {
		return 0.0
	}
	return f64(m.total_kb - m.avail_kb) / f64(m.total_kb) * 100.0
}

fn read_loadavg() f64 {
	content := os.read_file('/proc/loadavg') or { return 0.0 }
	return content.all_before(' ').f64()
}

struct App {
	vxui.Context
mut:
	history  []f64
	has_proc bool
	prev     CpuSnapshot
	mem      MemInfo
	load     f64
	cpu      f64
}

// start_sampler runs in its own goroutine; samples once per second and
// broadcasts an oob_update command with freshly rendered dashboard parts.
fn start_sampler(mut app &App) {
	time.sleep(1500 * time.millisecond) // let the WS server come up first
	app.has_proc = os.exists('/proc/stat')
	mut snap := read_cpu_snapshot()
	if s := snap {
		app.prev = s
	}
	for {
		app.sample_once()
		fragment := render_dashboard(mut app)
		payload := {'cmd': 'oob_update', 'html': fragment}
		app.broadcast(vxjson.encode(payload)) or {}
		time.sleep(1 * time.second)
	}
}

// read_cpu_snapshot wraps parse_cpu_line over the live /proc/stat head line
fn read_cpu_snapshot() ?CpuSnapshot {
	lines := os.read_lines('/proc/stat') or { return none }
	if lines.len == 0 {
		return none
	}
	return parse_cpu_line(lines[0])
}

fn (mut app App) sample_once() {
	app.load = read_loadavg()
	content := os.read_file('/proc/meminfo') or { '' }
	app.mem = parse_meminfo(content)

	cur := read_cpu_snapshot()
	if s := cur {
		pct := cpu_percent(app.prev, s)
		if pct >= 0 {
			app.cpu = pct
			app.history << pct
			if app.history.len > 60 {
				app.history.delete(0)
			}
		}
		app.prev = s
	} else {
		// simulated fallback (non-Linux): smooth sine wave around 40%
		t := time.now().unix() % 3600
		app.cpu = 40.0 + 30.0 * math.sin(f64(t) / 10.0)
		app.history << app.cpu
		if app.history.len > 60 {
			app.history.delete(0)
		}
	}
}

// gauge_svg renders one ring gauge as an OOB-swappable div
fn gauge_svg(id string, label string, pct f64, color string) string {
	clamped := math.min(math.max(pct, 0.0), 100.0)
	offset := ring_circumference * (1.0 - clamped / 100.0)
	return '<div id="gauge-${id}" hx-swap-oob="true" class="gauge">
		<svg viewBox="0 0 120 120">
			<circle class="ring-bg" cx="60" cy="60" r="52"/>
			<circle class="ring-fg" cx="60" cy="60" r="52" style="stroke:${color};stroke-dashoffset:${offset:.1f}"/>
		</svg>
		<div class="gauge-value">${clamped:.1f}%</div>
		<div class="gauge-label">${label}</div>
	</div>'
}

// history_svg renders the CPU% sparkline polyline
fn history_svg(history []f64) string {
	mut pts := ''
	w := 600.0
	h := 120.0
	step := if history.len > 1 { w / f64(history.len - 1) } else { w }
	for i, v in history {
		x := step * f64(i)
		y := h - h * v / 100.0
		pts += '${x:.1f},${y:.1f} '
	}
	label := if history.len > 0 { '${history.last():.1f}%' } else { '--' }
	return '<div id="history" hx-swap-oob="true" class="history">
		<div class="history-title">CPU 历史 <span>${label}</span></div>
		<svg viewBox="0 0 ${w:.0f} ${h:.0f}" preserveAspectRatio="none">
			<polyline fill="none" stroke="#38ef7d" stroke-width="2" points="${pts}"/>
		</svg>
	</div>'
}

fn render_dashboard(mut app &App) string {
	mut out := gauge_svg('cpu', 'CPU', app.cpu, '#38ef7d')
	out += gauge_svg('mem', '内存', mem_percent(app.mem), '#4fc3f7')
	out += gauge_svg('load', '负载×100', app.load * 100.0, '#ffb74d')
	out += history_svg(app.history)
	out += '<div id="clients" hx-swap-oob="true" class="clients">在线窗口：${app.get_client_count()}</div>'
	return out
}

fn main() {
	mut app := App{}

	app.config.app_name = 'system-monitor'
	app.config.multi_client = true
	app.config.close_timer_ms = 60000

	mut sampler_app := &app
	spawn start_sampler(mut sampler_app)

	vxui.run(mut app, default_page_html_file)!
}
