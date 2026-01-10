package main

import "core:fmt"
import "core:mem"
import os "core:os/os2"
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

convert_screen_to_world :: proc "contextless" (camera: ^Camera, screen_point: [2]f32) -> [2]f32 {
	w := camera.width
	h := camera.height
	uv := [2]f32{screen_point.x / w, (h - screen_point.y) / h}

	ratio := w / h
	extents := [2]f32{camera.zoom * ratio, camera.zoom}
	lower := camera.center - extents
	upper := camera.center + extents

	pw := (1.0 - uv) * lower + uv * upper
	return pw
}

convert_world_to_screen :: proc "contextless" (camera: ^Camera, world_point: [2]f32) -> [2]f32 {
	w := camera.width
	h := camera.height

	ratio := w / h
	extents := [2]f32{camera.zoom * ratio, camera.zoom}
	lower := camera.center - extents
	upper := camera.center + extents

	uv := (world_point - lower) / (upper - lower)
	ps := [2]f32{uv.x * w, (1.0 - uv.y) * h}
	return ps
}

RGBA8 :: [4]u8

@(private = "file")
make_rgba8 :: proc "contextless" (c: b2.HexColor, alpha: f32) -> RGBA8 {
	color: RGBA8
	color.r = u8((int(c) >> 16) & 0xFF)
	color.g = u8((int(c) >> 8) & 0xFF)
	color.b = u8((int(c) >> 0) & 0xFF)
	color.a = u8(alpha * 0xFF)
	return color
}

POINT_BATCH_SIZE :: 2048

Point_Data :: struct {
	position: b2.Vec2,
	size:     f32,
	rgba:     RGBA8,
}

Point_Render :: struct {
	points:             [dynamic]Point_Data,
	vao_id:             u32,
	vbo_id:             u32,
	program_id:         u32,
	projection_uniform: i32,
}

LINE_BATCH_SIZE :: (2 * 2048)

Vertex_Data :: struct {
	position: b2.Vec2,
	rgba:     RGBA8,
}

Line_Render :: struct {
	points:             [dynamic]Vertex_Data,
	vao_id:             u32,
	vbo_id:             u32,
	program_id:         u32,
	projection_uniform: i32,
}

CAPSULE_BATCH_SIZE :: 2048

Capsule :: struct {
	transform: b2.Transform,
	radius:    f32,
	length:    f32,
	rgba:      RGBA8,
}

Capsules :: struct {
	capsules:            [dynamic]Capsule,
	vao_id:              u32,
	vbo_ids:             [2]u32,
	program_id:          u32,
	projection_uniform:  i32,
	pixel_scale_uniform: i32,
}

POLYGON_BATCH_SIZE :: 2048

Polygon :: struct {
	transform:      b2.Transform,
	p1, p2, p3, p4: b2.Vec2,
	p5, p6, p7, p8: b2.Vec2,
	count:          i32,
	radius:         f32,

	// keep color small
	color:          RGBA8,
}

Polygons :: struct {
	polygons:          [dynamic]Polygon,
	vaoId:             u32,
	vboIds:            [2]u32,
	programId:         u32,
	projectionUniform: i32,
	pixelScaleUniform: i32,
}

FONT_FIRST_CHARACTER :: 32
FONT_CHARACTER_COUNT :: 96
FONT_ATLAS_WIDTH :: 512
FONT_ATLAS_HEIGHT :: 512

// The number of vertices the vbo can hold. Must be a multiple of 6.
FONT_BATCH_SIZE :: (6 * 10000)

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

Draw :: struct {
	// TODO
	// Background background;
	points:   Point_Render,
	lines:    Line_Render,
	// CircleRender hollowCircles;
	// SolidCircles circles;
	capsules: Capsules,
	polygons: Polygons,
	font:     Font,
}

draw_create :: proc() -> ^Draw {
	draw := new(Draw)
	// todo
	draw.points = create_point_render()
	draw.lines = create_line_render()
	draw.capsules = create_capsules()
	draw.polygons = create_polygons()
	draw.font = font_create("data/droid_sans.ttf", 18.0)
	return draw
}

draw_destroy :: proc(draw: ^Draw) {
	// todo
	destroy_point_render(&draw.points)
	destroy_line_render(&draw.lines)
	destroy_capsules(&draw.capsules)
	destroy_polygons(&draw.polygons)
	font_destroy(&draw.font)
	free(draw)
}

