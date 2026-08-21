module main

fn sample() []Employee {
	return [
		Employee{id: 1, name: 'Alice', dept: '研发', salary: 30000, hired: '2021-01-01', status: '在职'},
		Employee{id: 2, name: 'Bob', dept: '销售', salary: 20000, hired: '2022-02-01', status: '离职'},
		Employee{id: 3, name: ' Carol ', dept: '研发', salary: 35000, hired: '2020-03-01', status: '在职'},
		Employee{id: 4, name: 'Dave', dept: '人事', salary: 25000, hired: '2023-04-01', status: '在职'},
	]
}

fn test_filter_by_q_matches_name_and_dept() {
	rows, _ := apply_query(sample(), QueryParams{q: 'ali', page_size: 10})
	assert rows.len == 1
	assert rows[0].name.trim_space() == 'Alice'
	rows2, _ := apply_query(sample(), QueryParams{q: '研发', page_size: 10})
	assert rows2.len == 2
}

fn test_filter_by_status() {
	rows, _ := apply_query(sample(), QueryParams{status: '离职', page_size: 10})
	assert rows.len == 1
	assert rows[0].id == 2
}

fn test_sort_salary_desc_then_asc() {
	rows, _ := apply_query(sample(), QueryParams{sort_col: 'salary', desc: true, page_size: 10})
	assert rows[0].salary == 35000
	rows2, _ := apply_query(sample(), QueryParams{sort_col: 'salary', page_size: 10})
	assert rows2[0].salary == 20000
}

fn test_pagination_and_total() {
	mut all := []Employee{cap: 25}
	for i in 1 .. 26 {
		all << Employee{id: i, name: 'E${i}', dept: '研发', salary: i * 100,
			hired: '2020-01-01', status: '在职'}
	}
	page1, total := apply_query(all, QueryParams{page: 1, page_size: 20})
	assert total == 25
	assert page1.len == 20
	assert page1[0].id == 1
	page2, _ := apply_query(all, QueryParams{page: 2, page_size: 20})
	assert page2.len == 5
	assert page2[0].id == 21
}

fn test_default_params() {
	rows, _ := apply_query(sample(), QueryParams{})
	assert rows.len == 4 // 默认按 id 升序、不过滤
}
