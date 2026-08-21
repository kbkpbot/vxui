module main

import os

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
	if fields.len < 5 || fields[0] != 'cpu' {
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
