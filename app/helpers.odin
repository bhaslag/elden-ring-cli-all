package main

import "core:encoding/json"
import "core:fmt"
// sub_regions: [dynamic]Ref
// 			sub_regions_ok := "sub_regions" in obj_variant_values
// 			if sub_regions_ok {
// 				obj_sub_regions_values, sub_regions_is_json_array_ok := obj_variant_values["sub_regions"].(json.Array)
// 				if !sub_regions_is_json_array_ok {
// 					fmt.println("sub_regions is not an array. Assuming bad data")
// 					os.exit(1)
// 				}
//
// 				for sub_region_value in obj_sub_regions_values {
// 					sub_region_value, sub_region_value_ok := sub_region_value.(json.String)
// 					if !sub_region_value_ok {
// 						fmt.println("sub_region value is not a string. Assuming bad data.")
// 						os.exit(1)
// 					}
//
// 					sub_region: Ref
// 					sub_region = sub_region_value
// 					append(&sub_regions, sub_region)
// 				}
// 			}
//
// 			graces: [dynamic]string
// 			graces_ok := "graces" in obj_variant_values
// 			if graces_ok {
// 				obj_graces_values, graces_is_json_array_ok := obj_variant_values["graces"].(json.Array)
// 				if !graces_is_json_array_ok {
// 					fmt.println("graces is not an array. Assuming bad data.")
// 					os.exit(1)
// 				}
//
// 				for grace_value in obj_graces_values {
// 					grace_value, grace_value_ok := grace_value.(json.String)
// 					if !grace_value_ok {
// 						fmt.println("grace_value is not a string. Assuming bad data.")
// 						os.exit(1)
// 					}
//
// 					grace: string
// 					grace = grace_value
// 					append(&graces, grace)
// 				}
// 			}
//

unpack_string_array :: proc(obj: json.Object, key: string) -> [dynamic]string {
	array_of_strings: [dynamic]string
	key_ok := key in obj
	if key_ok {
		values, values_is_array := obj[key].(json.Array)
		if !values_is_array {
			fmt.println("key is not an array. Assuming bad data.")
		}

		for value in values {
			value, value_is_string := value.(json.String)
			if !value_is_string {
				fmt.println("value is not a string. Assuming bad data.")
			}

			string_value: string
			string_value = value
			append(&array_of_strings, string_value)
		}
	}

	return array_of_strings
}

unpack_ref_array :: proc(obj: json.Object, key: string) -> []Ref {
	strings: [dynamic]string
	strings = unpack_string_array(obj, key)
	array_of_refs := make([]Ref, len(strings))

	for string, index in strings {
		ref: Ref
		ref = string
		array_of_refs[index] = ref
	}

	return array_of_refs
}