@(private = "file")
create_point_render :: proc() -> Point_Render {
	render: Point_Render
	render.points = make([dynamic]Point_Data, 0, POINT_BATCH_SIZE)
	render.program_id = create_program_from_files("data/point.vs", "data/point.fs")
	render.projection_uniform = gl.GetUniformLocation(render.program_id, "projectionMatrix")

	vertexAtttribute: u32 = 0
	sizeAttribute: u32 = 1
	colorAttribute: u32 = 2

	// Generate
	gl.GenVertexArrays(1, &render.vao_id)
	gl.GenBuffers(1, &render.vbo_id)

	gl.BindVertexArray(render.vao_id)
	gl.EnableVertexAttribArray(vertexAtttribute)
	gl.EnableVertexAttribArray(sizeAttribute)
	gl.EnableVertexAttribArray(colorAttribute)

	// Vertex buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_id)
	gl.BufferData(gl.ARRAY_BUFFER, POINT_BATCH_SIZE * size_of(Point_Data), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(
		vertexAtttribute,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(Point_Data),
		offset_of(Point_Data, position),
	)

	gl.VertexAttribPointer(sizeAttribute, 1, gl.FLOAT, gl.FALSE, size_of(Point_Data), offset_of(Point_Data, size))
	// save bandwidth by expanding color to floats in the shader
	gl.VertexAttribPointer(
		colorAttribute,
		4,
		gl.UNSIGNED_BYTE,
		gl.TRUE,
		size_of(Point_Data),
		offset_of(Point_Data, rgba),
	)

	check_opengl()

	// Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	return render
}

@(private = "file")
destroy_point_render :: proc(render: ^Point_Render) {
	if render.vao_id != 0 {
		gl.DeleteVertexArrays(1, &render.vao_id)
		gl.DeleteBuffers(1, &render.vbo_id)
	}

	if render.program_id != 0 {
		gl.DeleteProgram(render.program_id)
	}

	delete(render.points)

	render^ = {}
}

@(private = "file")
flush_points :: proc(render: ^Point_Render, camera: ^Camera) {
	if len(render.points) == 0 {
		return
	}

	gl.UseProgram(render.program_id)

	proj: [16]f32
	BuildProjectionMatrix(camera, &proj, 0.0)

	gl.UniformMatrix4fv(render.projection_uniform, 1, gl.FALSE, raw_data(&proj))
	gl.BindVertexArray(render.vao_id)


	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_id)
	gl.Enable(gl.PROGRAM_POINT_SIZE)

	base := 0
	count := len(render.points)
	for (count > 0) {
		batchCount := min(count, POINT_BATCH_SIZE)
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, batchCount * size_of(Point_Data), raw_data(render.points[base:]))

		gl.DrawArrays(gl.POINTS, 0, i32(batchCount))

		check_opengl()

		count -= POINT_BATCH_SIZE
		base += POINT_BATCH_SIZE
	}

	gl.Disable(gl.PROGRAM_POINT_SIZE)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&render.points)
}

draw_point :: proc "contextless" (draw: ^Draw, position: b2.Vec2, size: f32, color: b2.HexColor) {
	context = g_context
	rgba := make_rgba8(color, 1.0)
	append(&draw.points.points, Point_Data{position, size, rgba})
}

@(private = "file")
create_line_render :: proc() -> Line_Render {
	render: Line_Render
	render.points = make([dynamic]Vertex_Data, 0, LINE_BATCH_SIZE)
	render.program_id = create_program_from_files("data/line.vs", "data/line.fs")
	render.projection_uniform = gl.GetUniformLocation(render.program_id, "projectionMatrix")

	vertexAttribute: u32 = 0
	colorAttribute: u32 = 1

	// Generate
	gl.GenVertexArrays(1, &render.vao_id)
	gl.GenBuffers(1, &render.vbo_id)

	gl.BindVertexArray(render.vao_id)
	gl.EnableVertexAttribArray(vertexAttribute)
	gl.EnableVertexAttribArray(colorAttribute)

	// Vertex buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_id)
	gl.BufferData(gl.ARRAY_BUFFER, LINE_BATCH_SIZE * size_of(Vertex_Data), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(
		vertexAttribute,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(Vertex_Data),
		offset_of(Vertex_Data, position),
	)
	// save bandwidth by expanding color to floats in the shader
	gl.VertexAttribPointer(
		colorAttribute,
		4,
		gl.UNSIGNED_BYTE,
		gl.TRUE,
		size_of(Vertex_Data),
		offset_of(Vertex_Data, rgba),
	)

	check_opengl()

	// Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	return render
}

@(private = "file")
destroy_line_render :: proc(render: ^Line_Render) {
	if render.vao_id != 0 {
		gl.DeleteVertexArrays(1, &render.vao_id)
		gl.DeleteBuffers(1, &render.vbo_id)
	}

	if render.program_id != 0 {
		gl.DeleteProgram(render.program_id)
	}

	delete(render.points)

	render^ = {}
}

@(private = "file")
flush_lines :: proc(render: ^Line_Render, camera: ^Camera) {
	if len(render.points) == 0 {
		return
	}
	assert(len(render.points) % 2 == 0)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(render.program_id)

	proj: [16]f32
	BuildProjectionMatrix(camera, &proj, 0.1)

	gl.UniformMatrix4fv(render.projection_uniform, 1, gl.FALSE, raw_data(&proj))

	gl.BindVertexArray(render.vao_id)

	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_id)

	base := 0
	count := len(render.points)
	for (count > 0) {
		batchCount := min(count, LINE_BATCH_SIZE)
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, batchCount * size_of(Vertex_Data), raw_data(render.points[base:]))

		gl.DrawArrays(gl.LINES, 0, i32(batchCount))

		check_opengl()

		count -= LINE_BATCH_SIZE
		base += LINE_BATCH_SIZE
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	gl.Disable(gl.BLEND)

	clear(&render.points)
}

