package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"

Test :: struct {
	name:  string,
	blurb: string,
}

EntityHandle :: distinct int

Ref :: union {
	EntityHandle,
	string,
}

SpoilerTier :: enum {
	Basic,
	Lore,
	LateGame,
}

WeaponClass :: enum {
	Axe,
	Backhand_Blade,
	Ballista,
	Beast_Claw,
	Bow,
	Claw,
	Colossal_Sword,
	Colossal_Weapon,
	Crossbow,
	Curved_Greatsword,
	Curved_Sword,
	Dagger,
	Fist,
	Flail,
	Glintstone_Staff,
	Great_Hammer,
	Great_Katana,
	Great_Spear,
	Greataxe,
	Greatbow,
	Greatshield,
	Greatsword,
	Halberd,
	Hammer,
	Hand_to_Hand,
	Heavy_Thrusting_Sword,
	Katana,
	Light_Bow,
	Light_Greatsword,
	Medium_Shield,
	Perfume_Bottle,
	Reaper,
	Sacred_Seal,
	Small_Shield,
	Spear,
	Straight_Sword,
	Throwing_Blade,
	Thrusting_Shield,
	Thrusting_Sword,
	Torch,
	Twinblade,
	Whip,
}

AttackType :: enum {
	None,
	Standard,
	Slash,
	Pierce,
}

ArmorSlot :: enum {
	Head,
	Chest,
	Arms,
	Legs,
}

ItemCategory :: enum {
	Key_Item,
	Tool,
	Talisman,
	Incantation,
	Sorcery,
	Crafting_Material,
	Bolstering_Material,
	Ash_of_War,
	Spirit_Ashes,
	Ammo,
}

LocationData :: struct {
	region:            Ref,
	sub_regions:       []Ref,
	graces:            []string,
	is_legacy_dungeon: bool,
	is_optional:       bool,
	map_fragment:      string,
	bosses:            []Ref,
	npcs:              []Ref,
	notable_loot:      []Ref,
}

WeaponData :: struct {
	class:           WeaponClass,
	attack_type:     AttackType,
	weight:          f32,
	attack:          Attack,
	guard:           Guard,
	scaling:         Scaling,
	requirements:    Requirements,
	skill:           string,
	passive_effects: []string,
}

Section :: struct {
	heading: string,
	tier:    SpoilerTier,
	body:    string,
}

Entity :: struct {
	id:          string,
	name:        string,
	image:       string,
	description: string,
	sections:    []Section,
	found_at:    []Ref,
	variant:     Variant,
}

Attack :: struct {
	physical, magic, fire, lightning, holy, critical: f32,
}

Guard :: struct {
	physical_guarded,
	magic_guarded,
	fire_guarded,
	lightning_guarded,
	holy_guarded,
	guard_boost: f32,
}

Scaling :: struct {
	str, dex, int_scale, fai, arc: Grade,
}

Grade :: enum {
	None,
	S,
	A,
	B,
	C,
	D,
	E,
}

Requirements :: struct {
	str, dex, int_req, fai, arc: int,
}

DefenseType :: struct {
	physical, magic, fire, lightning, holy: f32,
}

ResistanceType :: struct {
	slash, strike, pierce, immunity, robustness, focus, vitality, poise: int,
}

ArmorData :: struct {
	slot:            ArmorSlot,
	weight:          f32,
	defense:         DefenseType,
	resistance:      ResistanceType,
	has_altered:     bool,
	passive_effects: []string,
}

ItemData :: struct {
	category:              ItemCategory,
	effect:                string,
	fp_cost:               int,
	slots_used:            int,
	spell_reqs:            Requirements,
	weight:                f32,
	required_items:        []Ref,
	buy_price, sell_price: int,
	tiers:                 []Tier,
}

Tier :: struct {
	label, detail: string,
}

Resistances :: struct {
	res_standard,
	res_slash,
	res_strike,
	res_pierce,
	res_magic,
	res_fire,
	res_lightning,
	res_holy,
	res_poison,
	res_rot,
	res_frost,
	res_bleed,
	res_sleep,
	res_madness,
	res_death: f32,
}

Combat :: struct {
	hp:          int,
	poise:       int,
	resistances: Resistances,
	weaknesses:  []string,
	phases:      int,
	moveset:     []string,
	drops:       []Ref,
	runes:       int,
	stats:       struct {
		str, dex, int_stat, fai, arc, vig, mnd, end: int,
		class:                                       string,
	},
}

