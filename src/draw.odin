package main

import "core:container/lru"
import "core:fmt"
import os "core:os/os2"
import "core:strings"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import stbi "vendor:stb/image"
import tt "vendor:stb/truetype"

_ :: stbi

Camera :: struct {
	center: [2]f32,
	zoom:   f32,
	width:  f32,
	height: f32,
}

camera_get_default :: proc() -> Camera {
	return Camera{center = {0, 0}, zoom = 1, width = 1280, height = 720}
}

camera_reset_view :: proc "contextless" (camera: ^Camera) {
	camera.center = {0.0, 20.0}
	camera.zoom = 1.0
}

Draw :: struct {
	font: Font,
}

draw_create :: proc() -> ^Draw {
	draw := new(Draw)
	draw.font = font_create("data/droid_sans.ttf", 18.0)
	return draw
}

draw_destroy :: proc(draw: ^Draw) {
	font_destroy(&draw.font)
	free(draw)
}

FONT_FIRST_CHARACTER :: 32
FONT_CHARACTER_COUNT :: 96
FONT_ATLAS_WIDTH :: 512
FONT_ATLAS_HEIGHT :: 512

// The number of vertices the vbo can hold. Must be a multiple of 6.
FONT_BATCH_SIZE :: (6 * 10000)

RGBA8 :: [4]u8

@(private = "file")
make_rgba8 :: proc(c: b2.HexColor, alpha: f32) -> RGBA8 {
	color: RGBA8
	color.r = u8((int(c) >> 16) & 0xFF)
	color.g = u8((int(c) >> 8) & 0xFF)
	color.b = u8((int(c) >> 0) & 0xFF)
	color.a = u8(alpha * 0xFF)
	return color
}

Font_Vertex :: struct {
	position: [2]f32,
	uv:       [2]f32,
	color:    RGBA8,
}

Font :: struct {
	font_size:  f32,
	vertices:   [dynamic]Font_Vertex,
	characters: []tt.bakedchar,
	texture_id: u32,
	vao_id:     u32,
	vbo_id:     u32,
	program_id: u32,
}

font_create :: proc(font_path: string, font_size: f32) -> Font {
	font: Font
	file_buffer, err := os.read_entire_file_from_path(font_path, context.allocator)
	if err != nil {
		assert(false)
		return font
	}
	defer delete(file_buffer)

	font.vertices = make([dynamic]Font_Vertex, 0, FONT_BATCH_SIZE)
	font.font_size = font_size
	font.characters = make([]tt.bakedchar, FONT_BATCH_SIZE)

	pw, ph: i32 = FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT
	temp_bitmap := make([]byte, pw * ph)
	defer delete(temp_bitmap)
	tt.BakeFontBitmap(
		raw_data(file_buffer),
		0,
		font.font_size,
		raw_data(temp_bitmap),
		pw,
		ph,
		FONT_FIRST_CHARACTER,
		FONT_CHARACTER_COUNT,
		raw_data(font.characters),
	)

	gl.GenTextures(1, &font.texture_id)
	gl.BindTexture(gl.TEXTURE_2D, font.texture_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R8, pw, ph, 0, gl.RED, gl.UNSIGNED_BYTE, raw_data(temp_bitmap))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)

	// for debugging
	// stbi.write_png("fontAtlas.png", pw, ph, 1, raw_data(temp_bitmap), pw)

	font.program_id = create_program_from_files("data/font.vs", "data/font.fs")
	if font.program_id == 0 {
		return font
	}

	// Setting up the VAO and VBO
	gl.GenBuffers(1, &font.vbo_id)
	gl.BindBuffer(gl.ARRAY_BUFFER, font.vbo_id)
	gl.BufferData(gl.ARRAY_BUFFER, FONT_BATCH_SIZE * size_of(Font_Vertex), nil, gl.DYNAMIC_DRAW)

	gl.GenVertexArrays(1, &font.vao_id)
	gl.BindVertexArray(font.vao_id)

	// position attribute
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Font_Vertex), offset_of(Font_Vertex, position))
	gl.EnableVertexAttribArray(0)

	// uv attribute
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(Font_Vertex), offset_of(Font_Vertex, uv))
	gl.EnableVertexAttribArray(1)

	// color attribute will be expanded to floats using normalization
	gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(Font_Vertex), offset_of(Font_Vertex, color))
	gl.EnableVertexAttribArray(2)

	gl.BindVertexArray(0)

	check_opengl()
	return font
}

