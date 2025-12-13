package main

import im "../odin-imgui"
import b2 "vendor:box2d"
import "vendor:glfw"

Sample_Context :: struct {
	window:       glfw.WindowHandle,
	camera:       Camera,
	ui_scale:     f32,
	worker_count: i32,


	// These are persisted
	sample_index: i32,
	debug_draw:   b2.DebugDraw,
	regular_font: ^im.Font,
	medium_font:  ^im.Font,
	large_font:   ^im.Font,
}

sample_context_load :: proc(ctx: ^Sample_Context) {
	ctx.camera = camera_get_default()
}
