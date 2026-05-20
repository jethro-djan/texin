package main

Lexer :: struct {
    src: string,
    start: int,
    pos: int,
}

Token_Kind :: enum {
    Invalid,
    Starttext,
    Stoptext,
    Text,
    Whitespace,
    EOF,
}

Token :: struct {
    kind: Token_Kind,
    value: string,
}

make_lexer :: proc(src: string) -> Lexer {
    return Lexer { 
        src = src, 
        start = 0, 
        pos = 0,
    }
}

next_token :: proc(l: ^Lexer) -> Token {
    l.start = l.pos

    // End of file
    if l.pos >= len(l.src) {
        return Token { kind = .EOF, value = "" }
    }

    // Whitespace 
    if is_whitespace(l.src[l.pos]) {
        for l.pos < len(l.src) && is_whitespace(l.src[l.pos]) {
            l.pos += 1
        }

        return Token { kind = .Whitespace, value = l.src[l.start:l.pos] }
    }

    // Commands 
    if l.src[l.pos] == '\\' {
        for l.pos < len(l.src) && !is_whitespace(l.src[l.pos]) {
            l.pos += 1
        }

        word := l.src[l.start:l.pos]
        switch word {
        case "\\starttext": return Token { kind = .Starttext, value = word }
        case "\\stoptext": return Token { kind = .Stoptext, value = word }
        case: return Token { kind = .Invalid, value = word }
        }
    }

    // Plain text 
    for l.pos < len(l.src) &&
        l.src[l.pos] != '\\' &&
        l.src[l.pos] != '{' &&
        l.src[l.pos] != '}' &&
        !is_whitespace(l.src[l.pos]) {
        l.pos += 1
    }
    
    return Token { kind = .Text, value = l.src[l.start:l.pos] }

    
}

is_whitespace :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}
