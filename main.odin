package main

import "core:fmt"
import "core:os"
import "parser"

main :: proc() {
    data, err := os.read_entire_file_from_path("./examples/hello_world_with_simple_preamble.tex", context.allocator)
    if err != os.ERROR_NONE {
        fmt.eprintln("Error: could not read file")
        os.exit(1)
    }

    defer delete(data)

    src := string(data)
    p := parser.make_parser(src)
    defer parser.destroy_parser(&p)

    doc := parser.parse_document(&p)
    parser.print_node_document(doc)
    parser.report_errors(&p)
}
