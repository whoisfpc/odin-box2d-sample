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

@(private = "file")
s_context: Sample_Context

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
	context = runtime.default_context()
	fmt.printfln("SAMPLE ASSERTION: %s, %s, line %d", condition, file_name, line_number)
	return 1
}

@(private = "file")
glfw_error_callback :: proc "c" (error: c.int, description: cstring) {
	context = runtime.default_context()
	fmt.eprintfln("GLFW error occurred. Code: %d. Description: %s", error, description)
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

	im.Style_ScaleAllSizes(im.GetStyle(), s_context.ui_scale)
	font_path :: "data/droid_sans.ttf"

	if os.exists(font_path) {
		font_cfg := im.FontConfig {
			FontDataOwnedByAtlas = true,
			OversampleH          = 2,
			OversampleV          = 1,
			GlyphMaxAdvanceX     = max(f32),
			RasterizerMultiply   = s_context.ui_scale,
			RasterizerDensity    = 1,
			EllipsisChar         = ~im.Wchar(0),
		}
		regular_size := math.floor(13.0 * s_context.ui_scale)
		medium_size := math.floor(40.0 * s_context.ui_scale)
		large_size := math.floor(64.0 * s_context.ui_scale)
		io := im.GetIO()
		s_context.regular_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, regular_size, &font_cfg)
		s_context.medium_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, medium_size, &font_cfg)
		s_context.large_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, large_size, &font_cfg)

		io.FontDefault = s_context.regular_font
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
	s_context.camera.width = f32(width)
	s_context.camera.height = f32(heigth)
}

@(private = "file")
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	imgui_impl_glfw.KeyCallback(window, key, scancode, action, mods)
	if im.GetIO().WantCaptureKeyboard {
		return
	}
	// todo: unfinish
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
	// todo: unfinish
}

@(private = "file")
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	ps := [2]f32{f32(xpos), f32(ypos)}
	imgui_impl_glfw.CursorPosCallback(window, f64(ps.x), f64(ps.y))
	// todo: unfinish
}

@(private = "file")
scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	imgui_impl_glfw.ScrollCallback(window, xoffset, yoffset)
	if im.GetIO().WantCaptureMouse {
		return
	}

	if yoffset > 0 {
		s_context.camera.zoom /= 1.1
	} else if yoffset < 0 {
		s_context.camera.zoom *= 1.1
	}
}

main :: proc() {
	register_all_samples()

	// todo: set allocator
	b2.SetAssertFcn(assert_fcn)

	sample_context_load(&s_context)
	s_context.worker_count = min(8, i32(enki.GetNumHardwareThreads() / 2))

	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(-1)
	}
	defer glfw.Terminate()

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
		_, s_context.ui_scale = glfw.GetMonitorContentScale(primary_monitor)
	}

	s_context.window = glfw.CreateWindow(
		i32(s_context.camera.width),
		i32(s_context.camera.height),
		title_cstring,
		nil,
		nil,
	)
	if s_context.window == nil {
		fmt.eprintln("Failed to create GLFW window.")
		glfw.Terminate()
		os.exit(-1)
	}
	defer glfw.DestroyWindow(s_context.window)

	glfw.MakeContextCurrent(s_context.window)
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	{
		gl_version_str := gl.GetString(gl.VERSION)
		glsl_version_str := gl.GetString(gl.SHADING_LANGUAGE_VERSION)
		fmt.printfln("OpenGL %s, GLSL %s", gl_version_str, glsl_version_str)
	}

	glfw.SetWindowSizeCallback(s_context.window, resize_window_callback)
	glfw.SetKeyCallback(s_context.window, key_callback)
	glfw.SetCharCallback(s_context.window, char_callback)
	glfw.SetMouseButtonCallback(s_context.window, mouse_button_callback)
	glfw.SetCursorPosCallback(s_context.window, cursor_pos_callback)
	glfw.SetScrollCallback(s_context.window, scroll_callback)

	create_ui(s_context.window)
	defer destroy_ui()
	s_context.draw = draw_create()
	defer draw_destroy(s_context.draw)
	s_context.sample_index = clamp(s_context.sample_index, 0, i32(len(g_sample_entries) - 1))
	s_selection = s_context.sample_index

	gl.ClearColor(0.2, 0.2, 0.2, 1.0)

	frame_time: f32 = 0.0

	for !glfw.WindowShouldClose(s_context.window) {
		time1 := glfw.GetTime()

		if glfw.GetKey(s_context.window, glfw.KEY_Z) == glfw.PRESS {
			// Zoom out
			s_context.camera.zoom = min(1.005 * s_context.camera.zoom, 100.0)
		} else if glfw.GetKey(s_context.window, glfw.KEY_X) == glfw.PRESS {
			// Zoom in
			s_context.camera.zoom = min(0.995 * s_context.camera.zoom, 0.5)
		}

		width, height := glfw.GetWindowSize(s_context.window)
		s_context.camera.width, s_context.camera.height = f32(width), f32(height)

		buffer_width, buffer_height := glfw.GetFramebufferSize(s_context.window)
		gl.Viewport(0, 0, buffer_width, buffer_height)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()

		io := im.GetIO()
		io.DisplaySize.x = s_context.camera.width
		io.DisplaySize.y = s_context.camera.height
		io.DisplayFramebufferScale.x = f32(buffer_width) / s_context.camera.width
		io.DisplayFramebufferScale.y = f32(buffer_height) / s_context.camera.height

		im.NewFrame()

		// todo: sample draw and step

		// imgui sample test only
		{
			im.ShowDemoWindow()
			if im.Begin("Window containing a quit button") {
				if im.Button("The quit button in question") {
					glfw.SetWindowShouldClose(s_context.window, true)
				}
				im.Text(
					"Application average %.3f ms/frame (%.1f FPS)",
					1000.0 / im.GetIO().Framerate,
					im.GetIO().Framerate,
				)
			}
			im.End()
		}

		im.Render()
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
		glfw.SwapBuffers(s_context.window)

		glfw.PollEvents()
		time2 := glfw.GetTime()
		target_time := time1 + 1.0 / 60.0
		for time2 < target_time {
			b2.Yield()
			time2 = glfw.GetTime()
		}

		frame_time = f32(time2 - time1)
	}
	if s_sample != nil {
		free(s_sample)
		s_sample = nil
	}

	sample_context_save(&s_context)
}
