extends RefCounted
## Small original low-poly props, shared by menu diorama and playable sectors.
## No CSG dependencies, imported models or runtime downloads.

static var textures: Dictionary = {}
static var fonts: Dictionary = {}

static func texture(name: String) -> Texture2D:
	if not textures.has(name):
		var image := Image.load_from_file("res://assets/textures/%s.png" % name)
		image.generate_mipmaps()
		textures[name] = ImageTexture.create_from_image(image)
	return textures[name]

static func font(heading: bool = false) -> FontFile:
	var name: String = "Oswald.ttf" if heading else "IBMPlexMono-Regular.ttf"
	if not fonts.has(name):
		var resource := FontFile.new()
		resource.load_dynamic_font("res://assets/fonts/" + name)
		fonts[name] = resource
	return fonts[name]

static func material(color: Color, tex: String = "", emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.86
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if not tex.is_empty():
		mat.albedo_texture = texture(tex)
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

static func box(parent: Node3D, dimensions: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func sphere(parent: Node3D, radius: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func collision_box(parent: Node3D, dimensions: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = dimensions
	shape.shape = bounds
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body

static func sign_text(parent: Node3D, text: String, at: Vector3, size: int = 48, color: Color = Color("bbc8bc")) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font(true)
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = at
	parent.add_child(label)
	return label

static func lamp(parent: Node3D, at: Vector3, color: Color, energy: float = 1.0, light_range: float = 7.0) -> OmniLight3D:
	var body := material(Color("273436"))
	box(parent, Vector3(0.72, 0.10, 0.25), at, body)
	box(parent, Vector3(0.59, 0.035, 0.14), at + Vector3(0, -0.065, 0), material(color, "", 1.7))
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, -0.23, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	parent.add_child(light)
	return light

static func pickup(kind: String) -> Node3D:
	var root := Node3D.new()
	var dark := material(Color("20292b"))
	var silver := material(Color("9daaa5"))
	if kind == "fuse":
		cylinder(root, 0.065, 0.32, Vector3.ZERO, material(Color("e1aa54"), "", 0.75))
		for y in [-0.18, 0.18]:
			cylinder(root, 0.09, 0.08, Vector3(0, y, 0), silver)
		cylinder(root, 0.018, 0.25, Vector3(0, 0, -0.069), material(Color("ffe2a6"), "", 1.5))
	else:
		box(root, Vector3(0.20, 0.30, 0.14), Vector3.ZERO, dark)
		box(root, Vector3(0.204, 0.10, 0.144), Vector3.ZERO, material(Color("7cbaa7"), "", 0.65))
		box(root, Vector3(0.08, 0.04, 0.065), Vector3(0, 0.165, 0), silver)
		box(root, Vector3(0.07, 0.017, 0.009), Vector3(0, 0, -0.076), silver)
		box(root, Vector3(0.017, 0.07, 0.009), Vector3(0, 0, -0.076), silver)
	return root

static func taser() -> Node3D:
	var root := Node3D.new()
	root.name = "TaserModel"
	var rubber := material(Color("151c1e"))
	var steel := material(Color("59696b"))
	var yellow := material(Color("c78d40"))
	box(root, Vector3(0.13, 0.13, 0.33), Vector3(0, 0, 0), steel)
	box(root, Vector3(0.095, 0.22, 0.11), Vector3(0, -0.13, 0.075), rubber).rotation.x = -0.20
	box(root, Vector3(0.14, 0.04, 0.22), Vector3(0, 0.08, 0.008), rubber)
	box(root, Vector3(0.144, 0.047, 0.06), Vector3(0, 0.009, -0.11), yellow)
	for x in [-0.043, 0.043]:
		box(root, Vector3(0.02, 0.028, 0.095), Vector3(x, 0.02, -0.21), material(Color("bccac7")))
	var light := box(root, Vector3(0.033, 0.008, 0.055), Vector3(0, 0.108, 0), material(Color("7fe9cf"), "", 1.5))
	light.name = "Indicator"
	for y in range(5):
		box(root, Vector3(0.10, 0.01, 0.13), Vector3(0, -0.067 - y * 0.025, 0.075), steel)
	# A sleeve and gloved hand make this a held object instead of a floating gun.
	box(root, Vector3(0.17, 0.17, 0.22), Vector3(0, -0.14, 0.13), material(Color("303d3d")))
	cylinder(root, 0.095, 0.36, Vector3(0.025, -0.32, 0.20), material(Color("263333"))).rotation.x = -0.65
	return root

static func creature(kind: String = "blind") -> Dictionary:
	var root := Node3D.new()
	var cloth := material(Color("252f2e"))
	var skin := material(Color("999887"))
	var bone := material(Color("c5bea7"))
	var black := material(Color("111918"))
	var torso := cylinder(root, 0.18, 0.85, Vector3(0, 1.32, 0), cloth, 0.29)
	torso.rotation.x = -0.14
	box(root, Vector3(0.55, 0.10, 0.25), Vector3(0, 1.69, -0.08), cloth)
	cylinder(root, 0.075, 0.21, Vector3(0, 1.86, -0.15), skin)
	var head := Node3D.new()
	root.add_child(head)
	head.position = Vector3(0, 2.03, -0.18)
	sphere(head, 0.18, Vector3.ZERO, skin).scale = Vector3(0.82, 1.21, 0.95)
	if kind == "blind":
		for y in [-0.005, 0.035, 0.075]:
			box(head, Vector3(0.31, 0.047, 0.24), Vector3(0, y, -0.03), bone)
	else:
		for x in [-0.065, 0.065]:
			box(head, Vector3(0.044, 0.025, 0.022), Vector3(x, 0.03, -0.164), material(Color("e9b58b"), "", 1.3))
	box(head, Vector3(0.125, 0.115, 0.045), Vector3(0, -0.10, -0.152), black)
	for x in range(5):
		box(head, Vector3(0.015, 0.028, 0.021), Vector3(-0.046 + x * 0.023, -0.06, -0.18), bone)
	if kind == "listener":
		for x in [-0.18, 0.18]:
			sphere(head, 0.10, Vector3(x, 0.05, 0), skin).scale = Vector3(0.4, 1.8, 1)
	var arms: Array[Node3D] = []
	var legs: Array[Node3D] = []
	for side in [-1, 1]:
		var arm := Node3D.new()
		root.add_child(arm)
		arm.position = Vector3(side * 0.31, 1.68, -0.02)
		arm.rotation.z = side * 0.11
		cylinder(arm, 0.058, 0.66, Vector3(0, -0.31, 0), cloth, 0.087)
		cylinder(arm, 0.045, 0.61, Vector3(0, -0.93, 0.015), skin, 0.062)
		box(arm, Vector3(0.085, 0.14, 0.085), Vector3(0, -1.28, 0.02), skin)
		for finger in range(3):
			cylinder(arm, 0.012, 0.17, Vector3((finger - 1) * 0.034, -1.43, -0.008), skin)
		arms.append(arm)
		var leg := Node3D.new()
		root.add_child(leg)
		leg.position = Vector3(side * 0.13, 0.98, 0.03)
		cylinder(leg, 0.09, 0.45, Vector3(0, -0.22, 0), cloth, 0.12)
		cylinder(leg, 0.065, 0.41, Vector3(0, -0.64, 0), cloth, 0.088)
		box(leg, Vector3(0.14, 0.14, 0.30), Vector3(0, -0.88, -0.07), black)
		legs.append(leg)
	return {"root": root, "head": head, "arms": arms, "legs": legs}

static func airlock(parent: Node3D, code: String) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var frame := material(Color("414e4f"), "metal")
	var door_mat := material(Color("a0b0ab"), "metal")
	var hazard_mat := material(Color.WHITE, "hazard")
	for x in [-1.08, 1.08]:
		box(root, Vector3(0.18, 2.65, 0.27), Vector3(x, 1.325, 0), frame)
	box(root, Vector3(2.36, 0.22, 0.27), Vector3(0, 2.64, 0), frame)
	box(root, Vector3(2.0, 0.05, 0.4), Vector3(0, 0.035, 0), hazard_mat)
	# All geometry attached to a leaf moves with it on opening.
	var leaves: Array[Node3D] = []
	for side in [-1, 1]:
		var leaf := Node3D.new()
		root.add_child(leaf)
		leaf.position.x = side * 0.5
		box(leaf, Vector3(0.985, 2.48, 0.15), Vector3(0, 1.25, 0), door_mat)
		box(leaf, Vector3(0.052, 2.43, 0.18), Vector3(-side * 0.47, 1.25, 0), hazard_mat)
		box(leaf, Vector3(0.97, 0.15, 0.025), Vector3(0, 0.8, 0.092), hazard_mat)
		leaves.append(leaf)
	box(root, Vector3(0.34, 0.46, 0.16), Vector3(1.37, 1.28, 0), frame)
	var status := box(root, Vector3(0.20, 0.13, 0.02), Vector3(1.37, 1.36, 0.095), material(Color("d76847"), "", 1.5))
	sign_text(root, code + " / ШЛЮЗ", Vector3(0, 2.92, 0.07), 44)
	var lamp_node := lamp(root, Vector3(0, 2.48, 0.26), Color("d64e35"), 1.1, 6)
	return {"root": root, "leaves": leaves, "status": status, "light": lamp_node}
