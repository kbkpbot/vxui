module main

struct Board {
mut:
	cells [4][4]int
}

// [][]int in, fixed-size array out — the implicit literal conversion is
// where V 0.5.2's codegen goes wrong.
fn board_of(vals [][]int) [4][4]int {
	mut b := [4][4]int{}
	for r in 0 .. 4 {
		for c in 0 .. 4 {
			b[r][c] = vals[r][c]
		}
	}
	return b
}

fn main() {
	mut bd := Board{}
	bd.cells = board_of([
		[0, 0, 0, 2],
		[0, 0, 0, 0],
		[0, 2, 0, 0],
		[0, 0, 0, 0],
	])
	println(bd.cells[0][3])
}