draw_line :: proc "contextless" (draw: ^Draw, p1, p2: b2.Vec2, color: b2.HexColor) {
	context = g_context
	rgba := make_rgba8(color, 1.0)
	append(&draw.lines.points, Vertex_Data{p1, rgba})
	append(&draw.lines.points, Vertex_Data{p2, rgba})
}

@(private = "file")
create_capsules :: proc() -> Capsules {
	render: Capsules

	render.capsules = make([dynamic]Capsule, 0, CAPSULE_BATCH_SIZE)
	render.program_id = create_program_from_files("data/solid_capsule.vs", "data/solid_capsule.fs")
	render.projection_uniform = gl.GetUniformLocation(render.program_id, "projectionMatrix")
	render.pixel_scale_uniform = gl.GetUniformLocation(render.program_id, "pixelScale")

	vertexAttribute: u32 = 0
	instanceTransform: u32 = 1
	instanceRadius: u32 = 2
	instanceLength: u32 = 3
	instanceColor: u32 = 4

	// Generate
	gl.GenVertexArrays(1, &render.vao_id)
	gl.GenBuffers(2, raw_data(&render.vbo_ids))

	gl.BindVertexArray(render.vao_id)
	gl.EnableVertexAttribArray(vertexAttribute)
	gl.EnableVertexAttribArray(instanceTransform)
	gl.EnableVertexAttribArray(instanceRadius)
	gl.EnableVertexAttribArray(instanceLength)
	gl.EnableVertexAttribArray(instanceColor)

	// Vertex buffer for single capsule
	a: f32 = 1.1
	vertices := [?]b2.Vec2{{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}}
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_ids[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), raw_data(&vertices), gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertexAttribute, 2, gl.FLOAT, gl.FALSE, 0, uintptr(0))

	// Capsule buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_ids[1])
	gl.BufferData(gl.ARRAY_BUFFER, CAPSULE_BATCH_SIZE * size_of(Capsule), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(instanceTransform, 4, gl.FLOAT, gl.FALSE, size_of(Capsule), offset_of(Capsule, transform))
	gl.VertexAttribPointer(instanceRadius, 1, gl.FLOAT, gl.FALSE, size_of(Capsule), offset_of(Capsule, radius))
	gl.VertexAttribPointer(instanceLength, 1, gl.FLOAT, gl.FALSE, size_of(Capsule), offset_of(Capsule, length))
	// color will get automatically expanded to floats in the shader
	gl.VertexAttribPointer(instanceColor, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(Capsule), offset_of(Capsule, rgba))

	gl.VertexAttribDivisor(instanceTransform, 1)
	gl.VertexAttribDivisor(instanceRadius, 1)
	gl.VertexAttribDivisor(instanceLength, 1)
	gl.VertexAttribDivisor(instanceColor, 1)

	check_opengl()

	// Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	return render
}

@(private = "file")
destroy_capsules :: proc(render: ^Capsules) {
	if render.vao_id != 0 {
		gl.DeleteVertexArrays(1, &render.vao_id)
		gl.DeleteBuffers(2, raw_data(&render.vbo_ids))
	}

	if render.program_id != 0 {
		gl.DeleteProgram(render.program_id)
	}

	delete(render.capsules)
	render^ = {}
}

