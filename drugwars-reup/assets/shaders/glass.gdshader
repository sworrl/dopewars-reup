shader_type canvas_item;

// Frosted "liquid glass" panel. Blurs whatever is drawn behind it (the map, other UI),
// tints it, rounds the corners with an SDF, and adds a bright rim + top sheen.
// Needs a BackBufferCopy ancestor so SCREEN_TEXTURE is populated in the Compatibility renderer.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 panel_size = vec2(600.0, 200.0);   // set per-instance to the ColorRect pixel size
uniform float corner_radius = 28.0;
uniform float blur = 3.0;                        // backdrop blur radius (screen px)
uniform vec4 tint : source_color = vec4(0.60, 0.66, 0.80, 0.22);
uniform float rim_strength = 0.30;
uniform float sheen_strength = 0.10;

float rounded_box_sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec3 blur_backdrop(vec2 suv, vec2 px) {
	// 13-tap gaussian-ish; weights sum to 1.
	vec3 c = texture(screen_tex, suv).rgb * 0.196;
	c += texture(screen_tex, suv + vec2( px.x, 0.0)).rgb * 0.118;
	c += texture(screen_tex, suv + vec2(-px.x, 0.0)).rgb * 0.118;
	c += texture(screen_tex, suv + vec2(0.0,  px.y)).rgb * 0.118;
	c += texture(screen_tex, suv + vec2(0.0, -px.y)).rgb * 0.118;
	c += texture(screen_tex, suv + px).rgb * 0.083;
	c += texture(screen_tex, suv - px).rgb * 0.083;
	c += texture(screen_tex, suv + vec2(px.x, -px.y)).rgb * 0.083;
	c += texture(screen_tex, suv + vec2(-px.x, px.y)).rgb * 0.083;
	return c;
}

void fragment() {
	vec2 p = (UV - 0.5) * panel_size;
	vec2 half_size = panel_size * 0.5;
	float d = rounded_box_sdf(p, half_size, corner_radius);
	float aa = fwidth(d) + 0.0001;
	float mask = 1.0 - smoothstep(-aa, aa, d);
	if (mask <= 0.001) {
		discard;
	}

	vec2 px = blur * SCREEN_PIXEL_SIZE;
	vec3 backdrop = blur_backdrop(SCREEN_UV, px);
	vec3 glass = mix(backdrop, tint.rgb, tint.a);

	// Bright rim near the edge.
	float rim = smoothstep(-5.0, 0.0, d);
	glass += rim_strength * rim;

	// Soft top-down sheen (light comes from above).
	float sheen = (1.0 - UV.y) * sheen_strength;
	glass += sheen;

	COLOR = vec4(glass, mask);
}
