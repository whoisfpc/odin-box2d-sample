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

		im.GetIO().FontDefault = s_context.regular_font
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
	// todo: set allocator
	b2.SetAssertFcn(assert_fcn)

	sample_context_load(&s_context)
	s_context.worker_count = min(8, i32(enki.GetNumHardwareThreads() / 2))

	// todo: sort samples

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

	// test only
	glfw.SwapInterval(1) // vsync
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

	im.StyleColorsDark()

	for !glfw.WindowShouldClose(s_context.window) {
		glfw.PollEvents()

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()
		im.NewFrame()

		im.ShowDemoWindow()

		if im.Begin("Window containing a quit button") {
			if im.Button("The quit button in question") {
				glfw.SetWindowShouldClose(s_context.window, true)
			}
		}
		im.End()

		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(s_context.window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		glfw.SwapBuffers(s_context.window)
	}
}
