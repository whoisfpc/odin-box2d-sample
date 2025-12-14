package main

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

Draw :: struct {}

draw_create :: proc() -> ^Draw {
	draw := new(Draw)
	return draw
}

draw_destroy :: proc(draw: ^Draw) {
	free(draw)
}
