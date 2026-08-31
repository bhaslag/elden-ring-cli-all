package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
    args := os.args

    if len(args) > 1 {  
      query := strings.join(args[1:], " ")
      fmt.println(query)
      defer delete(query)
    } else {
      fmt.println("Requires one argument")
      os.exit(1)
    }
}