add_capsule :: proc "contextless" (render: ^Capsules, p1, p2: b2.Vec2, radius: f32, color: b2.HexColor) {
	context = g_context
	d := p2 - p1
	length := b2.Length(d)
	if length < 0.001 {
		fmt.printf("WARNING: sample app: capsule too short!\n")
		return
	}

	axis := b2.Vec2{d.x / length, d.y / length}
	transform := b2.Transform {
		p = b2.Lerp(p1, p2, 0.5),
		q = {c = axis.x, s = axis.y},
	}
	rgba := make_rgba8(color, 1.0)
	append(&render.capsules, Capsule{transform, radius, length, rgba})
}

@(private = "file")
flush_capsules :: proc(render: ^Capsules, camera: ^Camera) {
	count := len(render.capsules)
	if (count == 0) {
		return
	}

	gl.UseProgram(render.program_id)

	proj: [16]f32
	BuildProjectionMatrix(camera, &proj, 0.2)

	gl.UniformMatrix4fv(render.projection_uniform, 1, gl.FALSE, raw_data(&proj))
	gl.Uniform1f(render.pixel_scale_uniform, camera.height / camera.zoom)

	gl.BindVertexArray(render.vao_id)

	gl.BindBuffer(gl.ARRAY_BUFFER, render.vbo_ids[1])
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base := 0
	for count > 0 {
		batchCount := min(count, CAPSULE_BATCH_SIZE)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, batchCount * size_of(Capsule), raw_data(render.capsules[base:]))
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, i32(batchCount))
		check_opengl()

		count -= CAPSULE_BATCH_SIZE
		base += CAPSULE_BATCH_SIZE
	}

	gl.Disable(gl.BLEND)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&render.capsules)
}

@(private = "file")
create_polygons :: proc() -> Polygons {
	render: Polygons

	render.polygons = make([dynamic]Polygon, 0, POLYGON_BATCH_SIZE)
	render.programId = create_program_from_files("data/solid_polygon.vs", "data/solid_polygon.fs")
	render.projectionUniform = gl.GetUniformLocation(render.programId, "projectionMatrix")
	render.pixelScaleUniform = gl.GetUniformLocation(render.programId, "pixelScale")

	vertexAttribute: u32 = 0
	instanceTransform: u32 = 1
	instancePoint12: u32 = 2
	instancePoint34: u32 = 3
	instancePoint56: u32 = 4
	instancePoint78: u32 = 5
	instancePointCount: u32 = 6
	instanceRadius: u32 = 7
	instanceColor: u32 = 8

	// Generate
	gl.GenVertexArrays(1, &render.vaoId)
	gl.GenBuffers(2, raw_data(&render.vboIds))

	gl.BindVertexArray(render.vaoId)
	gl.EnableVertexAttribArray(vertexAttribute)
	gl.EnableVertexAttribArray(instanceTransform)
	gl.EnableVertexAttribArray(instancePoint12)
	gl.EnableVertexAttribArray(instancePoint34)
	gl.EnableVertexAttribArray(instancePoint56)
	gl.EnableVertexAttribArray(instancePoint78)
	gl.EnableVertexAttribArray(instancePointCount)
	gl.EnableVertexAttribArray(instanceRadius)
	gl.EnableVertexAttribArray(instanceColor)

	// Vertex buffer for single quad
	a: f32 = 1.1
	vertices := [?]b2.Vec2{{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}}
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vboIds[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), raw_data(&vertices), gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertexAttribute, 2, gl.FLOAT, gl.FALSE, 0, uintptr(0))

	// Polygon buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vboIds[1])
	gl.BufferData(gl.ARRAY_BUFFER, POLYGON_BATCH_SIZE * size_of(Polygon), nil, gl.DYNAMIC_DRAW)
	gl.VertexAttribPointer(instanceTransform, 4, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, transform))
	gl.VertexAttribPointer(instancePoint12, 4, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, p1))
	gl.VertexAttribPointer(instancePoint34, 4, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, p3))
	gl.VertexAttribPointer(instancePoint56, 4, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, p5))
	gl.VertexAttribPointer(instancePoint78, 4, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, p7))
	gl.VertexAttribIPointer(instancePointCount, 1, gl.INT, size_of(Polygon), offset_of(Polygon, count))
	gl.VertexAttribPointer(instanceRadius, 1, gl.FLOAT, gl.FALSE, size_of(Polygon), offset_of(Polygon, radius))
	// color will get automatically expanded to floats in the shader
	gl.VertexAttribPointer(instanceColor, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(Polygon), offset_of(Polygon, color))

	// These divisors tell glsl how to distribute per instance data
	gl.VertexAttribDivisor(instanceTransform, 1)
	gl.VertexAttribDivisor(instancePoint12, 1)
	gl.VertexAttribDivisor(instancePoint34, 1)
	gl.VertexAttribDivisor(instancePoint56, 1)
	gl.VertexAttribDivisor(instancePoint78, 1)
	gl.VertexAttribDivisor(instancePointCount, 1)
	gl.VertexAttribDivisor(instanceRadius, 1)
	gl.VertexAttribDivisor(instanceColor, 1)

	check_opengl()

	// Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	return render
}

