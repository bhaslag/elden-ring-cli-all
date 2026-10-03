package main

import "core:fmt"
import "core:os"
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
	Body,
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

Variant :: union {
	ArmorData,
	LocationData,
	WeaponData,
}

main :: proc() {
	args := os.args

	gmdsword_section := []Section {
		Section {
			"Items",
			SpoilerTier.LateGame,
			"This is the body of the great moon darksword section",
		},
	}
	test1 := Entity {
		id          = "98",
		name        = "Darkmoon Greatsword",
		description = "A big sword, it's cold",
		sections    = gmdsword_section,
	}

	ranni_section := []Section {
		Section{"Characters", SpoilerTier.Lore, "This is the body of the ranni section"},
	}
	test2 := Entity {
		id          = "654",
		name        = "Ranni",
		description = "Ranni, she's got 4 arms",
		sections    = ranni_section,
	}

	leyndel_section := []Section {
		Section{"Places", SpoilerTier.Basic, "This is the body section of Leyndel"},
	}
	test3 := Entity {
		id          = "6",
		name        = "Leyndel",
		description = "This is the description of Leyndel",
		sections    = leyndel_section,
	}

	grace_section := []Section {
		Section{"Places", SpoilerTier.Lore, "This is the body of the section for graces"},
	}
	test4 := Entity {
		id          = "10",
		name        = "Sites of grace",
		description = "This is a description of sites of grace",
		sections    = grace_section,
	}

	malenia_section := []Section {
		Section{"Bosses", SpoilerTier.Basic, "This is the body of the section"},
	}

	test5 := Entity {
		id          = "40",
		name        = "Malenia",
		description = "This is the description",
		sections    = malenia_section,
	}

	test_u: Ref = "Hellope"
	switch t in test_u {
	case string:
		#assert(type_of(t) == string)
		fmt.println("I am a string")
	case EntityHandle:
		#assert(type_of(t) == EntityHandle)
		fmt.println("EntityHandle!")
	case:
		panic("No type for this in union")
	}

	test_b := SpoilerTier.LateGame
	switch test_b {
	case .Basic:
		fmt.println("Basic!")
	case .Lore:
		fmt.println("Lore!")
	case .LateGame:
		fmt.println("Late game!")
	}

	if test_b <= .Lore {
		fmt.println("I am not late game")
	}

	results := [5]Entity{test1, test2, test3, test4, test5}
	if len(args) > 1 {
		query := strings.join(args[1:], " ")
		defer delete(query)

		answer := ""

		for result in results {
			if strings.equal_fold(query, result.name) {
				answer = result.description
			}
		}

		if answer == "" {
			recommendations: [dynamic]string
			defer delete(recommendations)
			str_build := strings.builder_make()
			defer strings.builder_destroy(&str_build)

			lower_query := strings.to_lower(query)
			defer delete(lower_query)

			for result in results {
				lower_result_name := strings.to_lower(result.name)
				defer delete(lower_result_name)

				my_lev_dist := my_levenshtein(lower_result_name, lower_query)

				if my_lev_dist < 4 {
					append(&recommendations, result.name)
				}
			}

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
