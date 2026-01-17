package main

import b2 "../odin-box2d"
import enki "../odin-enkiTS"
import im "../odin-imgui"
import "base:intrinsics"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:glfw"

@(private = "file")
SETTINGS_PATH :: "settings.json"

@(private = "file")
Settings :: struct {
	sample_index: i32,
	draw_shapes:  bool,
	draw_joints:  bool,
}

Sample_Context :: struct {
	window:               glfw.WindowHandle,
	camera:               Camera,
	draw:                 ^Draw,
	ui_scale:             f32, // 1.0
	hertz:                f32, // 60.0
	sub_step_count:       i32, // 4
	worker_count:         i32, // 1
	restart:              bool, // false
	pause:                bool, // false
	single_step:          bool, // false
	draw_counters:        bool, // false
	draw_profile:         bool, // false
	enable_warm_starting: bool, // true
	enable_continuous:    bool, // true
	enable_sleep:         bool, // true
	show_ui:              bool, // true


	// These are persisted
	sample_index:         i32,
	debug_draw:           b2.DebugDraw,
	regular_font:         ^im.Font,
	medium_font:          ^im.Font,
	large_font:           ^im.Font,
}

MAX_TASKS :: 64
MAX_THREADS :: 64

Sample :: struct {
	ctx:               ^Sample_Context,
	camera:            ^Camera,
	draw:              ^Draw,
	scheduler:         ^enki.TaskScheduler,
	tasks:             []^enki.TaskSet,
	task_count:        int,
	thread_count:      i32,

	// box2d
	mouse_body_id:     b2.BodyId,
	world_id:          b2.WorldId,
	mouse_joint_id:    b2.JointId,
	mouse_point:       b2.Vec2,
	mouse_force_scale: f32,
	step_count:        i32,
	max_profile:       b2.Profile,
	total_profile:     b2.Profile,
	text_line:         int,
	text_increment:    int,
	variant:           union {
		^BenchmarkBarrel24,
		^Weeble,
		^BodyType,
	},
}

Sample_Entry :: struct {
	category:   cstring,
	name:       cstring,
	create_fcn: sample_create_fcn_type,
}

sample_create_fcn_type :: #type proc(ctx: ^Sample_Context) -> ^Sample

g_sample_entries: [dynamic]Sample_Entry

register_sample :: proc(category, name: cstring, fcn: sample_create_fcn_type) {
	append(&g_sample_entries, Sample_Entry{category, name, fcn})
}

register_all_samples :: proc() {
	// todo: add all samples
	register_sample("Benchmark", "Barrel 2.4", BenchmarkBarrel24_create)
	register_sample("Bodies", "Weeble", Weeble_create)
	register_sample("Bodies", "Body Type", BodyType_create)
	slice.sort_by(g_sample_entries[:], proc(i, j: Sample_Entry) -> bool {
		if i.category != j.category {
			return i.category < j.category
		}
		return i.name < j.name
	})
}

sample_context_load :: proc(ctx: ^Sample_Context) {
	ctx.ui_scale = 1.0
	ctx.hertz = 60.0
	ctx.sub_step_count = 4
	ctx.worker_count = 1
	ctx.enable_warm_starting = true
	ctx.enable_continuous = true
	ctx.enable_sleep = true
	ctx.show_ui = true
	ctx.camera = camera_get_default()

	ctx.debug_draw = b2.DefaultDebugDraw()
	ctx.debug_draw.DrawPolygonFcn = DrawPolygonFcn
	ctx.debug_draw.DrawSolidPolygonFcn = DrawSolidPolygonFcn
	ctx.debug_draw.DrawCircleFcn = DrawCircleFcn
	ctx.debug_draw.DrawSolidCircleFcn = DrawSolidCircleFcn
	ctx.debug_draw.DrawSolidCapsuleFcn = DrawSolidCapsuleFcn
	ctx.debug_draw.DrawLineFcn = DrawLineFcn
	ctx.debug_draw.DrawTransformFcn = DrawTransformFcn
	ctx.debug_draw.DrawPointFcn = DrawPointFcn
	ctx.debug_draw.DrawStringFcn = DrawStringFcn
	ctx.debug_draw._context = ctx
	ctx.debug_draw.drawShapes = true
	ctx.debug_draw.drawJoints = true

	// load settings from file
	load_settings: {
		data, ok := os.read_entire_file_from_filename(SETTINGS_PATH)
		if !ok {
			fmt.eprintln("Failed to load the settings file!")
			break load_settings
		}
		defer delete(data) // Free the memory at the end

		settings: Settings
		unmarshal_err := json.unmarshal(data, &settings)
		if unmarshal_err != nil {
			fmt.eprintln("Failed to unmarshal the settings file!")
		}

		ctx.sample_index = settings.sample_index
		ctx.debug_draw.drawShapes = settings.draw_shapes
		ctx.debug_draw.drawJoints = settings.draw_joints
	}
}

