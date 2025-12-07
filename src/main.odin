package main

import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import "vendor:glfw"

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
s_context: Sample_Context

main :: proc() {
	// todo: set allocator
	b2.SetAssertFcn(assert_fcn)

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
	title_cstring := strings.unsafe_string_to_cstring(b2_version_info)

	if primary_monitor := glfw.GetPrimaryMonitor(); primary_monitor != nil {
		_, yscale := glfw.GetMonitorContentScale(primary_monitor)
		s_context.ui_scale = yscale
	}

	s_context.window = glfw.CreateWindow(1920, 1080, title_cstring, nil, nil)
	if s_context.window == nil {
		fmt.eprintln("Failed to create GLFW window.")
		glfw.Terminate()
		os.exit(-1)
	}
	defer glfw.DestroyWindow(s_context.window)

	glfw.MakeContextCurrent(s_context.window)
	glfw.SwapInterval(1) // vsync
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	// test only
	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

	im.StyleColorsDark()

	imgui_impl_glfw.InitForOpenGL(s_context.window, true)
	defer imgui_impl_glfw.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()

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
