extends Node
var game:Node

# self = game.unit.orders

var player_lanes_orders = {}
var enemy_lanes_orders = {}
var player_leaders_orders = {}
var enemy_leaders_orders = {}

var player_tax = "low"
var enemy_tax = "low"

var player_extra_unit = "infantry"
var enemy_extra_unit = "infantry"

var conquer_time = 3
var destroy_time = 5
var collect_time = 16


func _ready():
	game = get_tree().get_current_scene()
	
const tax_gold = {
	"low": 0,
	"medium": 1,
	"high": 2
}

const tactics_extra_speed = { 
	"retreat": 0,
	"defend": -5,
	"default": 0,
	"attack": 5
}


func new_orders():
	return {
		"priority": ["pawn", "leader", "building"],
		"tactics": {
			"tactic": "default",
			"speed": 0
		}
	}


# LANES

func build_lanes():
	for lane in game.map.lanes:
		player_lanes_orders[lane] = new_orders()
		enemy_lanes_orders[lane] = new_orders()


func set_lane_tactic(tactic):
	var lane = game.selected_unit.lane
	var lane_tactics
	if game.selected_unit.team == game.player_team:
		lane_tactics = player_lanes_orders[lane].tactics
	else: lane_tactics = enemy_lanes_orders[lane].tactics
	lane_tactics.tactic = tactic
	lane_tactics.speed = tactics_extra_speed[tactic]


func set_lane_priority(priority):
	var lane = game.selected_unit.lane
	var lane_priority
	if game.selected_unit.team == game.player_team:
		lane_priority = player_lanes_orders[lane].priority
	else: lane_priority = enemy_lanes_orders[lane].priority
	lane_priority.erase(priority)
	lane_priority.push_front(priority)


func set_pawn(pawn):
	var lane = pawn.lane
	var lane_orders
	if pawn.team == game.player_team:
		lane_orders = player_lanes_orders[lane]
	else: lane_orders = enemy_lanes_orders[lane]
	pawn.tactics = lane_orders.tactics.tactic
	pawn.priority = lane_orders.priority.duplicate()


func lanes_cycle(): # called every 8 sec
	for building in game.player_buildings:
		if building.lane:
			var priority = player_lanes_orders[building.lane].priority.duplicate()
			building.priority = priority
			
	for building in game.enemy_buildings:
		if building.lane:
			var priority = enemy_lanes_orders[building.lane].priority.duplicate()
			building.priority = priority


# LEADERS

func build_leaders():
	for leader in game.player_leaders:
		player_leaders_orders[leader.name] = new_orders()
		
	for leader in game.enemy_leaders:
		enemy_leaders_orders[leader.name] = new_orders()
	
	hp_regen_cycle()


func hp_regen_cycle(): # called every second
	if not game.paused:
		for unit in game.all_units:
			if unit.regen > 0:
				set_regen(unit)
				if unit.type == "leader" and unit.team == game.player_team:
					game.ui.inventories.update_consumables(unit)
		
	yield(get_tree().create_timer(1), "timeout")
	hp_regen_cycle()


func set_regen(unit):
	if not unit.dead:
		var regen = game.unit.modifiers.get_value(unit, "regen")
		unit.heal(regen)
	else: unit.regen = 0



func leaders_cycle(): # called every 4 sec
	for leader in game.player_leaders:
		set_leader(leader, player_leaders_orders[leader.name])
		
	for leader in game.enemy_leaders:
		set_leader(leader, enemy_leaders_orders[leader.name])



func set_leader(leader, orders):
	var tactics = orders.tactics
	leader.tactics = tactics.tactic
	leader.priority = orders.priority.duplicate()
	
	var extra_unit = player_extra_unit
	if leader.team == game.enemy_team:
		extra_unit = enemy_extra_unit
	var cost
	match extra_unit:
		"infantry": cost = 1
		"archer": cost = 2
		"mounted": cost = 3
	leader.gold -= cost
	
	# get back to lane 
	if (not leader.after_arive == "conquer" and
			not leader.after_arive == "attack" and
			not leader.working and
			not leader.channeling and
			not leader.retreating and 
			not (leader.team == game.player_team and game.ui.shop.close_to_blacksmith(leader)) ): 
				
		game.unit.follow.lane(leader)



func set_leader_tactic(tactic):
	var leader = game.selected_leader
	var leader_tactics
	if game.selected_unit.team == game.player_team:
		leader_tactics = player_leaders_orders[leader.name].tactics
	else: leader_tactics = enemy_leaders_orders[leader.name].tactics
	leader_tactics.tactic = tactic
	leader_tactics.speed = tactics_extra_speed[tactic]


func set_leader_priority(priority):
	var leader = game.selected_unit
	var leader_orders
	if leader.team == game.player_team:
		leader_orders = player_leaders_orders[leader.name]
	else: leader_orders = enemy_leaders_orders[leader.name]
	var leader_priority = leader_orders.priority
	leader_priority.erase(priority)
	leader_priority.push_front(priority)