@(private = "file")
DrawPolygonFcn :: proc "c" (vertices: [^]b2.Vec2, vertexCount: i32, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_polygon(sample_ctx.draw, vertices, vertexCount, color)
}

@(private = "file")
DrawSolidPolygonFcn :: proc "c" (
	transform: b2.Transform,
	vertices: [^]b2.Vec2,
	vertexCount: i32,
	radius: f32,
	color: b2.HexColor,
	ctx: rawptr,
) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_solid_polygon(sample_ctx.draw, transform, vertices, vertexCount, radius, color)
}

@(private = "file")
DrawCircleFcn :: proc "c" (center: b2.Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_circle(sample_ctx.draw, center, radius, color)
}

@(private = "file")
DrawSolidCircleFcn :: proc "c" (transform: b2.Transform, radius: f32, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_solid_circle(sample_ctx.draw, transform, radius, color)
}

@(private = "file")
DrawSolidCapsuleFcn :: proc "c" (p1, p2: b2.Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_solid_capsule(sample_ctx.draw, p1, p2, radius, color)
}

@(private = "file")
DrawLineFcn :: proc "c" (p1, p2: b2.Vec2, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_line(sample_ctx.draw, p1, p2, color)
}

@(private = "file")
DrawTransformFcn :: proc "c" (transform: b2.Transform, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_transform(sample_ctx.draw, transform, 1.0)
}

@(private = "file")
DrawPointFcn :: proc "c" (p: b2.Vec2, size: f32, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_point(sample_ctx.draw, p, size, color)
}

@(private = "file")
DrawStringFcn :: proc "c" (p: b2.Vec2, s: cstring, color: b2.HexColor, ctx: rawptr) {
	sample_ctx := cast(^Sample_Context)ctx
	draw_world_string(sample_ctx.draw, &sample_ctx.camera, p, color, string(s))
}

sample_context_save :: proc(ctx: ^Sample_Context) {
	settings := Settings {
		sample_index = ctx.sample_index,
		draw_shapes  = ctx.debug_draw.drawShapes,
		draw_joints  = ctx.debug_draw.drawJoints,
	}

	json_data, err := json.marshal(
	settings,
	{
		// Adds indentation etc
		pretty         = true,

		// Output enum member names instead of numeric value.
		use_enum_names = true,
	},
	)

	if err != nil {
		fmt.eprintfln("Unable to marshal JSON for sample_context_save: %v", err)
		return
	}
	defer delete(json_data)

	werr := os.write_entire_file_or_err(SETTINGS_PATH, json_data)

	if werr != nil {
		fmt.eprintfln("Unable to write file: %v", werr)
	}
}

sample_base_create :: proc(ctx: ^Sample_Context, sample: ^Sample) {
	sample.ctx = ctx
	sample.camera = &ctx.camera
	sample.draw = ctx.draw

	sample.scheduler = enki.NewTaskScheduler()
	enki.InitTaskSchedulerNumThreads(sample.scheduler, u32(ctx.worker_count))
	sample.tasks = make([]^enki.TaskSet, MAX_TASKS)
	for i in 0 ..< MAX_TASKS {
		// crate tasks
		wrapper := new(Task_Wrapper)
		sample_task := enki.CreateTaskSet(sample.scheduler, task_wrapper_func)
		enki.SetArgsTaskSet(sample_task, wrapper)
		sample.tasks[i] = sample_task
	}
	sample.task_count = 0
	sample.thread_count = 1 + ctx.worker_count

	sample.world_id = b2.nullWorldId

	sample.text_increment = 26
	sample.text_line = sample.text_increment
	sample.mouse_joint_id = b2.nullJointId

	sample.step_count = 0
	sample.mouse_body_id = b2.nullBodyId
	sample.mouse_point = {0, 0}
	sample.mouse_force_scale = 100

	sample_create_world(sample)
}

