module main

struct Board {
mut:
	cells [4][4]int
	one   [4]int
}

fn board_of(vals [][]int) [4][4]int {
	mut b := [4][4]int{}
	for r in 0 .. 4 {
		for c in 0 .. 4 {
			b[r][c] = vals[r][c]
		}
	}
	return b
}

fn row_of(vals []int) [4]int {
	mut r := [4]int{}
	for i in 0 .. 4 {
		r[i] = vals[i]
	}
	return r
}

fn main() {
	mut bd := Board{}

	// A: literal stored in a variable first, then passed — OK?
	v := [
		[0, 0, 0, 2],
		[0, 0, 0, 0],
		[0, 2, 0, 0],
		[0, 0, 0, 0],
	]
	bd.cells = board_of(v)
	println('A ok: ${bd.cells[0][3]}')

	// B: 1-D fixed array from []int literal
	bd.one = row_of([9, 8, 7, 6])
	println('B ok: ${bd.one[0]}')

	// C: assign to a LOCAL fixed array (not a struct field)
	mut local := board_of([
		[1, 0, 0, 0],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
	])
	println('C ok: ${local[0][0]}')
}
