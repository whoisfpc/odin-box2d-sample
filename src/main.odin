package main

import enki "../odin-enkiTS"
import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import os "core:os/os2"
import "core:strings"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import "vendor:glfw"

g_context: runtime.Context

@(private = "file")
s_ctx: Sample_Context

@(private = "file")
s_selection: i32

@(private = "file")
s_sample: ^Sample

@(private = "file")
s_right_mouse_down: bool

@(private = "file")
s_click_point_ws: [2]f32

@(private = "file")
assert_fcn :: proc "c" (condition, file_name: cstring, line_number: i32) -> i32 {
	context = g_context
	fmt.printfln("SAMPLE ASSERTION: %s, %s, line %d", condition, file_name, line_number)
	return 1
}

@(private = "file")
glfw_error_callback :: proc "c" (error: c.int, description: cstring) {
	context = g_context
	fmt.eprintfln("GLFW error occurred. Code: %d. Description: %s", error, description)
}

@(private = "file")
restart_sample :: proc() {
	sample_variant_destroy(s_sample)
	s_sample = nil
	s_ctx.restart = true
	s_sample = g_sample_entries[s_ctx.sample_index].create_fcn(&s_ctx)
	s_ctx.restart = false
}

@(private = "file")
create_ui :: proc(window: glfw.WindowHandle) {
	im.CHECKVERSION()
	im.CreateContext()

	if !imgui_impl_glfw.InitForOpenGL(window, false) {
		fmt.printfln("ImGui_ImplGlfw_InitForOpenGL failed")
		assert(false)
	}

	if !imgui_impl_opengl3.Init() {
		fmt.printfln("ImGui_ImplOpenGL3_Init failed")
		assert(false)
	}

	im.Style_ScaleAllSizes(im.GetStyle(), s_ctx.ui_scale)
	font_path :: "data/droid_sans.ttf"

	if os.exists(font_path) {
		font_cfg := im.FontConfig {
			FontDataOwnedByAtlas = true,
			OversampleH          = 2,
			OversampleV          = 1,
			GlyphMaxAdvanceX     = max(f32),
			RasterizerMultiply   = s_ctx.ui_scale,
			RasterizerDensity    = 1,
			EllipsisChar         = ~im.Wchar(0),
		}
		regular_size := math.floor(13.0 * s_ctx.ui_scale)
		medium_size := math.floor(40.0 * s_ctx.ui_scale)
		large_size := math.floor(64.0 * s_ctx.ui_scale)
		io := im.GetIO()
		s_ctx.regular_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, regular_size, &font_cfg)
		s_ctx.medium_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, medium_size, &font_cfg)
		s_ctx.large_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, large_size, &font_cfg)

		io.FontDefault = s_ctx.regular_font
	} else {
		fmt.printfln("\n\nERROR: samples working directory must be the top level directory\n\n")
		os.exit(1)
	}
}

@(private = "file")
destroy_ui :: proc() {
	imgui_impl_opengl3.Shutdown()
	imgui_impl_glfw.Shutdown()
	im.DestroyContext()
}

@(private = "file")
resize_window_callback :: proc "c" (window: glfw.WindowHandle, width, heigth: c.int) {
	s_ctx.camera.width = f32(width)
	s_ctx.camera.height = f32(heigth)
}

@(private = "file")
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	imgui_impl_glfw.KeyCallback(window, key, scancode, action, mods)
	if im.GetIO().WantCaptureKeyboard {
		return
	}

	if action == glfw.PRESS {
		switch key {
		case glfw.KEY_ESCAPE:
			// Quit
			glfw.SetWindowShouldClose(s_ctx.window, gl.TRUE)
		case glfw.KEY_LEFT:
			s_ctx.camera.center.x -= 0.5
		case glfw.KEY_RIGHT:
			s_ctx.camera.center.x += 0.5
		case glfw.KEY_DOWN:
			s_ctx.camera.center.y -= 0.5
		case glfw.KEY_UP:
			s_ctx.camera.center.y += 0.5
		case glfw.KEY_HOME:
			camera_reset_view(&s_ctx.camera)
		case glfw.KEY_R:
			{
				context = g_context
				restart_sample()
			}
		case glfw.KEY_O:
			s_ctx.single_step = true
		case glfw.KEY_P:
			s_ctx.pause = !s_ctx.pause
		case glfw.KEY_LEFT_BRACKET:
			s_selection -= 1
			if s_selection < 0 {
				s_selection = i32(len(g_sample_entries) - 1)
			}
		case glfw.KEY_RIGHT_BRACKET:
			s_selection += 1
			if s_selection == i32(len(g_sample_entries)) {
				s_selection = 0
			}
		case glfw.KEY_TAB:
			s_ctx.show_ui = !s_ctx.show_ui
		case:
			if s_sample != nil {
				context = g_context
				sample_variant_keyboard(s_sample, key)
			}
		}
	}
}