sample_base_destroy :: proc(sample: ^Sample) {
	if b2.IS_NON_NULL(sample.world_id) {
		b2.DestroyWorld(sample.world_id)
	}
	for i in 0 ..< sample.task_count {
		params := enki.GetParamsTaskSet(sample.tasks[i])
		wrapper := cast(^Task_Wrapper)params.pArgs
		free(wrapper)
		enki.DeleteTaskSet(sample.scheduler, sample.tasks[i])
	}
	enki.DeleteTaskScheduler(sample.scheduler)
	delete(sample.tasks)
}

sample_generic_create :: proc(ctx: ^Sample_Context, $T: typeid) -> ^T where intrinsics.type_is_struct(T),
	intrinsics.type_has_field(T, "variant"),
	intrinsics.type_has_field(T, "sample"),
	intrinsics.type_field_type(T, "sample") == Sample {
	sample := new(T)
	sample.variant = sample
	sample_base_create(ctx, &sample.sample)
	return sample
}

sample_variant_destroy :: proc(sample: ^Sample) {
	switch v in sample.variant {
	case ^BenchmarkBarrel24:
		BenchmarkBarrel24_destroy(v)
	case ^Weeble:
		Weeble_destroy(v)
	case ^BodyType:
		BodyType_destroy(v)
	case:
		panic("unimplement destroy")
	}
}

sample_create_world :: proc(sample: ^Sample) {
	if b2.IS_NON_NULL(sample.world_id) {
		b2.DestroyWorld(sample.world_id)
		sample.world_id = b2.nullWorldId
	}

	world_def := b2.DefaultWorldDef()
	world_def.workerCount = sample.ctx.worker_count
	world_def.enqueueTask = enqueue_task
	world_def.finishTask = finish_task
	world_def.userTaskContext = sample
	world_def.enableSleep = sample.ctx.enable_sleep

	// todo experimental
	// worldDef.enableContactSoftening = true;
	sample.world_id = b2.CreateWorld(world_def)
}

Task_Wrapper :: struct {
	task:        b2.TaskCallback,
	taskContext: rawptr,
}

@(private = "file")
task_wrapper_func :: proc "c" (start_: u32, end_: u32, threadnum_: u32, pArgs_: rawptr) {
	wrapper := cast(^Task_Wrapper)pArgs_
	wrapper.task(i32(start_), i32(end_), threadnum_, wrapper.taskContext)
}

@(private = "file")
enqueue_task :: proc "c" (
	task: b2.TaskCallback, // must use enki.TaskExecuteRange, b2.TaskCallback cause compiler crash!
	itemCount: i32,
	minRange: i32,
	taskContext: rawptr,
	userContext: rawptr,
) -> rawptr {

	sample := cast(^Sample)userContext
	if sample.task_count < MAX_TASKS {
		sample_task := sample.tasks[sample.task_count]
		enki.SetSetSizeTaskSet(sample_task, u32(itemCount))
		enki.SetMinRangeTaskSet(sample_task, u32(minRange))
		params := enki.GetParamsTaskSet(sample_task)
		// can not juse assign task to enki Task, otherwise it will let odin compiler crash!
		// so create a wrapper to call real b2.TaskCallback
		wrapper := cast(^Task_Wrapper)params.pArgs
		wrapper.taskContext = taskContext
		wrapper.task = task

		enki.AddTaskSet(sample.scheduler, sample_task)
		sample.task_count += 1
		return sample_task
	} else {
		// This is not fatal but the maxTasks should be increased
		assert_contextless(false)
		task(0, itemCount, 0, taskContext)
		return nil
	}
}

@(private = "file")
finish_task :: proc "c" (taskPtr: rawptr, userContext: rawptr) {
	if taskPtr != nil {
		sample_task := cast(^enki.TaskSet)taskPtr
		sample := cast(^Sample)userContext
		enki.WaitForTaskSet(sample.scheduler, sample_task)
	}
}


sample_reset_text :: proc(sample: ^Sample) {
	sample.text_line = sample.text_increment
}

