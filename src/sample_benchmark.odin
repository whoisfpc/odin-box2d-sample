package main

BenchmarkBarrel24 :: struct {
	using sample: Sample,
}

BenchmarkBarrel24_create :: proc(ctx: ^Sample_Context) -> ^Sample {
	sample := new(BenchmarkBarrel24)
	sample.variant = sample
	sample_base_create(ctx, sample)
	// TODO: fill content

	return sample
}