@(private = "file")
char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	imgui_impl_glfw.CharCallback(window, c.uint(codepoint))
}

@(private = "file")
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
	imgui_impl_glfw.MouseButtonCallback(window, button, action, mods)
	if im.GetIO().WantCaptureMouse {
		return
	}

	xpos, ypos := glfw.GetCursorPos(window)
	ps := [2]f32{f32(xpos), f32(ypos)}

	// Use the mouse to move things around.
	if button == glfw.MOUSE_BUTTON_1 {
		pw := convert_screen_to_world(&s_ctx.camera, ps)
		if action == glfw.PRESS {
			sample_variant_mouse_down(s_sample, pw, button, mods)
		}

		if action == glfw.RELEASE {
			sample_variant_mouse_up(s_sample, pw, button)
		}

	} else if button == glfw.MOUSE_BUTTON_2 {
		if action == glfw.PRESS {
			s_click_point_ws = convert_screen_to_world(&s_ctx.camera, ps)
			s_right_mouse_down = true
		}

		if action == glfw.RELEASE {
			s_right_mouse_down = false
		}
	}
}

@(private = "file")
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	ps := [2]f32{f32(xpos), f32(ypos)}
	imgui_impl_glfw.CursorPosCallback(window, f64(ps.x), f64(ps.y))

	pw := convert_screen_to_world(&s_ctx.camera, ps)
	sample_variant_mouse_move(s_sample, pw)
	if s_right_mouse_down {
		diff := pw - s_click_point_ws
		s_ctx.camera.center -= diff
		s_click_point_ws = convert_screen_to_world(&s_ctx.camera, ps)
	}
}

@(private = "file")
scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	imgui_impl_glfw.ScrollCallback(window, xoffset, yoffset)
	if im.GetIO().WantCaptureMouse {
		return
	}

	if yoffset > 0 {
		s_ctx.camera.zoom /= 1.1
	} else if yoffset < 0 {
		s_ctx.camera.zoom *= 1.1
	}
}

