module main

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
