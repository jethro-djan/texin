package main

import "core:fmt"
import "core:os"

main :: proc() {
    data, err := os.read_entire_file_from_path("examples/hello_world.tex", context.allocator)
    if err != os.ERROR_NONE {
        fmt.eprintln("Error: could not read file")
        os.exit(1)
    }

    defer delete(data)

    src := string(data)
    p := make_parser(src)
    defer destroy_parser(&p)

    parse_document(&p)
    report_errors(&p)
}
