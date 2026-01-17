package main

import b2 "../odin-box2d"

// This is used to compare performance with Box2D v2.4
BenchmarkBarrel24 :: struct {
	using sample: Sample,
}

BenchmarkBarrel24_create :: proc(ctx: ^Sample_Context) -> ^Sample {
	sample := sample_generic_create(ctx, BenchmarkBarrel24)

	if ctx.restart == false {
		ctx.camera.center = {8, 53}
		ctx.camera.zoom = 25 * 2.35
	}

	{
		ground_size :: 25
		body_def := b2.DefaultBodyDef()
		ground_id := b2.CreateBody(sample.world_id, body_def)

		box := b2.MakeBox(ground_size, 1.2)
		shape_def := b2.DefaultShapeDef()
		_ = b2.CreatePolygonShape(ground_id, shape_def, box)

		body_def.rotation = b2.MakeRot(0.5 * b2.PI)
		body_def.position = {ground_size, 2.0 * ground_size}
		ground_id = b2.CreateBody(sample.world_id, body_def)

		box = b2.MakeBox(2.0 * ground_size, 1.2)
		_ = b2.CreatePolygonShape(ground_id, shape_def, box)

		body_def.position = {-ground_size, 2.0 * ground_size}
		ground_id = b2.CreateBody(sample.world_id, body_def)
		_ = b2.CreatePolygonShape(ground_id, shape_def, box)
	}

	NUM :: 26

	rad: f32 = 0.5
	shift: f32 = rad * 2.0
	centerx := shift * NUM / 2.0
	centery := shift / 2.0

	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody

	shape_def := b2.DefaultShapeDef()
	shape_def.density = 1
	shape_def.material.friction = 0.5

	cuboid := b2.MakeSquare(0.5)

	NUM_J :: 5

	for i in 0 ..< NUM {
		x := f32(i) * shift - centerx
		for j in 0 ..< NUM_J {
			y := f32(j) * shift + centery + 2.0

			body_def.position = {x, y}
			body_id := b2.CreateBody(sample.world_id, body_def)
			_ = b2.CreatePolygonShape(body_id, shape_def, cuboid)
		}
	}

	return sample
}

BenchmarkBarrel24_destroy :: proc(sample: ^BenchmarkBarrel24) {
	sample_base_destroy(sample)
	free(sample)
}
