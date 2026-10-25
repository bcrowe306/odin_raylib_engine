package engine

// Sort_Stable sorts `data` by `less`, keeping equal items in their order:
// a bottom-up merge sort (O(n log n); a temp buffer as long as `data`) over
// insertion-sorted runs of 16. core:slice's stable_sort_by is an insertion
// sort, O(n^2): 3000 Y-sorted sprites took 4.6 ms a frame with it.
Sort_Stable :: proc(data: []$E, less: proc(a, b: E) -> bool) {
	RUN :: 16
	n := len(data)
	if n < 2 do return
	for lo := 0; lo < n; lo += RUN {
		hi := min(lo + RUN, n)
		for i in lo + 1 ..< hi {
			x := data[i]
			j := i
			for j > lo && less(x, data[j - 1]) {
				data[j] = data[j - 1]
				j -= 1
			}
			data[j] = x
		}
	}
	if n <= RUN do return
	src := data
	dst := make([]E, n, context.temp_allocator)
	for width := RUN; width < n; width *= 2 {
		for lo := 0; lo < n; lo += 2 * width {
			mid := min(lo + width, n)
			hi := min(lo + 2 * width, n)
			i, j, k := lo, mid, lo
			for i < mid && j < hi {
				// The right run's item goes first only when strictly less (stable).
				if less(src[j], src[i]) {
					dst[k] = src[j]
					j += 1
				} else {
					dst[k] = src[i]
					i += 1
				}
				k += 1
			}
			k += copy(dst[k:], src[i:mid])
			copy(dst[k:], src[j:hi])
		}
		src, dst = dst, src
	}
	if raw_data(src) != raw_data(data) do copy(data, src)
}
