package main

import im "../odin-imgui"
import "core:slice"
import "core:strings"
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

Sample :: struct {}

Sample_Entry :: struct {
	category:   cstring,
	name:       cstring,
	create_fcn: sample_create_fcn_type,
}

sample_create_fcn_type :: #type proc(ctx: ^Sample_Context) -> Sample

g_sample_entries: [dynamic]Sample_Entry

register_sample :: proc(category, name: cstring, fcn: sample_create_fcn_type) {
	append(&g_sample_entries, Sample_Entry{category, name, fcn})
}

register_all_samples :: proc() {
	// todo: add all samples
	register_sample("placeholder", "test", nil)
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

sample_keyboard :: proc(sample: ^Sample, key: i32) {

}
