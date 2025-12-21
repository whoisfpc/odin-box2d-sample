package main

import enki "../odin-enkiTS"
import im "../odin-imgui"
import "base:intrinsics"
import "core:slice"
import b2 "vendor:box2d"
import "vendor:glfw"

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
	// todo: need destroy all tasks before set to zero
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
}

sample_context_save :: proc(ctx: ^Sample_Context) {

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

sample_keyboard :: proc(sample: ^Sample, key: i32) {

}
