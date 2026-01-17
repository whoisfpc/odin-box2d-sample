package main

import b2 "../odin-box2d"
import im "../odin-imgui"

BodyType :: struct {
	using sample:       Sample,
	attachmentId:       b2.BodyId,
	secondAttachmentId: b2.BodyId,
	platformId:         b2.BodyId,
	touchingBodyId:     b2.BodyId,
	floatingBodyId:     b2.BodyId,
	type:               b2.BodyType,
	speed:              f32,
	isEnabled:          bool,
}

BodyType_create :: proc(ctx: ^Sample_Context) -> ^Sample {
	sample := sample_generic_create(ctx, BodyType)

	if ctx.restart == false {
		ctx.camera.center = {0.8, 6.4}
		ctx.camera.zoom = 25 * 0.4
	}

	sample.type = .dynamicBody
	sample.isEnabled = true

	ground_id := b2.nullBodyId
	{
		body_def := b2.DefaultBodyDef()
		body_def.name = "ground"
		ground_id = b2.CreateBody(sample.world_id, body_def)

		segment := b2.Segment{b2.Vec2{-20, 0}, b2.Vec2{20, 0}}
		shape_def := b2.DefaultShapeDef()
		_ = b2.CreateSegmentShape(ground_id, shape_def, segment)
	}

	// Define attachment
	{
		body_def := b2.DefaultBodyDef()
		body_def.type = .dynamicBody
		body_def.position = {-2, 3}
		body_def.name = "attach1"
		sample.attachmentId = b2.CreateBody(sample.world_id, body_def)

		box := b2.MakeBox(0.5, 2)
		shape_def := b2.DefaultShapeDef()
		shape_def.density = 1.0
		_ = b2.CreatePolygonShape(sample.attachmentId, shape_def, box)
	}

	// Define second attachment
	{
		body_def := b2.DefaultBodyDef()
		body_def.type = sample.type
		body_def.isEnabled = sample.isEnabled
		body_def.position = {3, 3}
		body_def.name = "attach2"
		sample.secondAttachmentId = b2.CreateBody(sample.world_id, body_def)

		box := b2.MakeBox(0.5, 2)
		shape_def := b2.DefaultShapeDef()
		shape_def.density = 1.0
		_ = b2.CreatePolygonShape(sample.secondAttachmentId, shape_def, box)
	}

	// Define platform
	// {
	// 	body_def := b2.DefaultBodyDef()
	// 	body_def.type = sample.type
	// 	body_def.isEnabled = sample.isEnabled
	// 	body_def.position = {-4, 5}
	// 	body_def.name = "platform"
	// 	sample.platformId = b2.CreateBody(sample.world_id, body_def)

	// 	box := b2.MakeOffsetBox(0.5, 4, {4.0, 0}, b2.MakeRot(0.5 * b2.PI))

	// 	shape_def := b2.DefaultShapeDef()
	// 	shape_def.density = 2.0
	// 	_ = b2.CreatePolygonShape(sample.platformId, shape_def, box)

	// 	revolute_def := b2.DefaultRevoluteJointDef()
	// 	pivot := b2.Vec2{-2, 5}
	// }

	// todo: other bodies

	// Create a separate floating body
	{
		body_def := b2.DefaultBodyDef()
		body_def.type = sample.type
		body_def.isEnabled = sample.isEnabled
		body_def.position = {-8, 12}
		body_def.gravityScale = 0.0
		body_def.name = "floater"
		sample.floatingBodyId = b2.CreateBody(sample.world_id, body_def)

		circle := b2.Circle{{0, 0.5}, 0.25}

		shape_def := b2.DefaultShapeDef()
		shape_def.density = 2.0
		_ = b2.CreateCircleShape(sample.floatingBodyId, shape_def, circle)
	}

	return sample
}

BodyType_update_gui :: proc(sample: ^BodyType) {
	// ctx := sample.ctx
}

BodyType_step :: proc(sample: ^BodyType) {
	// Drive the kinematic body.
	if sample.type == .kinematicBody {
		p := b2.Body_GetPosition(sample.platformId)
		v := b2.Body_GetLinearVelocity(sample.platformId)

		if (p.x < -14.0 && v.x < 0.0) || (p.x > 6.0 && v.x > 0.0) {
			v.x = -v.x
			b2.Body_SetLinearVelocity(sample.platformId, v)
		}
	}

	sample_base_step(sample)
}

BodyType_destroy :: proc(sample: ^BodyType) {
	sample_base_destroy(sample)
	free(sample)
}