sample_draw_text_line :: proc(sample: ^Sample, format: string, args: ..any) {
	sample_draw_colored_text_line(sample, .White, format, ..args)
}

sample_draw_colored_text_line :: proc(sample: ^Sample, color: b2.HexColor, format: string, args: ..any) {
	if !sample.ctx.show_ui {
		return
	}
	draw_screen_string(sample.draw, 5, f32(sample.text_line), color, format, ..args)
	sample.text_line += sample.text_increment
}

sample_reset_profile :: proc "contextless" (sample: ^Sample) {
	sample.total_profile = {}
	sample.max_profile = {}
	sample.step_count = 0
}

sample_base_step :: proc(sample: ^Sample) {
	ctx := sample.ctx
	time_step := ctx.hertz > 0 ? 1.0 / ctx.hertz : 0
	if ctx.pause {
		if ctx.single_step {
			ctx.single_step = false
		} else {
			time_step = 0
		}

		if ctx.show_ui {
			sample_draw_text_line(sample, "****PAUSED****")
			sample.text_line += sample.text_increment
		}
	}

	if b2.IS_NON_NULL(sample.mouse_joint_id) && !b2.Joint_IsValid(sample.mouse_joint_id) {
		// The world or attached body was destroyed.
		sample.mouse_joint_id = b2.nullJointId
		if b2.IS_NON_NULL(sample.mouse_body_id) {
			b2.DestroyBody(sample.mouse_body_id)
			sample.mouse_body_id = b2.nullBodyId
		}
	}

	if b2.IS_NON_NULL(sample.mouse_body_id) && time_step > 0 {
		b2.Body_SetTargetTransform(sample.mouse_body_id, {sample.mouse_point, b2.Rot_identity}, time_step)
	}

	ctx.debug_draw.drawingBounds = get_view_bounds(&ctx.camera)

	b2.World_EnableSleeping(sample.world_id, ctx.enable_sleep)
	b2.World_EnableWarmStarting(sample.world_id, ctx.enable_warm_starting)
	b2.World_EnableContinuous(sample.world_id, ctx.enable_continuous)

	b2.World_Step(sample.world_id, time_step, ctx.sub_step_count)
	sample.task_count = 0

	b2.World_Draw(sample.world_id, &ctx.debug_draw)

	if time_step > 0 {
		sample.step_count += 1
	}

	if ctx.draw_counters {
		s := b2.World_GetCounters(sample.world_id)
		sample_draw_text_line(
			sample,
			"bodies/shapes/contacts/joints = %d/%d/%d/%d",
			s.bodyCount,
			s.shapeCount,
			s.contactCount,
			s.jointCount,
		)
		sample_draw_text_line(sample, "islands/tasks = %d/%d", s.islandCount, s.taskCount)
		sample_draw_text_line(sample, "tree height static/movable = %d/%d", s.staticTreeHeight, s.treeHeight)

		total_count := 0
		color_count := size_of(s.colorCounts) / size_of(s.colorCounts[0])
		sb, err := strings.builder_make()
		assert(err == nil)
		defer strings.builder_destroy(&sb)
		strings.write_string(&sb, "colors: ")
		for i in 0 ..< color_count {
			strings.write_int(&sb, int(s.colorCounts[i]))
			strings.write_rune(&sb, '/')
			total_count += int(s.colorCounts[i])
		}
		strings.write_rune(&sb, '[')
		strings.write_int(&sb, total_count)
		strings.write_rune(&sb, ']')
		color_counts_str := strings.to_string(sb)
		sample_draw_text_line(sample, color_counts_str)
		sample_draw_text_line(sample, "stack allocator size = %d K", s.stackUsed / 1024)
		sample_draw_text_line(sample, "total allocation = %d K", s.byteCount / 1024)
	}

	// todo
	// Track maximum profile times
	//m_context->drawProfile
}

sample_variant_step :: proc(sample: ^Sample) {
	#partial switch v in sample.variant {
	case ^Weeble:
		Weeble_step(v)
	case ^BodyType:
		BodyType_step(v)
	case:
		sample_base_step(sample)
	}
}

sample_variant_update_gui :: proc(sample: ^Sample) {
	#partial switch v in sample.variant {
	case ^Weeble:
		Weeble_update_gui(v)
	case ^BodyType:
		BodyType_update_gui(v)
	}
}

