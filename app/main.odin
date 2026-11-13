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
	Dagger,
	Straight_Sword,
	Greatsword,
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
	Tool,
	Talisman,
	Key_Item,
	Bolstering_Material,
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
	crit:            int,
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
	physical, magic, fire, lightning, holy: f32,
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
	vs_slash, strike, pierce, immunity, robustness, focus, vitality, poise: int,
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
	// fmt.println(len(eldr_file))

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
				// fmt.println(obj_section)
				obj_section, obj_section_ok := obj_section.(json.Object)
				if !obj_section_ok {
					fmt.println("Section value is not a JSON object. Assuming bad data")
					os.exit(1)
				}


				what_tier: SpoilerTier
				// defer delete(what_tier)
				switch tier_string := obj_section["tier"].(string); tier_string {
				case "Lore":
					what_tier = SpoilerTier.Lore
				case "Basic":
					what_tier = SpoilerTier.Basic
				case "LateGame":
					what_tier = SpoilerTier.LateGame
				}
				// tier: SpoilerTier
				section := Section {
					obj_section["heading"].(string),
					what_tier,
					obj_section["body"].(string),
				}

				append(&sections, section)
			}

		}

		// fmt.println(obj)
		found_at: [dynamic]Ref
		found_at_ok := "found_at" in obj
		if found_at_ok {
			obj_found_at_values, found_at_is_json_obj_ok := obj["found_at"].(json.Array)
			if !found_at_is_json_obj_ok {
				fmt.println("found_at is not an object. Assuming bad data.")
				os.exit(1)
			}

			for found_at_value in obj_found_at_values {
				// fmt.println(found_at_value)
				found_at_value, found_at_value_ok := found_at_value.(json.String)
				if !found_at_value_ok {
					fmt.println("found_at value is not a string. Assuming bad data")
					os.exit(1)
				}

				found_where: Ref
				found_where = found_at_value
				append(&found_at, found_where)
				// fmt.println(found_at_value)

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

			// fmt.println(variant_kind)
			switch variant_kind {
			case "Armor":
				// ArmorData :: struct {
				// 	slot:            ArmorSlot,
				// 	weight:          f32,
				// 	defense:         DefenseType,
				// 	resistance:      ResistanceType,
				// 	has_altered:     bool,
				// 	passive_effects: []string,
				// }
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

						if key == defense.key {
							defense.key = d_val
						}
					}
					// defense.fire = defense_value["fire"]
					fmt.println(defense_object)
				}
			// variant = ArmorData {
			//    slot,
			//    weight,
			//    defense,
			//    resistance,
			//    has_altered,
			//    passive_effects
			// }
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
			case "Item":
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

		// for result in results {
		// 	if strings.equal_fold(query, result.name) {
		// 		answer = result.description
		// 	}
		// }

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