Weeble :: struct {
	using sample:        Sample,
	weeble_id:           b2.BodyId,
	explosion_position:  b2.Vec2,
	explosion_radius:    f32,
	explosion_magnitude: f32,
}

@(private = "file")
friction_callback :: proc "c" (frictionA: f32, userMaterialIdA: u64, frictionB: f32, userMaterialIdB: u64) -> f32 {
	return 0.1
}

@(private = "file")
restitution_callback :: proc "c" (
	restitutionA: f32,
	userMaterialIdA: u64,
	restitutionB: f32,
	userMaterialIdB: u64,
) -> f32 {
	return 1.0
}

Weeble_create :: proc(ctx: ^Sample_Context) -> ^Sample {
	sample := sample_generic_create(ctx, Weeble)

	if ctx.restart == false {
		ctx.camera.center = {2.3, 10.0}
		ctx.camera.zoom = 25 * 0.5
	}

	// Test friction and restitution callbacks
	b2.World_SetFrictionCallback(sample.world_id, friction_callback)
	b2.World_SetRestitutionCallback(sample.world_id, restitution_callback)

	ground_id := b2.nullBodyId
	{
		body_def := b2.DefaultBodyDef()
		ground_id = b2.CreateBody(sample.world_id, body_def)

		segment := b2.Segment{b2.Vec2{-20, 0}, b2.Vec2{20, 0}}
		shape_def := b2.DefaultShapeDef()
		_ = b2.CreateSegmentShape(ground_id, shape_def, segment)
	}

	// Build weeble
	{
		body_def := b2.DefaultBodyDef()
		body_def.type = .dynamicBody
		body_def.position = {0, 3}
		body_def.rotation = b2.MakeRot(0.25 * b2.PI)
		sample.weeble_id = b2.CreateBody(sample.world_id, body_def)

		capsule := b2.Capsule{{0.0, -1.0}, {0.0, 1.0}, 1}
		shape_def := b2.DefaultShapeDef()
		_ = b2.CreateCapsuleShape(sample.weeble_id, shape_def, capsule)

		mass := b2.Body_GetMass(sample.weeble_id)
		inertia_tensor := b2.Body_GetRotationalInertia(sample.weeble_id)

		offset: f32 = 1.5
		// See: https://en.wikipedia.org/wiki/Parallel_axis_theorem
		inertia_tensor += mass * (offset * offset)

		mass_data := b2.MassData{mass, {0, -offset}, inertia_tensor}
		b2.Body_SetMassData(sample.weeble_id, mass_data)
	}

	sample.explosion_position = {0, 0}
	sample.explosion_radius = 2.0
	sample.explosion_magnitude = 8.0

	return sample
}

Weeble_update_gui :: proc(sample: ^Weeble) {
	ctx := sample.ctx

	font_size := im.GetFontSize()
	height :: 120
	im.SetNextWindowPos({0.5 * font_size, sample.camera.height - height - 2 * font_size}, .Once)
	im.SetNextWindowSize({200.0, height})
	im.Begin("Weeble", nil, {.NoMove + .NoResize})
	if im.Button("Teleport") {
		b2.Body_SetTransform(sample.weeble_id, {0, 5}, b2.MakeRot(0.05 * b2.PI))
	}

	if im.Button("Explode") {
		def := b2.DefaultExplosionDef()
		def.position = sample.explosion_position
		def.radius = sample.explosion_radius
		def.falloff = 0.1
		def.impulsePerLength = sample.explosion_magnitude
		b2.World_Explode(sample.world_id, def)
	}
	im.PushItemWidth(100.0)

	im.SliderFloat("Magnitude", &sample.explosion_magnitude, -100, 100, "%.1f")

	im.PopItemWidth()
	im.End()
}

Weeble_step :: proc(sample: ^Weeble) {
	sample_base_step(sample)
	ctx := sample.ctx

	draw_circle(sample.draw, sample.explosion_position, sample.explosion_radius, .Azure)
	// This shows how to get the velocity of a point on a body
	local_point := b2.Vec2{0, 2}
	world_point := b2.Body_GetWorldPoint(sample.weeble_id, local_point)

	v1 := b2.Body_GetLocalPointVelocity(sample.weeble_id, local_point)
	v2 := b2.Body_GetWorldPointVelocity(sample.weeble_id, world_point)

	offset := b2.Vec2{0.05, 0.0}
	draw_line(sample.draw, world_point, world_point + v1, .Red)
	draw_line(sample.draw, world_point + offset, world_point + offset + v2, .Green)
}

Weeble_destroy :: proc(sample: ^Weeble) {
	sample_base_destroy(sample)
	free(sample)
}