@(private = "file")
update_ui :: proc() {
	max_works := i32(enki.GetNumHardwareThreads())

	font_size := im.GetFontSize()
	menu_width := 13.0 * font_size
	if s_ctx.show_ui {
		im.SetNextWindowPos({s_ctx.camera.width - menu_width - 0.5 * font_size, 0.5 * font_size})
		im.SetNextWindowSize({menu_width, s_ctx.camera.height - font_size})

		im.Begin("Tools", &s_ctx.show_ui, {.NoMove, .NoResize, .NoCollapse})

		if im.BeginTabBar("ControlTabs") {
			if im.BeginTabItem("Controls") {
				im.PushItemWidth(100.0)
				im.SliderInt("Sub-steps", &s_ctx.sub_step_count, 1, 32)
				im.SliderFloat("Hertz", &s_ctx.hertz, 5.0, 240.0, "%.0f hz")

				if (im.SliderInt("Workers", &s_ctx.worker_count, 1, max_works)) {
					s_ctx.worker_count = clamp(s_ctx.worker_count, 1, max_works)
					restart_sample()
				}
				im.PopItemWidth()

				im.Separator()

				im.Checkbox("Sleep", &s_ctx.enable_sleep)
				im.Checkbox("Warm Starting", &s_ctx.enable_warm_starting)
				im.Checkbox("Continuous", &s_ctx.enable_continuous)

				im.Separator()

				im.Checkbox("Shapes", &s_ctx.debug_draw.drawShapes)
				im.Checkbox("Joints", &s_ctx.debug_draw.drawJoints)
				im.Checkbox("Joint Extras", &s_ctx.debug_draw.drawJointExtras)
				im.Checkbox("Bounds", &s_ctx.debug_draw.drawBounds)
				im.Checkbox("Contact Points", &s_ctx.debug_draw.drawContacts)
				im.Checkbox("Contact Normals", &s_ctx.debug_draw.drawContactNormals)
				im.Checkbox("Contact Features", &s_ctx.debug_draw.drawContactFeatures)
				im.Checkbox("Contact Forces", &s_ctx.debug_draw.drawContactImpulses)
				im.Checkbox("Friction Forces", &s_ctx.debug_draw.drawFrictionImpulses)
				im.Checkbox("Mass", &s_ctx.debug_draw.drawMass)
				im.Checkbox("Body Names", &s_ctx.debug_draw.drawBodyNames)
				im.Checkbox("Graph Colors", &s_ctx.debug_draw.drawGraphColors)
				im.Checkbox("Islands", &s_ctx.debug_draw.drawIslands)
				im.Checkbox("Counters", &s_ctx.draw_counters)
				im.Checkbox("Profile", &s_ctx.draw_profile)

				im.PushItemWidth(80.0)
				// im.InputFloat("Joint Scale", &s_context.debug_draw.jointScale)
				// im.InputFloat("Force Scale", &s_context.debug_draw.forceScale)
				im.PopItemWidth()

				button_sz := [2]f32{-1.0, 0.0}

				if im.Button("Pause (P)", button_sz) {
					s_ctx.pause = !s_ctx.pause
				}

				if im.Button("Single Step (O)", button_sz) {
					s_ctx.single_step = !s_ctx.single_step
				}

				if im.Button("Dump Mem Stats", button_sz) {
					b2.World_DumpMemoryStats(s_sample.world_id)
				}

				if im.Button("Reset Profile", button_sz) {
					sample_reset_profile(s_sample)
				}

				if im.Button("Restart (R)", button_sz) {
					restart_sample()
				}

				if im.Button("Quit", button_sz) {
					glfw.SetWindowShouldClose(s_ctx.window, gl.TRUE)
				}

				im.EndTabItem()
			}

			if im.BeginTabItem("Samples") {
				leaf_node_flags: im.TreeNodeFlags = {.OpenOnArrow, .OpenOnDoubleClick, .Leaf, .NoTreePushOnOpen}
				node_flags: im.TreeNodeFlags = {.OpenOnArrow, .OpenOnDoubleClick}

				category_index := 0
				category := g_sample_entries[category_index].category
				i := 0
				for i < len(g_sample_entries) {
					category_selected := category == g_sample_entries[s_ctx.sample_index].category
					node_selection_flags: im.TreeNodeFlags = category_selected ? {.Selected} : {}
					node_open := im.TreeNodeEx(category, node_flags + node_selection_flags)
					if node_open {
						for i < len(g_sample_entries) && category == g_sample_entries[i].category {
							selection_flags: im.TreeNodeFlags = {}
							if s_ctx.sample_index == i32(i) {
								selection_flags = {.Selected}
							}
							im.TreeNodeExPtr(
								rawptr(uintptr(i)),
								leaf_node_flags + selection_flags,
								"%s",
								g_sample_entries[i].name,
							)
							if im.IsItemClicked() {
								s_selection = i32(i)
							}
							i += 1
						}
						im.TreePop()
					} else {
						for i < len(g_sample_entries) && category == g_sample_entries[i].category {
							i += 1
						}
					}

					if i < len(g_sample_entries) {
						category = g_sample_entries[i].category
						category_index = i
					}
				}
				im.EndTabItem()
			}
			im.EndTabBar()
		}

		im.End()
		sample_variant_update_gui(s_sample)
	}
}