@(private = "file")
destroy_polygons :: proc(render: ^Polygons) {
	if render.vaoId != 0 {
		gl.DeleteVertexArrays(1, &render.vaoId)
		gl.DeleteBuffers(2, raw_data(&render.vboIds))
	}

	if render.programId != 0 {
		gl.DeleteProgram(render.programId)
	}

	delete(render.polygons)
	render^ = {}
}

@(private = "file")
flush_polygons :: proc(render: ^Polygons, camera: ^Camera) {

	count := len(render.polygons)
	if (count == 0) {
		return
	}

	gl.UseProgram(render.programId)

	proj: [16]f32
	BuildProjectionMatrix(camera, &proj, 0.2)

	gl.UniformMatrix4fv(render.projectionUniform, 1, gl.FALSE, raw_data(&proj))
	gl.Uniform1f(render.pixelScaleUniform, camera.height / camera.zoom)

	gl.BindVertexArray(render.vaoId)
	gl.BindBuffer(gl.ARRAY_BUFFER, render.vboIds[1])

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base := 0
	for count > 0 {
		batchCount := min(count, POLYGON_BATCH_SIZE)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, batchCount * size_of(Polygon), raw_data(render.polygons[base:]))
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, i32(batchCount))
		check_opengl()

		count -= POLYGON_BATCH_SIZE
		base += POLYGON_BATCH_SIZE
	}

	gl.Disable(gl.BLEND)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&render.polygons)
}

draw_solid_polygon :: proc "contextless" (
	draw: ^Draw,
	transform: b2.Transform,
	vertices: [^]b2.Vec2,
	vertexCount: i32,
	radius: f32,
	color: b2.HexColor,
) {
	context = g_context
	data: Polygon
	data.transform = transform

	n := vertexCount < 8 ? vertexCount : 8
	ps := &data.p1
	for i in 0 ..< n {
		mem.ptr_offset(ps, i)^ = vertices[i]
	}

	data.count = n
	data.radius = radius
	data.color = make_rgba8(color, 1.0)

	append(&draw.polygons.polygons, data)
}

@(private = "file")
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

@(private = "file")
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

draw_screen_string :: proc(draw: ^Draw, x, y: f32, color: b2.HexColor, format: string, args: ..any) {
	text := fmt.aprintf(format, ..args)
	defer delete(text)
	draw_add_text(&draw.font, x, y, color, text)
}

// Convert from world coordinates to normalized device coordinates.
// http://www.songho.ca/opengl/gl_projectionmatrix.html
// This also includes the view transform
@(private = "file")
BuildProjectionMatrix :: proc(camera: ^Camera, m: ^[16]f32, zBias: f32) {
	ratio := camera.width / camera.height
	extents := b2.Vec2{camera.zoom * ratio, camera.zoom}

	lower := camera.center - extents
	upper := camera.center + extents
	w := upper.x - lower.x
	h := upper.y - lower.y

	m[0] = 2.0 / w
	m[1] = 0.0
	m[2] = 0.0
	m[3] = 0.0

	m[4] = 0.0
	m[5] = 2.0 / h
	m[6] = 0.0
	m[7] = 0.0

	m[8] = 0.0
	m[9] = 0.0
	m[10] = -1.0
	m[11] = 0.0

	m[12] = -2.0 * camera.center.x / w
	m[13] = -2.0 * camera.center.y / h
	m[14] = zBias
	m[15] = 1.0
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

flush_draw :: proc(draw: ^Draw, camera: ^Camera) {
	// todo

	flush_capsules(&draw.capsules, camera)
	flush_polygons(&draw.polygons, camera)
	flush_lines(&draw.lines, camera)
	flush_text(&draw.font, camera)
	check_opengl()
}

get_view_bounds :: proc(camera: ^Camera) -> b2.AABB {
	if camera.height > 0 || camera.width > 0 {
		return b2.AABB{lowerBound = b2.Vec2_zero, upperBound = b2.Vec2_zero}
	}
	return b2.AABB {
		lowerBound = convert_screen_to_world(camera, {0, camera.height}),
		upperBound = convert_screen_to_world(camera, {camera.width, 0}),
	}
}
