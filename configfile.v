module vxui

import x.json2
import os

// FileConfig is the serializable subset of Config that may be set from a JSON
// config file. Nested sections are kept as `map[string]json2.Any` so the file
// can carry extra/unknown fields without breaking the decoder. Only the fields
// recognised by apply_config_file are read; everything else is ignored.
pub struct FileConfig {
mut:
	display        map[string]json2.Any
	browser        map[string]json2.Any
	webview        map[string]json2.Any
	window         map[string]json2.Any
	dev            map[string]json2.Any
	token          string
	multi_client   ?bool
	evict_on_new   ?bool
	close_timer_ms ?int
}

// load_config_file reads and decodes a JSON config file into a FileConfig.
// Unknown fields are ignored; missing sections simply yield empty maps.
pub fn load_config_file(path string) !FileConfig {
	text := os.read_file(path) or { return error('cannot read config file: ${path}') }
	root := json2.decode[json2.Any](text) or {
		return error('invalid JSON in config file ${path}: ${err}')
	}
	mut fc := FileConfig{}
	m := root.as_map()
	if m.len > 0 {
		if v := m['display'] {
			d := v.as_map()
			if d.len > 0 {
				fc.display = d.clone()
			}
		}
		if v := m['browser'] {
			b := v.as_map()
			if b.len > 0 {
				fc.browser = b.clone()
			}
		}
		if v := m['webview'] {
			wv := v.as_map()
			if wv.len > 0 {
				fc.webview = wv.clone()
			}
		}
		if v := m['window'] {
			wn := v.as_map()
			if wn.len > 0 {
				fc.window = wn.clone()
			}
		}
		if v := m['dev'] {
			dv := v.as_map()
			if dv.len > 0 {
				fc.dev = dv.clone()
			}
		}
		if v := m['token'] {
			tok := v.str()
			if tok != '' {
				fc.token = tok
			}
		}
		if v := m['multi_client'] {
			fc.multi_client = v.bool()
		}
		if v := m['evict_on_new'] {
			fc.evict_on_new = v.bool()
		}
		if v := m['close_timer_ms'] {
			fc.close_timer_ms = v.int()
		}
	}
	return fc
}

// apply_config_file overlays a config file onto an existing Config. It is meant
// to be called BEFORE init()/new_display() so that the chosen backend and other
// settings take effect during startup. Code-set values not present in the file
// are preserved.
pub fn apply_config_file(mut cfg Config, path string) ! {
	fc := load_config_file(path) or { return err }

	if sid := fc.display['id'] {
		s := sid.str()
		if s != '' {
			cfg.display.id = s
		}
	}

	if fc.browser.len > 0 {
		b := fc.browser.clone()
		if ve := b['engine'] {
			e := ve.str()
			if e != '' {
				cfg.browser.engine = browser_engine_from_str(e)
			}
		}
		if vh := b['headless'] {
			cfg.browser.headless = vh.bool()
		}
		if vd := b['devtools'] {
			cfg.browser.devtools = vd.bool()
		}
		if vn := b['no_sandbox'] {
			cfg.browser.no_sandbox = vn.bool()
		}
		if vw := b['window_mode'] {
			wm := vw.str()
			if wm != '' {
				cfg.browser.window_mode = window_mode_from_str(wm)
			}
		}
		if vp := b['profile_dir'] {
			pd := vp.str()
			if pd != '' {
				cfg.browser.profile_dir = pd
			}
		}
		if vu := b['user_data_dir'] {
			ud := vu.str()
			if ud != '' {
				cfg.browser.user_data_dir = ud
			}
		}
		if vpr := b['preferred_path'] {
			pp := vpr.str()
			if pp != '' {
				cfg.browser.preferred_path = pp
			}
		}
		if vr := b['remote_debug_port'] {
			cfg.browser.remote_debug_port = vr.int()
		}
		if vc := b['custom_args'] {
			for it in vc.as_array() {
				cs := it.str()
				if cs != '' {
					cfg.browser.custom_args << cs
				}
			}
		}
	}

	if fc.window.len > 0 {
		wn := fc.window.clone()
		if vw := wn['width'] {
			cfg.window.width = vw.int()
		}
		if vh := wn['height'] {
			cfg.window.height = vh.int()
		}
		if vt := wn['title'] {
			t := vt.str()
			if t != '' {
				cfg.window.title = t
			}
		}
		if vx := wn['x'] {
			cfg.window.x = vx.int()
		}
		if vy := wn['y'] {
			cfg.window.y = vy.int()
		}
	}

	if fc.dev.len > 0 {
		if vd := fc.dev['auto_devtools'] {
			cfg.dev.auto_devtools = vd.bool()
		}
	}

	if fc.token != '' {
		cfg.token = fc.token
	}
	if mc := fc.multi_client {
		cfg.multi_client = mc
	}
	if eon := fc.evict_on_new {
		cfg.evict_on_new = eon
	}
	if ctm := fc.close_timer_ms {
		cfg.close_timer_ms = ctm
	}
}

fn browser_engine_from_str(s string) BrowserEngine {
	return match s {
		'auto' { .auto }
		'chrome' { .chrome }
		'firefox' { .firefox }
		'edge' { .edge }
		'brave' { .brave }
		'safari' { .safari }
		'system' { .system }
		else { .auto }
	}
}

fn window_mode_from_str(s string) WindowMode {
	return match s {
		'app' { .app }
		'kiosk' { .kiosk }
		'normal' { .normal }
		else { .app }
	}
}

// resolve_config_path finds the config file to apply, honouring (in order):
// 1. `--config <path>` / `--config=<path>` CLI args
// 2. the VXUI_CONFIG environment variable
// 3. ./vxui.json in the current working directory
// 4. ~/.vxui/config.json
// Returns an empty string when none is found.
fn resolve_config_path() string {
	for i, a in os.args {
		if a == '--config' && i + 1 < os.args.len {
			return os.args[i + 1]
		}
		if a.starts_with('--config=') {
			return a.after('--config=')
		}
	}
	env := os.getenv('VXUI_CONFIG')
	if env != '' {
		return env
	}
	cands := [
		os.join_path(os.getwd(), 'vxui.json'),
		os.join_path(os.home_dir(), '.vxui', 'config.json'),
	]
	for cand in cands {
		if os.exists(cand) {
			return cand
		}
	}
	return ''
}
