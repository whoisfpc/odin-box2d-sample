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
