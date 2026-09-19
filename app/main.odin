package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

Test :: struct {
  name: string,
  blurb: string,
}

main :: proc() {
    args := os.args

    test1 := Test{name="Malenia", blurb="A very hard boss"}
    test2 := Test{name="Ranni", blurb="Has four arms"}
    test3 := Test{name="sites of grace", blurb="You save the game here"}
    test4 := Test{name="sites of graace", blurb="You save something here"}
    
    results := [4]Test{test1, test2, test3, test4}
    if len(args) > 1 {
      query := strings.join(args[1:], " ")
      defer delete(query)
      
      answer := ""

      for result in results {
        if strings.equal_fold(query, result.name) {
          answer = result.blurb
        }
      }

      if answer == "" {
        recommendations: [dynamic]string
        defer delete(recommendations)
        str_build := strings.builder_make()
        defer strings.builder_destroy(&str_build)

        lower_query :=  strings.to_lower(query)
        defer delete(lower_query)

        for result in results {
          lower_result_name := strings.to_lower(result.name)
          defer delete(lower_result_name)

          lev_dist := strings.levenshtein_distance(lower_result_name, lower_query);
          my_dist := my_levenshtein(lower_result_name, "ranni")
          fmt.println(my_dist)
          fmt.println(lev_dist)
          if lev_dist < 4 {
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

my_levenshtein :: proc(a,b: string) -> (res: int) {
  rune_1, rune_2 := utf8.rune_count_in_string(a), utf8.rune_count_in_string(b)

  costs: int

  if (rune_1 == 0) {
    return rune_2
  } 

  if (rune_2 == 0) {
    return rune_1
  }

  // fmt.println(a[len(a)-1])
  // fmt.println(b[len(b)-1])
  
  if rune_1 == 0 && rune_2 == 0 {
    return 0 
  } 

  if (a[len(a)-1] == b[len(b)-1]) {
    return my_levenshtein(a[0:len(a)-1], b[0:len(b)-1]) 
  }

  return costs
}