font_destroy :: proc(font: ^Font) {
	if font.program_id != 0 {
		gl.DeleteProgram(font.program_id)
	}
	gl.DeleteBuffers(1, &font.vbo_id)
	gl.DeleteVertexArrays(1, &font.vao_id)
	if font.texture_id != 0 {
		gl.DeleteTextures(1, &font.texture_id)
	}
	delete(font.characters)
	delete(font.vertices)
}

draw_screen_string :: proc(draw: ^Draw, x, y: f32, color: b2.HexColor, format: string, args: ..any) {
	text := fmt.aprintf(format, ..args)
	defer delete(text)
	draw_add_text(&draw.font, x, y, color, text)
}

flush_draw :: proc(draw: ^Draw, camera: ^Camera) {
	flush_text(&draw.font, camera)
	check_opengl()
}

@(private = "file")
draw_add_text :: proc(font: ^Font, x, y: f32, color: b2.HexColor, text: string) {
	if len(text) == 0 {
		return
	}

	position := [2]f32{x, y}
	c := make_rgba8(color, 1.0)
	pw, ph: i32 = FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT

	for i in 0 ..< len(text) {
		index := i32(text[i]) - FONT_FIRST_CHARACTER
		if 0 <= index && index < FONT_CHARACTER_COUNT {
			q: tt.aligned_quad
			tt.GetBakedQuad(raw_data(font.characters), pw, ph, index, &position.x, &position.y, &q, true)
			v1 := Font_Vertex{{q.x0, q.y0}, {q.s0, q.t0}, c}
			v2 := Font_Vertex{{q.x1, q.y0}, {q.s1, q.t0}, c}
			v3 := Font_Vertex{{q.x1, q.y1}, {q.s1, q.t1}, c}
			v4 := Font_Vertex{{q.x0, q.y1}, {q.s0, q.t1}, c}

			append(&font.vertices, v1)
			append(&font.vertices, v3)
			append(&font.vertices, v2)
			append(&font.vertices, v1)
			append(&font.vertices, v4)
			append(&font.vertices, v3)
		}
	}
}

@(private = "file")
make_orthographic_matrix :: proc(m: ^[16]f32, left, right, bottom, top, near, far: f32) {
	m[0] = 2.0 / (right - left)
	m[1] = 0.0
	m[2] = 0.0
	m[3] = 0.0

	m[4] = 0.0
	m[5] = 2.0 / (top - bottom)
	m[6] = 0.0
	m[7] = 0.0

	m[8] = 0.0
	m[9] = 0.0
	m[10] = -2.0 / (far - near)
	m[11] = 0.0

	m[12] = -(right + left) / (right - left)
	m[13] = -(top + bottom) / (top - bottom)
	m[14] = -(far + near) / (far - near)
	m[15] = 1.0
}

@(private = "file")
flush_text :: proc(font: ^Font, camera: ^Camera) {
	projection_matrix: [16]f32
	make_orthographic_matrix(&projection_matrix, 0, camera.width, camera.height, 0, -1, 1)

	gl.UseProgram(font.program_id)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	slot: i32 = 0
	gl.ActiveTexture(gl.TEXTURE0 + u32(slot))
	gl.BindTexture(gl.TEXTURE_2D, font.texture_id)

	gl.BindVertexArray(font.vao_id)
	gl.BindBuffer(gl.ARRAY_BUFFER, font.vbo_id)

	texture_uniform := gl.GetUniformLocation(font.program_id, "FontAtlas")
	gl.Uniform1i(texture_uniform, slot)

	matrix_uniform := gl.GetUniformLocation(font.program_id, "ProjectionMatrix")
	gl.UniformMatrix4fv(matrix_uniform, 1, gl.FALSE, raw_data(&projection_matrix))

	total_vertex_count := len(font.vertices)
	draw_call_count := (total_vertex_count / FONT_BATCH_SIZE) + 1

	for i in 0 ..< draw_call_count {
		data := font.vertices[i * FONT_BATCH_SIZE:]
		vertex_count: int
		if i == draw_call_count - 1 {
			vertex_count = total_vertex_count % FONT_BATCH_SIZE
		} else {
			vertex_count = FONT_BATCH_SIZE
		}
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, vertex_count * size_of(Font_Vertex), raw_data(data))
		gl.DrawArrays(gl.TRIANGLES, 0, i32(vertex_count))
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	gl.Disable(gl.BLEND)

	check_opengl()
	clear(&font.vertices)
}
