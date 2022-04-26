extends Node
var game:Node

# self = game.unit.attack

func _ready():
	game = get_tree().get_current_scene()


func start(unit, point):
	if unit.attacks and not unit.stunned and game.unit.move.in_bounds(point):
		if unit.ranged and unit.weapon:
			unit.weapon.look_at(point)
		
		if !unit.target:
			var neighbors = game.map.blocks.get_units_in_radius(point, 1)
			if neighbors:
				var target = closest_enemy_unit(unit, neighbors)
				var target_position = target.global_position + target.collision_position
				if target and target_position.distance_to(point) < target.collision_radius:
					game.unit.attack.set_target(unit, target)
		
		if unit.target:
			unit.look_at(point)
			unit.get_node("animations").playback_speed = unit.current_attack_speed
			unit.set_state("attack")


func set_target(unit, target):
	if not unit.target == target:
		unit.current_attack_speed = unit.attack_speed
		unit.attack_count = 0
		unit.last_target = unit.target
		unit.target = target



func closest_enemy_unit(unit, enemies):
	var sorted = game.utils.sort_by_distance(unit, enemies)
	var filtered = []
	for enemy in sorted:
		if enemy.unit.team != game.player_team:
			filtered.append(enemy.unit)
	if filtered:
		return filtered[0]


func hit(unit1):
	var att_pos = unit1.global_position + unit1.attack_hit_position
	var att_rad = unit1.attack_hit_radius
	
	# hit target
	if can_hit(unit1, unit1.target) and in_range(unit1, unit1.target):
		take_hit(unit1, unit1.target)
	
	# melee cleave damage
	if unit1.display_name in game.unit.skills.leader:
		var attacker_skills = game.unit.skills.leader[unit1.display_name]
		if "cleave" in attacker_skills:
			var neighbors = game.map.blocks.get_units_in_radius(att_pos, att_rad)
			for unit2 in neighbors:
				if can_hit(unit1, unit2) and in_range(unit1, unit2):
					take_hit(unit1, unit2, null, {"cleave": true})


func can_hit(attacker, target):
	return (
		attacker != null and
		target != null and
		target != attacker and
		target.team != attacker.team and
		is_instance_valid(attacker) and
		is_instance_valid(target) and
		not target.dead
	)


func in_range(attacker, target):
	var att_pos = attacker.global_position + attacker.attack_hit_position
	var att_rad = attacker.attack_hit_radius * attacker.current_attack_range
	var tar_pos = target.global_position + target.collision_position
	var tar_rad = target.collision_radius
	return game.utils.circle_collision(att_pos, att_rad, tar_pos, tar_rad)


func take_hit(attacker, target, projectile = null, modifiers = {}):
	modifiers = game.unit.skills.hit_modifiers(attacker, target, projectile, modifiers)
	
	if projectile:
		if not modifiers.pierce: 
			projectile_stuck(attacker, target, projectile)
		
		if projectile.targets != null and projectile.targets.find(target) < 0:
			projectile.targets.append(target)
	
	if target and target.current_hp > 0:
		if not modifiers.dodge:
			var damage = max(1, modifiers.damage - target.defense)
			#print("damage ", modifiers.damage)
			target.current_hp -= damage
			attacker.attack_count += 1
			
		if not modifiers.counter:
			game.unit.advance.react(target, attacker)
			game.unit.advance.ally_attacked(target, attacker)
			
		game.unit.orders.take_hit_retreat(attacker, target)
		if target.hud: game.unit.hud.update_hpbar(target)
		if target == game.selected_unit: game.ui.stats.update()
		
		if target.current_hp <= 0: 
			target.current_hp = 0
			target.die()
			if target.type == "leader":
				if target.team == game.player_team: game.player_deaths += 1
				else: game.enemy_deaths += 1
				if attacker.team == game.player_team: game.player_kills += 1
				else: game.enemy_kills += 1
			yield(get_tree().create_timer(0.6), "timeout")
			game.unit.attack.set_target(attacker, null)
			game.unit.advance.resume(attacker)



func projectile_release(attacker):
	if attacker.target and not attacker.target.dead:
		projectile_start(attacker, attacker.target)
		game.unit.skills.projectile_release(attacker)



func projectile_start(attacker, target):
	var target_position = target.global_position + target.collision_position
	attacker.weapon.look_at(target_position)
	var projectile = attacker.projectile.duplicate()
	var projectile_sprite = projectile.get_node("sprites")
	var a = attacker.weapon.global_rotation
	var speed = attacker.projectile_speed
	var projectile_speed = Vector2(cos(a)*speed, sin(a)*speed)
	var lifetime = attacker.attack_hit_radius / attacker.projectile_speed
	projectile.global_position = attacker.projectile.global_position
	var projectile_rotation
	if attacker.projectile_rotation:
		projectile_rotation = attacker.projectile_rotation
		if attacker.mirror:
			a -= PI
			projectile_rotation *= -1
			projectile_sprite.scale.x *= -1
	projectile.global_rotation = a
	projectile.visible = true
	projectile_sprite.visible = true
	var targets = null
	if attacker.display_name in game.unit.skills.leader:
		var attacker_skills = game.unit.skills.leader[attacker.display_name]
		if "pierce" in attacker_skills: 
			target = null
			targets = []
	game.map.add_child(projectile)
	attacker.projectiles.append({
		"target": target,
		"targets": targets,
		"node": projectile,
		"sprite": projectile_sprite,
		"speed": projectile_speed,
		"rotation": projectile_rotation,
		"lifetime": lifetime,
		"stuck":false
	})


func projectile_step(delta, projectile):
	if not projectile.stuck:
		if projectile.speed:
			projectile.node.global_position += projectile.speed * delta
		
		if projectile.rotation:
			projectile.node.global_rotation += projectile.rotation * delta


func projectile_stuck(attacker, target, projectile):
	projectile.stuck = true
	var stuck = projectile.node
	var r = projectile.node.global_rotation
	
	if target: 
		stuck.get_parent().remove_child(stuck)
		target.get_node("sprites").add_child(stuck)
		stuck.global_position = target.global_position + target.collision_position
		if target.mirror: 
			r = Vector2(cos(r),-sin(r)).angle()
		
	var a = 0.2 # angle variation
	var ra = (randf()*a*2) - a
	stuck.global_rotation = r + ra
	
	# rotating axe
	if projectile.rotation:
		stuck.global_rotation = 0 + ra
		if target:
			# fix  axe vertical hit position
			stuck.global_position += Vector2(0, projectile.speed.y * 0.033)
			# mirror stuck axe
			if target.mirror:
				stuck.global_rotation = PI + ra
				stuck.scale.x *= -1
		# offset from center
		var o = projectile.speed*-0.08
		stuck.global_position += o
	
	# stuck sprite
	stuck.get_node("sprites").frame = 1 
	# stop projectile movement
	attacker.projectiles.erase(projectile)
	# remove projectile after 1.2 sec
	yield(get_tree().create_timer(1.2), "timeout")
	stuck.get_parent().remove_child(stuck)
	stuck.queue_free()
