package engine

import "core:math/rand"
import "core:slice"
import "core:testing"

@(test)
test_sort_stable :: proc(t: ^testing.T) {
	Item :: struct {key, seq: int}
	less :: proc(a, b: Item) -> bool {return a.key < b.key}
	for n in ([]int{0, 1, 2, 15, 16, 17, 31, 33, 100, 1000, 4097}) {
		for keys in ([]int{3, 50, 1 << 30}) { // many / some / few equal keys
			a := make([]Item, n, context.temp_allocator)
			for &it, i in a do it = {int(rand.int31_max(i32(min(keys, 1 << 30)))), i}
			b := slice.clone(a, context.temp_allocator)
			Sort_Stable(a, less)
			slice.stable_sort_by(b, less) // the reference (insertion sort)
			testing.expectf(t, slice.equal(a, b), "n=%d keys=%d: differs from stable_sort_by", n, keys)
		}
	}
	free_all(context.temp_allocator)
}
