package main

import im "../odin-imgui"
import "core:slice"
import "core:strings"
import b2 "vendor:box2d"
import "vendor:glfw"

Sample_Context :: struct {
	window:       glfw.WindowHandle,
	camera:       Camera,
	draw:         ^Draw,
	ui_scale:     f32,
	worker_count: i32,


	// These are persisted
	sample_index: i32,
	debug_draw:   b2.DebugDraw,
	regular_font: ^im.Font,
	medium_font:  ^im.Font,
	large_font:   ^im.Font,
}

Sample :: struct {}

Sample_Entry :: struct {
	category:   string,
	name:       string,
	create_fcn: sample_create_fcn_type,
}

sample_create_fcn_type :: #type proc(ctx: ^Sample_Context) -> Sample

g_sample_entries: [dynamic]Sample_Entry

register_sample :: proc(category, name: string, fcn: sample_create_fcn_type) {
	append(&g_sample_entries, Sample_Entry{category, name, fcn})
}

register_all_samples :: proc() {
	// todo: add all samples
	slice.sort_by(g_sample_entries[:], proc(i, j: Sample_Entry) -> bool {
		if i.category != j.category {
			return i.category < j.category
		}
		return i.name < j.name
	})
}

sample_context_load :: proc(ctx: ^Sample_Context) {
	ctx.camera = camera_get_default()
}

sample_context_save :: proc(ctx: ^Sample_Context) {

}