Quest :: struct {
	questline: []string,
	shop:      []Ref,
}

CharacterData :: struct {
	title:                             string,
	aka:                               []string,
	role:                              string,
	race, affiliation, classification: string,
	voice:                             string,
	relations:                         []Ref,
	combat_facet:                      Maybe(Combat),
	quest_facet:                       Maybe(Quest),
}

Variant :: union {
	ArmorData,
	LocationData,
	WeaponData,
	ItemData,
	CharacterData,
}

main :: proc() {
	args := os.args
	eldr_file := #load("../data/entities.json")
	json_data, err := json.parse(eldr_file)

	if err != .None {
		fmt.eprintln("Failed to parse the json file.")
		fmt.eprintln("Error:", err)
	}

	defer json.destroy_value(json_data)

	root := json_data

	json_array, array_ok := root.(json.Array)

	if !array_ok {
		fmt.println("JSON is not an array. Assuming bad data.")
		os.exit(1)
	}

	entities: [dynamic]Entity
	defer delete(entities)

	for obj in json_array {
		obj, obj_ok := obj.(json.Object)

		if !obj_ok {
			fmt.println("JSON element is not an object. Assuming bad data.")
			os.exit(1)
		}

		sections: [dynamic]Section
		defer delete(sections)

		sections_ok := "sections" in obj
		if sections_ok {
			obj_sections, sections_is_json_obj_ok := obj["sections"].(json.Array)
			if !sections_is_json_obj_ok {
				fmt.println("Sections is not an object. Assuming bad data.")
				os.exit(1)
			}


			for obj_section in obj_sections {
				obj_section, obj_section_ok := obj_section.(json.Object)
				if !obj_section_ok {
					fmt.println("Section value is not a JSON object. Assuming bad data")
					os.exit(1)
				}

				what_tier: SpoilerTier
				switch tier_string := obj_section["tier"].(string); tier_string {
				case "Lore":
					what_tier = SpoilerTier.Lore
				case "Basic":
					what_tier = SpoilerTier.Basic
				case "LateGame":
					what_tier = SpoilerTier.LateGame
				}

				section := Section {
					obj_section["heading"].(string),
					what_tier,
					obj_section["body"].(string),
				}

				append(&sections, section)
			}
		}

		found_at: [dynamic]Ref
		found_at_ok := "found_at" in obj
		if found_at_ok {
			obj_found_at_values, found_at_is_json_obj_ok := obj["found_at"].(json.Array)
			if !found_at_is_json_obj_ok {
				fmt.println("found_at is not an object. Assuming bad data.")
				os.exit(1)
			}

			for found_at_value in obj_found_at_values {
				found_at_value, found_at_value_ok := found_at_value.(json.String)

				if !found_at_value_ok {
					fmt.println("found_at value is not a string. Assuming bad data")
					os.exit(1)
				}

				found_where: Ref
				found_where = found_at_value
				append(&found_at, found_where)
			}
		}

		variant: Variant
		variant_ok := "variant" in obj
		if variant_ok {
			_, obj_variant_value_is_null := obj["variant"].(json.Null)
			if obj_variant_value_is_null {
				continue
			}

			obj_variant_values, obj_variant_values_is_json_obj_ok := obj["variant"].(json.Object)
			if !obj_variant_values_is_json_obj_ok {
				fmt.println("variant is not an object. Assuming bad data.")
				os.exit(1)
			}

			variant_kind_value, variant_kind_ok := obj_variant_values["kind"]
			if !variant_kind_ok {
				fmt.println("variant_kind is not there. Assuming bad data.")
				os.exit(1)
			}

			variant_kind, variant_kind_value_ok := variant_kind_value.(json.String)

			switch variant_kind {
			case "Armor":
				slot: ArmorSlot
				slot_exists := "slot" in obj_variant_values
				if slot_exists {
					slot_value, slot_value_is_string := obj_variant_values["slot"].(json.String)
					if !slot_value_is_string {
						fmt.println("slot_value is not a string. Assuming bad data. Fix it.")
						os.exit(1)
					}

					e_slot, e_slot_ok := reflect.enum_from_name(ArmorSlot, slot_value)
					if !e_slot_ok {
						continue
					}

					slot = e_slot
				}

				weight: f32
				weight_exists := "weight" in obj_variant_values
				if weight_exists {
					weight_value, weight_is_f64 := obj_variant_values["weight"].(json.Float)
					if !weight_is_f64 {
						fmt.println("weight_value is not f64. Fix it.")
						os.exit(1)
					}

					weight = f32(weight_value)
				}

				defense: DefenseType
				defense_exists := "defense" in obj_variant_values
				if defense_exists {
					defense_object, defense_is_object := unpack(
						obj_variant_values["defense"],
						json.Object,
					)

					for key, value in defense_object {
						d_val, _ := unpack(defense_object[key], json.Float)

						if key == "physical" {
							defense.physical = f32(d_val)
						}

						if key == "magic" {
							defense.magic = f32(d_val)
						}

						if key == "fire" {
							defense.fire = f32(d_val)
						}

						if key == "lightning" {
							defense.lightning = f32(d_val)
						}

						if key == "holy" {
							defense.holy = f32(d_val)
						}
					}
				}

				resistance: ResistanceType
				res_exists := "resistance" in obj_variant_values

				if res_exists {
					res_obj, _ := unpack(obj_variant_values["resistance"], json.Object)

					for key, value in res_obj {
						res_val, _ := unpack(res_obj[key], json.Float)

						if key == "slash" {
							resistance.slash = int(res_val)
						}

						if key == "strike" {
							resistance.strike = int(res_val)
						}

						if key == "pierce" {
							resistance.pierce = int(res_val)
						}

						if key == "immunity" {
							resistance.immunity = int(res_val)
						}

						if key == "robustness" {
							resistance.robustness = int(res_val)
						}

						if key == "focus" {
							resistance.focus = int(res_val)
						}

						if key == "vitality" {
							resistance.vitality = int(res_val)
						}

						if key == "poise" {
							resistance.poise = int(res_val)
						}
					}
				}

				has_altered: bool
				has_alt := "has_altered" in obj_variant_values
				if has_alt {
					has_altered = has_alt
				}

				passive_effects: [dynamic]string
				passive_effects = unpack_string_array(obj_variant_values, "passive_effects")

				variant = ArmorData {
					slot,
					weight,
					defense,
					resistance,
					has_altered,
					passive_effects[:],
				}

			case "Location":
				region: Ref
				region_is_ok := "region" in obj_variant_values
				if region_is_ok {
					region_value, region_value_ok := obj_variant_values["region"].(json.String)
					if !region_value_ok {
						fmt.println("region_value is not a string. Assuming bad data")
					}

					region = region_value
				}

				sub_regions: []Ref
				sub_regions = unpack_ref_array(obj_variant_values, "sub_regions")

				graces: [dynamic]string
				graces = unpack_string_array(obj_variant_values, "graces")

				is_legacy_dungeon, is_optional: bool
				legacy_dung := "is_legacy_dungeon" in obj_variant_values
				if legacy_dung {
					is_legacy_dungeon = legacy_dung
				}

				dung_optional := "is_optional" in obj_variant_values
				if dung_optional {
					is_optional = dung_optional
				}

				map_fragment: string
				frag_ok := "map_fragment" in obj_variant_values
				if frag_ok {
					obj_frag_value, obj_frag_value_ok := obj_variant_values["map_fragment"].(json.String)

					if !obj_frag_value_ok {
						fmt.println("Map fragment value is not a string. Assuming bad data")
						os.exit(1)
					}

					map_fragment = obj_frag_value
				}

				bosses: []Ref
				bosses = unpack_ref_array(obj_variant_values, "bosses")

				npcs: []Ref
				npcs = unpack_ref_array(obj_variant_values, "npcs")

				notable_loot: []Ref
				notable_loot = unpack_ref_array(obj_variant_values, "notable_loot")

				variant = LocationData {
					region,
					sub_regions[:],
					graces[:],
					is_legacy_dungeon,
					is_optional,
					map_fragment,
					bosses[:],
					npcs[:],
					notable_loot[:],
				}

			case "Weapon":
				class: WeaponClass
				class_exists := "weapon_class" in obj_variant_values
				if class_exists {
					wep_val, _ := unpack(obj_variant_values["weapon_class"], string)

					e_wep_class, e_wep_class_ok := reflect.enum_from_name(WeaponClass, wep_val)
					if !e_wep_class_ok {
						continue
					}

					class = e_wep_class
				}

				attack_type: AttackType
				attack_t_exists := "attack_type" in obj_variant_values
				if attack_t_exists {
					attack_t_val, _ := unpack(obj_variant_values["attack_type"], string)

					e_attack_t, e_attack_t_ok := reflect.enum_from_name(AttackType, attack_t_val)
					if !e_attack_t_ok {
						continue
					}

					attack_type = e_attack_t
				}

				weight: f32
				weight_exists := "weight" in obj_variant_values
				if weight_exists {
					weight_val, _ := unpack(obj_variant_values["weight"], json.Float)
					weight = f32(weight_val)
				}

				attack: Attack
				attack_exists := "attack" in obj_variant_values
				if attack_exists {
					attack_obj, _ := unpack(obj_variant_values["attack"], json.Object)

					for key, value in attack_obj {
						attack_val, _ := unpack(attack_obj[key], json.Float)

						if key == "physical" {
							attack.physical = f32(attack_val)
						}

						if key == "magic" {
							attack.magic = f32(attack_val)
						}

						if key == "fire" {
							attack.fire = f32(attack_val)
						}

						if key == "lightning" {
							attack.lightning = f32(attack_val)
						}

						if key == "holy" {
							attack.holy = f32(attack_val)
						}

						if key == "critical" {
							attack.critical = f32(attack_val)
						}
					}
				}

				guard: Guard
				guard_exists := "guard" in obj_variant_values
				if guard_exists {
					guard_obj, _ := unpack(obj_variant_values["guard"], json.Object)

					for key, value in guard_obj {
						guard_val, _ := unpack(value, json.Float)

						if key == "physical" {
							guard.physical_guarded = f32(guard_val)
						}

						if key == "magic" {
							guard.magic_guarded = f32(guard_val)
						}

						if key == "fire" {
							guard.fire_guarded = f32(guard_val)
						}

						if key == "lightning" {
							guard.lightning_guarded = f32(guard_val)
						}

						if key == "holy" {
							guard.holy_guarded = f32(guard_val)
						}

						if key == "boost" {
							guard.guard_boost = f32(guard_val)
						}
					}
				}

				scaling: Scaling
				scaling_exists := "scaling" in obj_variant_values

				if scaling_exists {
					scaling_obj, _ := unpack(obj_variant_values["scaling"], json.Object)
					grade: Grade

					for key, value in scaling_obj {
						scaling_val, _ := unpack(value, string)

						if scaling_val == "-" {
							grade = Grade.None
						} else {
							grade, grade_ok := reflect.enum_from_name(Grade, scaling_val)

							if !grade_ok {
								fmt.println(
									"Something's wrong with the grade in scaling. Check it",
								)
							}
						}

						if key == "str" {
							scaling.str = grade
						}

						if key == "dex" {
							scaling.dex = grade
						}

						if key == "int" {
							scaling.int_scale = grade
						}

						if key == "fai" {
							scaling.fai = grade
						}

						if key == "arc" {
							scaling.arc = grade
						}
					}
				}

				requirements: Requirements
				req_exists := "requirements" in obj_variant_values

				if req_exists {
					req_obj, _ := unpack(obj_variant_values["requirements"], json.Object)

					for key, value in req_obj {
						req_val, _ := unpack(value, json.Float)

						if key == "str" {
							requirements.str = int(req_val)
						}

						if key == "dex" {
							requirements.dex = int(req_val)
						}

						if key == "int" {
							requirements.int_req = int(req_val)
						}

						if key == "fai" {
							requirements.fai = int(req_val)
						}

						if key == "arc" {
							requirements.arc = int(req_val)
						}
					}
				}

				skill: string
				skill_exists := "skill" in obj_variant_values

				if skill_exists {
					skill_val, _ := unpack(obj_variant_values["skill"], json.String)
					skill = skill_val
				}

				passive_effects: [dynamic]string
				passive_effects = unpack_string_array(obj_variant_values, "passive_effects")

				variant = WeaponData {
					class,
					attack_type,
					weight,
					attack,
					guard,
					scaling,
					requirements,
					skill,
					passive_effects[:],
				}

			case "Item":
				// ItemData :: struct {
				// 	category:              ItemCategory,
				// 	effect:                string,
				// 	fp_cost:               int,
				// 	slots_used:            int,
				// 	spell_reqs:            Requirements,
				// 	weight:                f32,
				// 	required_items:        []Ref,
				// 	buy_price, sell_price: int,
				// 	tiers:                 []Tier,
				// }

				category: ItemCategory
				cat_exists := "category" in obj_variant_values
				if cat_exists {
					cat_val, _ := unpack(obj_variant_values["category"], string)

					e_cat, e_cat_ok := reflect.enum_from_name(ItemCategory, cat_val)
					if !e_cat_ok {
						continue
					}

					category = e_cat
				}

				effect: string
				effect_exists := "effect" in obj_variant_values

				if effect_exists {
					eff_val, eff_val_ok := unpack(obj_variant_values["effect"], json.String)

					if !eff_val_ok {
						continue
					}

					effect = eff_val
				}

				fp_cost, slots_used: int
				fp_exists := "fp_cost" in obj_variant_values

				if fp_exists {
					fp_val, fp_ok := unpack(obj_variant_values["fp_cost"], json.Float)

					if !fp_ok {
						continue
					}

					fp_cost = int(fp_val)
				}

				slots_u_exists := "slots_used" in obj_variant_values

				if slots_u_exists {
					slots_u_val, slots_ok := unpack(obj_variant_values["slots_used"], json.Float)

					if !slots_ok {
						continue
					}

					slots_used = int(slots_u_val)
				}

				spell_reqs: Requirements
				spell_r_exists := "spell_reqs" in obj_variant_values

				if spell_r_exists {
					spell_r_obj, _ := unpack(obj_variant_values["spell_reqs"], json.Object)

					for key, value in spell_r_obj {
						req_val, _ := unpack(value, json.Float)

						if key == "str" {
							spell_reqs.str = int(req_val)
						}

						if key == "dex" {
							spell_reqs.dex = int(req_val)
						}

						if key == "int" {
							spell_reqs.int_req = int(req_val)
						}

						if key == "fai" {
							spell_reqs.fai = int(req_val)
						}

						if key == "arc" {
							spell_reqs.arc = int(req_val)
						}
					}
				}
			// variant = ItemData {category, effect, fp_cost, slots_used, spell_reqs, weight, required_items, buy_price, sell_price, tiers}
			case "Character":
			}


			// fmt.println(found_at_value)

		}
		// fmt.println(entities)
		// eldr_entity := Entity {
		// obj["id"].(string),
		// obj["name"].(string),
		// obj["image"].(string),
		// obj["description"].(string),
		// sections[:],
		// found_at[:],
		// variant,
		// }

		// append(&entities, eldr_entity)
	}


	if len(args) > 1 {
		query := strings.join(args[1:], " ")
		defer delete(query)

		answer := ""
		if answer == "" {
			recommendations: [dynamic]string
			defer delete(recommendations)
			str_build := strings.builder_make()
			defer strings.builder_destroy(&str_build)

			lower_query := strings.to_lower(query)
			defer delete(lower_query)

			// for result in results {
			// 	lower_result_name := strings.to_lower(result.name)
			// 	defer delete(lower_result_name)
			//
			// 	my_lev_dist := my_levenshtein(lower_result_name, lower_query)
			//
			// 	if my_lev_dist < 4 {
			// 		append(&recommendations, result.name)
			// 	}
			// }

			if len(recommendations) > 0 {
				strings.write_string(&str_build, "No results. Did you mean:")

				for rec in recommendations {
					strings.write_string(&str_build, "\n")
					strings.write_string(&str_build, rec)
				}

				final := strings.to_string(str_build)
				fmt.println(final)
			} else {
				fmt.println("No results")
			}
		} else {
			fmt.println(answer)
		}
	} else {
		fmt.println("Requires one argument")
		os.exit(1)
	}
}

my_levenshtein :: proc(a, b: string) -> (res: int) {
	// If either string is empty, the cost is inserting all runes
	// from the other
	rune_1, rune_2 := utf8.rune_count_in_string(a), utf8.rune_count_in_string(b)

	costs_a, costs_b, costs_c: int
	len_a := len(a)
	len_b := len(b)

	if (rune_1 == 0) {
		return rune_2
	}

	if (rune_2 == 0) {
		return rune_1
	}

	// If last letters are the same, the cost is whatever is
	// required to edit the rest of the strings
	if (a[len_a - 1] == b[len_b - 1]) {
		return my_levenshtein(a[0:len_a - 1], b[0:len_b - 1])
	}

	costs_a = my_levenshtein(a[0:len_a - 1], b[0:len_b - 1]) // substitute
	costs_b = my_levenshtein(a[0:len_a - 1], b) // delete last letter a
	costs_c = my_levenshtein(a, b[0:len_b - 1]) // delete last letter

	return 1 + min(costs_a, costs_b, costs_c)
}