main :: proc() {
	g_context = context
	register_all_samples()

	// todo: set allocator
	b2.SetAssertFcn(assert_fcn)

	sample_context_load(&s_ctx)
	s_ctx.worker_count = min(8, i32(enki.GetNumHardwareThreads() / 2))

	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(-1)
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	// MSAA
	glfw.WindowHint(glfw.SAMPLES, 4)

	// official vendor lack this procedure
	version := b2.GetVersion()
	b2_version_info := fmt.aprintf("Box2D Version %d.%d.%d", version.major, version.minor, version.revision)
	defer delete(b2_version_info)
	title_cstring := strings.clone_to_cstring(b2_version_info)
	defer delete(title_cstring)

	if primary_monitor := glfw.GetPrimaryMonitor(); primary_monitor != nil {
		_, s_ctx.ui_scale = glfw.GetMonitorContentScale(primary_monitor)
	}

	s_ctx.window = glfw.CreateWindow(i32(s_ctx.camera.width), i32(s_ctx.camera.height), title_cstring, nil, nil)
	if s_ctx.window == nil {
		fmt.eprintln("Failed to create GLFW window.")
		glfw.Terminate()
		os.exit(-1)
	}

	glfw.MakeContextCurrent(s_ctx.window)
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	dump_info_gl()

	glfw.SetWindowSizeCallback(s_ctx.window, resize_window_callback)
	glfw.SetKeyCallback(s_ctx.window, key_callback)
	glfw.SetCharCallback(s_ctx.window, char_callback)
	glfw.SetMouseButtonCallback(s_ctx.window, mouse_button_callback)
	glfw.SetCursorPosCallback(s_ctx.window, cursor_pos_callback)
	glfw.SetScrollCallback(s_ctx.window, scroll_callback)

	create_ui(s_ctx.window)
	s_ctx.draw = draw_create()
	s_ctx.sample_index = clamp(s_ctx.sample_index, 0, i32(len(g_sample_entries) - 1))
	s_selection = s_ctx.sample_index

	gl.ClearColor(0.2, 0.2, 0.2, 1.0)

	frame_time: f32 = 0.0

	for !glfw.WindowShouldClose(s_ctx.window) {
		time1 := glfw.GetTime()

		if glfw.GetKey(s_ctx.window, glfw.KEY_Z) == glfw.PRESS {
			// Zoom out
			s_ctx.camera.zoom = min(1.005 * s_ctx.camera.zoom, 100.0)
		} else if glfw.GetKey(s_ctx.window, glfw.KEY_X) == glfw.PRESS {
			// Zoom in
			s_ctx.camera.zoom = min(0.995 * s_ctx.camera.zoom, 0.5)
		}

		width, height := glfw.GetWindowSize(s_ctx.window)
		s_ctx.camera.width, s_ctx.camera.height = f32(width), f32(height)

		buffer_width, buffer_height := glfw.GetFramebufferSize(s_ctx.window)
		gl.Viewport(0, 0, buffer_width, buffer_height)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()

		io := im.GetIO()
		io.DisplaySize.x = s_ctx.camera.width
		io.DisplaySize.y = s_ctx.camera.height
		io.DisplayFramebufferScale.x = f32(buffer_width) / s_ctx.camera.width
		io.DisplayFramebufferScale.y = f32(buffer_height) / s_ctx.camera.height

		im.NewFrame()

		if s_sample == nil {
			// delayed creation because imgui doesn't create fonts until NewFrame() is called
			s_sample = g_sample_entries[s_ctx.sample_index].create_fcn(&s_ctx)
		}

		sample_reset_text(s_sample)
		sample_draw_colored_text_line(
			s_sample,
			.Yellow,
			"%s : %s",
			g_sample_entries[s_ctx.sample_index].category,
			g_sample_entries[s_ctx.sample_index].name,
		)
		sample_variant_step(s_sample)

		draw_screen_string(
			s_ctx.draw,
			5.0,
			s_ctx.camera.height - 10.0,
			.SeaGreen,
			"%.1f ms - step %d - camera (%g, %g, %g)",
			1000.0 * frame_time,
			s_sample.step_count,
			s_ctx.camera.center.x,
			s_ctx.camera.center.y,
			s_ctx.camera.zoom,
		)

		draw_flush(s_ctx.draw, &s_ctx.camera)

		update_ui()

		im.Render()
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
		glfw.SwapBuffers(s_ctx.window)

		if s_selection != s_ctx.sample_index {
			camera_reset_view(&s_ctx.camera)
			s_ctx.sample_index = s_selection
			s_ctx.sub_step_count = 4
			s_ctx.debug_draw.drawJoints = true

			sample_variant_destroy(s_sample)
			s_sample = nil
			s_sample = g_sample_entries[s_ctx.sample_index].create_fcn(&s_ctx)
		}

		glfw.PollEvents()

		// Limit frame rate to 60Hz
		time2 := glfw.GetTime()
		target_time := time1 + 1.0 / 60.0
		for time2 < target_time {
			b2.Yield()
			time2 = glfw.GetTime()
		}

		frame_time = f32(time2 - time1)

		free_all(context.temp_allocator)
	}
	if s_sample != nil {
		sample_variant_destroy(s_sample)
		s_sample = nil
	}

	draw_destroy(s_ctx.draw)
	destroy_ui()
	glfw.DestroyWindow(s_ctx.window)
	glfw.Terminate()

	sample_context_save(&s_ctx)
}
