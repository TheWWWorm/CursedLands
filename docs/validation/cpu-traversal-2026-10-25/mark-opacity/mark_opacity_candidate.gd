extends GroundMarks
func _update(m: Mark) -> int:
	var moved := false
	if not m.foot:
		m.grow_left -= 1
		if m.grow_left < 0:
			m.grow = 0.0
		m.angle += m.spin
		moved = m.grow != 0.0 or m.spin != 0.0
	m.life -= 1
	m.a += m.grow
	m.b += m.grow
	var f := float(m.fade - m.life) / float(m.fade)
	var alpha := _decal_alpha((1.0 - maxf(f, 0.0)) * m.alpha0)
	if moved:
		_place(m)
	var previous := m.decal.modulate
	var colour := previous
	colour.a = alpha
	if colour != previous:
		m.decal.modulate = colour
		if m.projection: m.projection.material_override.set_shader_parameter("opacity",alpha)
	return m.life
