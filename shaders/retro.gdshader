shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float brightness : hint_range(0.7, 1.7) = 1.0;
uniform float fear : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float effects : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_size : hint_range(1.0, 4.0) = 1.6;

float random_value(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid = resolution / pixel_size;
	vec2 uv = (floor(SCREEN_UV * grid) + 0.5) / grid;
	vec3 col = texture(screen_texture, uv).rgb;
	vec2 center = SCREEN_UV - vec2(0.5);
	float vignette = smoothstep(0.26, 0.73, length(center * vec2(0.96, 1.1)));
	col *= 1.0 - vignette * (0.60 + fear * 0.16);
	float grain = random_value(floor(SCREEN_UV * resolution / 1.5) + fract(TIME) * 97.0) - 0.5;
	col += grain * 0.029 * effects;
	col *= 1.0 - (sin(SCREEN_UV.y * resolution.y * 3.14159) * 0.018 + 0.018) * effects;
	col += vec3(0.12, 0.015, 0.002) * vignette * fear;
	col *= brightness;
	COLOR = vec4(mix(col, vec3(0.006, 0.009, 0.012), fade), 1.0);
}
