package main

import "core:encoding/json"
import "core:fmt"
import "core:os"

unpack :: proc(j: json.Value, $T: typeid) -> (T, bool) {
	value, ok := j.(T)
	if !ok {
		fmt.printf("%v is not %v. Fix it.", j, typeid_of(T))
		os.exit(1)
	}
	return value, ok
}

unpack_string_array :: proc(obj: json.Object, key: string) -> [dynamic]string {
	array_of_strings: [dynamic]string
	key_ok := key in obj
	if key_ok {
		values, values_is_array := unpack(obj[key], json.Array)

		for value in values {
			value, value_is_string := unpack(value, json.String)

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
