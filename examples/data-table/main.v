module main

import vxui
import x.json2

// Demonstrates: parameters handling, advanced hx-trigger, verb attribute routing

pub struct Employee {
pub:
	id     int
	name   string
	dept   string
	salary int
	hired  string
	status string
}

pub struct QueryParams {
pub mut:
	q         string
	status    string
	sort_col  string
	desc      bool
	page      int
	page_size int
}

// norm fills defaults for unset fields
fn norm(p QueryParams) QueryParams {
	mut q := p
	if q.page < 1 {
		q.page = 1
	}
	if q.page_size < 1 {
		q.page_size = 20
	}
	if q.sort_col !in ['id', 'name', 'dept', 'salary', 'hired', 'status'] {
		q.sort_col = 'id'
	}
	q.q = q.q.trim_space().to_lower()
	return q
}

// apply_query filters, sorts and paginates. Returns current-page rows and the
// filtered total count.
fn apply_query(rows []Employee, p QueryParams) ([]Employee, int) {
	q := norm(p)
	mut filtered := rows.filter(it.name.to_lower().contains(q.q) || it.dept.contains(q.q))
	if q.status != '' {
		filtered = filtered.filter(it.status == q.status)
	}
	match q.sort_col {
		'salary' { filtered.sort(a.salary < b.salary) }
		'name' { filtered.sort(a.name.to_lower() < b.name.to_lower()) }
		'dept' { filtered.sort(a.dept < b.dept) }
		'hired' { filtered.sort(a.hired < b.hired) }
		'status' { filtered.sort(a.status < b.status) }
		else { filtered.sort(a.id < b.id) }
	}
	if q.desc {
		filtered.reverse_in_place()
	}
	start := (q.page - 1) * q.page_size
	if start >= filtered.len {
		return []Employee{}, filtered.len
	}
	mut end := start + q.page_size
	if end > filtered.len {
		end = filtered.len
	}
	return filtered[start..end], filtered.len
}

const departments = ['研发', '销售', '人事', '财务', '运营']

const statuses = ['在职', '在职', '在职', '休假', '离职']

// gen_rows deterministically generates n employees
fn gen_rows(n int) []Employee {
	mut rows := []Employee{cap: n}
	names := ['伟', '芳', '娜', '敏', '静', '强', '磊', '洋', '勇', '艳', '杰', '涛']
	surnames := ['王', '李', '张', '刘', '陈', '杨', '赵', '黄']
	for i in 1 .. n + 1 {
		name := surnames[i % surnames.len] + names[(i * 7) % names.len]
		y := 2018 + i % 8
		m := 1 + i % 12
		d := 1 + i % 28
		rows << Employee{
			id:     i
			name:   name
			dept:   departments[i % departments.len]
			salary: 12000 + (i * 937) % 38000
			hired:  '${y}-${m:02}-${d:02}'
			status: statuses[i % statuses.len]
		}
	}
	return rows
}

struct TableApp {
	vxui.Context
mut:
	rows []Employee
}

// esc escapes text for safe embedding into HTML attributes and JSON payloads
fn esc(s string) string {
	mut out := s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
	out = out.replace('"', '&quot;').replace("'", '&#39;')
	return out
}

// vals_json builds the hx-vals payload carrying the full query state
fn vals_json(page int, p QueryParams) string {
	dir := if p.desc { 'desc' } else { 'asc' }
	return '{"page":${page},"q":"${esc(p.q)}","status":"${esc(p.status)}","sort":"${esc(p.sort_col)}","dir":"${dir}"}'
}

// qp_from_message parses QueryParams out of request parameters
fn qp_from_message(message map[string]json2.Any) QueryParams {
	mut p := QueryParams{}
	if params := message['parameters'] {
		pm := params.as_map()
		if v := pm['q'] { p.q = v.str() }
		if v := pm['status'] { p.status = v.str() }
		if v := pm['sort'] { p.sort_col = v.str() }
		if v := pm['dir'] { p.desc = v.str() == 'desc' }
		if v := pm['page'] { p.page = v.str().int() }
	}
	return p
}

// render_table renders tbody content for given page rows plus pager OOB
fn render_table(page_rows []Employee, total int, p QueryParams) string {
	max_page := if total == 0 { 1 } else { (total + p.page_size - 1) / p.page_size }
	mut trs := ''
	for r in page_rows {
		tag_cls := if r.status == '在职' { 'ok' } else { 'off' }
		trs += '<tr><td>${r.id}</td><td>${r.name}</td><td>${r.dept}</td><td>${r.salary}</td><td>${r.hired}</td><td><span class="tag ${tag_cls}">${r.status}</span></td></tr>'
	}
	prev_disabled := if p.page <= 1 { ' disabled' } else { '' }
	next_disabled := if p.page >= max_page { ' disabled' } else { '' }
	pager := '<div id="pager" hx-swap-oob="true">' +
		'<button hx-post="/query" hx-vals=\'' + vals_json(p.page - 1, p) + '\'' + prev_disabled + '>上一页</button>' +
		'<span>第 ${p.page} / ${max_page} 页 · 共 ${total} 条</span>' +
		'<button hx-post="/query" hx-vals=\'' + vals_json(p.page + 1, p) + '\'' + next_disabled + '>下一页</button>' +
		'</div>'
	return '<tbody id="tbody-zone" hx-swap-oob="innerHTML">' + trs + '</tbody>' + pager
}

@['/query']
fn (mut app TableApp) query(message map[string]json2.Any) string {
	p := qp_from_message(message)
	page_rows, total := apply_query(app.rows, p)
	return render_table(page_rows, total, p)
}

@['/reset-sort']
fn (mut app TableApp) reset_sort(_ map[string]json2.Any) string {
	p := QueryParams{page: 1}
	page_rows, total := apply_query(app.rows, p)
	return render_table(page_rows, total, p)
}

fn main() {
	mut app := TableApp{}
	app.rows = gen_rows(200)
	app.config.app_name = 'data-table'
	app.config.close_timer_ms = 60000
	vxui.run(mut app, './ui/index.html')!
}
