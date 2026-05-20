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

    l := make_lexer(src)

    // Lex untll EOF
    for {
        tok := next_token(&l)
        fmt.printf("%-12v %q\n", tok.kind, tok.value)
        if tok.kind == .EOF do break
    }
}