func select_target(unit, enemies):
	var n = enemies.size()
	if n == 0: return
	
	if n == 1:
		return enemies[0]
	
	var sorted = game.utils.sort_by_distance(unit, enemies)
	var closest_unit = sorted[0].unit
	
	if n == 2:
		var further_unit = sorted[1].unit
		var index1 = unit.priority.find(closest_unit.type)
		var index2 = unit.priority.find(further_unit.type)
		if index2 < index1: 
			return further_unit
			
	# n > 2
	if not unit.ranged: # melee
		return closest_unit
		
	else: # ranged
		for priority_type in unit.priority:
			for enemy in sorted:
				if enemy.unit.type == priority_type:
					return enemy.unit


func closest_unit(unit, enemies):
	var sorted = game.utils.sort_by_distance(unit, enemies)
	return sorted[0].unit



func conquer_building(unit):
	var point = unit.global_position
	point.y -= game.map.tile_size
	var building = game.utils.buildings_click(point)
	if building and building.team == "neutral" and not unit.stunned:
		unit.channel_start(conquer_time)
		yield(unit.channeling_timer, "timeout")
		# conquer
		if unit.channeling:
			unit.channeling = false
			unit.working = false
			building.channeling = false
			building.team = unit.team
			building.setup_team()
			
			 # check empty backwood
			var leaders = game.player_leaders
			if unit.team != game.player_team: leaders = game.enemy_leaders
			var oponent_has_no_buildings = true
			var oponent_team = unit.oponent_team()
			for neutral in game.map.neutrals:
				var neutral_building = game.map.get_node("buildings/"+oponent_team+"/"+neutral)
				if neutral_building.team == oponent_team:
					oponent_has_no_buildings = false
					break
			if oponent_has_no_buildings:
				# remove tax gold from conquered team
				leaders = game.player_leaders
				if oponent_team == game.enemy_team:
					leaders = game.enemy_leaders
				for leader in leaders:
					var inventory = game.ui.inventories.leaders[leader.name]
					inventory.extra_tax_gold = 0
			
			match building.display_name:
				"camp", "outpost": # allow neutral attack
					building.attacks = true
				
				"mine": # add mine gold
					for leader in leaders:
						game.ui.inventories.leaders[leader.name].extra_mine_gold = 1
			
			game.ui.show_select()


# MINE

func gold_order(button):
	var mine = button.orders.order.mine
	mine.channeling_timer.stop()
	mine.channeling_timer.wait_time = 1
	mine.channeling_timer.start()
	mine.channeling = true
	match button.orders.gold:
		"collect":
			button.counter = collect_time
			button.hint_label.text = str(collect_time)
			gold_collect_counter(button)
		"destroy":
			button.counter = destroy_time
			button.hint_label.text = str(button.counter)
			gold_destroy_counter(button)


func gold_collect_counter(button):
	var mine = button.orders.order.mine
	yield(mine.channeling_timer, "timeout")
	if button.counter > 0:
		button.counter -= 1
		button.hint_label.text = str(button.counter)
		gold_collect_counter(button)
	else:
		mine.channeling_timer.stop()
		button.disabled = false
		if mine.channeling:
			mine.channeling = false
			var leaders = game.player_leaders
			if mine.team == game.enemy_team: leaders = game.enemy_team
			for leader in leaders:
				leader.gold += floor(mine.gold / leaders.size())
			mine.gold = 0


func gold_destroy_counter(button):
	var mine = button.orders.order.mine
	yield(mine.channeling_timer, "timeout")
	if button.counter > 0:
		button.counter -= 1
		button.hint_label.text = str(button.counter)
		gold_destroy_counter(button)
	else:
		mine.channeling_timer.stop()
		button.disabled = false
		if mine.channeling:
			mine.channeling = false
			mine.gold = 0
			mine.team = "neutral"
			mine.setup_team()
			game.ui.show_select()
			for leader in game.player_leaders:
				game.ui.inventories.leaders[leader.name].extra_mine_gold = 0



# CAMP

func camp_hire(unit, team):
	if team == game.player_team:
		player_extra_unit = unit
	else: enemy_extra_unit = unit


# TAXES

func set_taxes(tax, team):
	if team == game.player_team:
		player_tax = tax
	else: enemy_tax = tax


func update_taxes():
	for leader in game.player_leaders:
		game.ui.inventories.player_leaders_inv[leader.name].extra_tax_gold = tax_gold[player_tax]
	for leader in game.enemy_leaders:
		game.ui.inventories.enemy_leaders_inv[leader.name].extra_tax_gold = tax_gold[enemy_tax] 


# RETREAT

func take_hit_retreat(attacker, target):
	match target.type:
		"leader":
			var hp = game.unit.modifiers.get_value(target, "hp")
			match target.tactics:
				"escape":
					retreat(target)
				"defensive":
					if target.current_hp < hp / 2:
						retreat(target)
				"default":
					if target.current_hp < hp / 3:
						retreat(target)


func retreat(unit):
	unit.retreating = true
	unit.current_path = []
	game.unit.attack.set_target(unit, null)
	var order
	if unit.team == game.player_team:
		order = player_leaders_orders[unit.name]
	else: order = enemy_leaders_orders[unit.name]
	set_leader(unit, order)
	var lane = unit.lane
	var path = game.map[lane].duplicate()
	if unit.team == "blue": path.invert()
	game.unit.follow.smart(unit, path, "move")
	

