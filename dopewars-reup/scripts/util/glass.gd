class_name Glass
extends RefCounted

## Liquid-glass helpers. `background()` returns a ColorRect that renders the frosted-glass
## shader (blurs whatever is drawn behind it). Place it behind panel content; it keeps its
## shader `panel_size` in sync with its own size so the rounded-corner SDF stays correct.
##
## Requires a BackBufferCopy ancestor drawn before it so SCREEN_TEXTURE is populated in the
## GL Compatibility renderer — call `ensure_backbuffer(canvas_layer)` once per HUD/overlay.

const SHADER := preload("res://assets/shaders/glass.gdshader")

static func background(tint: Color = Color(0.60, 0.66, 0.80, 0.22),
		radius: float = 28.0, blur: float = 3.0) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = Color(1, 1, 1, 1)                 # ignored by the shader
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("corner_radius", radius)
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("panel_size", Vector2(600, 200))
	cr.material = mat
	cr.resized.connect(func(): mat.set_shader_parameter("panel_size", cr.size))
	return cr

## Add a full-screen BackBufferCopy as the first child of `parent` (a CanvasLayer/Control),
## so glass shaders drawn afterward can sample the framebuffer. Idempotent.
static func ensure_backbuffer(parent: Node) -> void:
	for c in parent.get_children():
		if c is BackBufferCopy:
			return
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	parent.add_child(bbc)
	parent.move_child(bbc, 0)