sample_variant_keyboard :: proc(sample: ^Sample, key: i32) {

}

Query_Context :: struct {
	point:   b2.Vec2,
	body_id: b2.BodyId,
}

query_callback :: proc "c" (shapeId: b2.ShapeId, ctx: rawptr) -> bool {
	query_ctx := cast(^Query_Context)ctx

	body_id := b2.Shape_GetBody(shapeId)
	body_type := b2.Body_GetType(body_id)
	if body_type != .dynamicBody {
		// continue query
		return true
	}

	overlap := b2.Shape_TestPoint(shapeId, query_ctx.point)
	if overlap {
		// found shape
		query_ctx.body_id = body_id
		return false
	}

	return true
}

sample_base_mouse_down :: proc "contextless" (sample: ^Sample, p: [2]f32, button, mods: i32) {
	if b2.IS_NON_NULL(sample.mouse_joint_id) {
		return
	}

	if button == glfw.MOUSE_BUTTON_1 {
		// Make a small box.
		box: b2.AABB
		d := b2.Vec2{0.001, 0.001}
		box.lowerBound = p - d
		box.upperBound = p + d

		sample.mouse_point = p

		// Query the world for overlapping shapes.
		query_ctx := Query_Context{p, b2.nullBodyId}
		_ = b2.World_OverlapAABB(sample.world_id, box, b2.DefaultQueryFilter(), query_callback, &query_ctx)

		if b2.IS_NON_NULL(query_ctx.body_id) {
			bodyDef := b2.DefaultBodyDef()
			bodyDef.type = .kinematicBody
			bodyDef.position = sample.mouse_point
			bodyDef.enableSleep = false
			sample.mouse_body_id = b2.CreateBody(sample.world_id, bodyDef)

			jointDef := b2.DefaultMotorJointDef()
			jointDef.base.bodyIdA = sample.mouse_body_id
			jointDef.base.bodyIdB = query_ctx.body_id
			jointDef.base.localFrameB.p = b2.Body_GetLocalPoint(query_ctx.body_id, p)
			jointDef.linearHertz = 7.5
			jointDef.linearDampingRatio = 1.0

			massData := b2.Body_GetMassData(query_ctx.body_id)
			g := b2.Length(b2.World_GetGravity(sample.world_id))
			mg := massData.mass * g

			jointDef.maxSpringForce = sample.mouse_force_scale * mg

			if massData.mass > 0.0 {
				// This acts like angular friction
				lever := math.sqrt(massData.rotationalInertia / massData.mass)
				jointDef.maxVelocityTorque = 0.25 * lever * mg
			}

			sample.mouse_joint_id = b2.CreateMotorJoint(sample.world_id, jointDef)
		}
	}
}

sample_variant_mouse_down :: proc "contextless" (sample: ^Sample, p: [2]f32, button, mods: i32) {
	#partial switch v in sample.variant {
	case:
		sample_base_mouse_down(sample, p, button, mods)
	}
}

sample_base_mouse_up :: proc "contextless" (sample: ^Sample, p: [2]f32, button: i32) {
	if b2.IS_NON_NULL(sample.mouse_joint_id) && button == glfw.MOUSE_BUTTON_1 {
		b2.DestroyJoint(sample.mouse_joint_id, true)
		sample.mouse_joint_id = b2.nullJointId

		b2.DestroyBody(sample.mouse_body_id)
		sample.mouse_body_id = b2.nullBodyId
	}
}

sample_variant_mouse_up :: proc "contextless" (sample: ^Sample, p: [2]f32, button: i32) {
	#partial switch v in sample.variant {
	case:
		sample_base_mouse_up(sample, p, button)
	}
}

sample_base_mouse_move :: proc "contextless" (sample: ^Sample, p: [2]f32) {
	if !b2.Joint_IsValid(sample.mouse_joint_id) {
		// The world or attached body was destroyed.
		sample.mouse_joint_id = b2.nullJointId
	}
	sample.mouse_point = p
}

sample_variant_mouse_move :: proc "contextless" (sample: ^Sample, p: [2]f32) {
	#partial switch v in sample.variant {
	case:
		sample_base_mouse_move(sample, p)
	}
}
