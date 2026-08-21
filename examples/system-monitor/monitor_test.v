module main

import math

fn test_parse_cpu_line() {
	snap := parse_cpu_line('cpu  100 0 100 700 100 0 0 0 0 0') or { panic('should parse') }
	assert snap.idle == 800 // idle 700 + iowait 100
	assert snap.total == 1000
	// `opt is none` is not supported by this V version; detect none via or-block flag
	mut garbage_is_none := false
	parse_cpu_line('garbage') or {
		garbage_is_none = true
		CpuSnapshot{}
	}
	assert garbage_is_none
}

fn test_cpu_percent() {
	prev := CpuSnapshot{
		idle:  800
		total: 1000
	}
	cur := CpuSnapshot{
		idle:  800
		total: 1200
	}
	// busy delta = 200 ; total delta = 200 -> all new time is busy
	pct := cpu_percent(prev, cur)
	assert pct > 99.9 && pct <= 100.0
	cur2 := CpuSnapshot{
		idle:  1100
		total: 1300
	}
	// busy delta = 300 - 300 = 0 ; total delta = 300 -> all new time is idle
	assert cpu_percent(prev, cur2) < 0.001
	// zero total delta -> -1 sentinel
	assert cpu_percent(cur, cur) == -1.0
}

fn test_parse_meminfo() {
	content := 'MemTotal:       16090520 kB\nMemFree:         1024 kB\nMemAvailable:    8045260 kB\nSwapTotal:             0 kB\n'
	mi := parse_meminfo(content)
	assert mi.total_kb == 16090520
	assert mi.avail_kb == 8045260
	// half available -> 50%
	assert math.abs(mem_percent(mi) - 50.0) < 0.01
}

fn test_meminfo_missing_fields_is_zero_safe() {
	mi := parse_meminfo('')
	assert mem_percent(mi) == 0.0
}
