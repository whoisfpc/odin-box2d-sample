package main

import "core:fmt"
import os "core:os/os2"
import "core:strings"
import gl "vendor:OpenGL"

dump_info_gl :: proc() {
	renderer := gl.GetString(gl.RENDERER)
	vendor := gl.GetString(gl.VENDOR)
	version := gl.GetString(gl.VERSION)
	glsl_version := gl.GetString(gl.SHADING_LANGUAGE_VERSION)

	major, minor: i32
	gl.GetIntegerv(gl.MAJOR_VERSION, &major)
	gl.GetIntegerv(gl.MINOR_VERSION, &minor)

	fmt.println("-------------------------------------------------------------")
	fmt.printfln("GL Vendor    : %s", vendor)
	fmt.printfln("GL Renderer  : %s", renderer)
	fmt.printfln("GL Version   : %s", version)
	fmt.printfln("GL Version   : %d.%d", major, minor)
	fmt.printfln("GLSL Version : %s", glsl_version)
	fmt.println("-------------------------------------------------------------")
}

check_opengl :: proc() {
	err := gl.GetError()
	if err != gl.NO_ERROR {
		fmt.printfln("OpenGL error = %d", err)
		assert(false)
	}
}

print_log_gl :: proc(object: u32) {
	log_length: i32 = 0
	if gl.IsShader(object) {
		gl.GetShaderiv(object, gl.INFO_LOG_LENGTH, &log_length)
	} else if gl.IsProgram(object) {
		gl.GetProgramiv(object, gl.INFO_LOG_LENGTH, &log_length)
	} else {
		fmt.printf("PrintLogGL: Not a shader or a program\n")
		return
	}

	log := make([]u8, log_length)
	defer delete(log)
	if gl.IsShader(object) {
		gl.GetShaderInfoLog(object, log_length, nil, raw_data(log[:]))
	} else if gl.IsProgram(object) {
		gl.GetProgramInfoLog(object, log_length, nil, raw_data(log[:]))
	}

	fmt.printfln("PrintLogGL: %s", transmute(string)log)
}

@(private = "file")
s_create_shader_from_string :: proc(source: cstring, type: u32) -> u32 {
	shader := gl.CreateShader(type)
	sources: [1]cstring = {source}
	gl.ShaderSource(shader, 1, raw_data(sources[:]), nil)
	gl.CompileShader(shader)

	success: i32 = 0
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)

	if success == 0 {
		fmt.printfln("Error compiling shader of type %d!", type)
		print_log_gl(shader)
		gl.DeleteShader(shader)
		return 0
	}

	return shader
}

create_shader_from_string :: proc(vertex_string, fragment_string: cstring) -> u32 {
	vertex := s_create_shader_from_string(vertex_string, gl.VERTEX_SHADER)
	if vertex == 0 {
		return 0
	}
	fragment := s_create_shader_from_string(fragment_string, gl.FRAGMENT_SHADER)
	if fragment == 0 {
		return 0
	}
	program := gl.CreateProgram()
	gl.AttachShader(program, vertex)
	gl.AttachShader(program, fragment)

	gl.LinkProgram(program)

	success: i32 = 0
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		fmt.printfln("glLinkProgram:")
		print_log_gl(program)
		return 0
	}

	gl.DeleteShader(vertex)
	gl.DeleteShader(fragment)

	return program
}

create_shader_from_files :: proc(vertex_path, fragment_path: cstring) -> u32 {
	vertex_data, vertex_err := os.read_entire_file_from_path(string(vertex_path), context.allocator)
	if vertex_err != nil {
		fmt.printfln("Error opening %v", vertex_err)
		return 0
	}
	defer delete(vertex_data)
	fragment_data, fragment_err := os.read_entire_file_from_path(string(fragment_path), context.allocator)
	if fragment_err != nil {
		fmt.printfln("Error opening %v", fragment_err)
		return 0
	}
	defer delete(fragment_data)
	vertex_cstr := strings.clone_to_cstring(transmute(string)vertex_data)
	fragment_cstr := strings.clone_to_cstring(transmute(string)fragment_data)
	defer delete(vertex_cstr)
	defer delete(fragment_cstr)
	return create_shader_from_string(vertex_cstr, fragment_cstr)
}
