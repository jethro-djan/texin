package main

import "core:fmt"

Parser :: struct {
    lexer: Lexer,
    current: Token,
    errors: [dynamic]ParseError,
}

ParseError :: struct {
    message: string,
    token: Token,
}

make_parser :: proc(src: string) -> Parser {
    p := Parser {
        lexer = make_lexer(src),
        errors = make([dynamic]ParseError),
    }

    advance(&p)
    return p
}

destroy_parser :: proc(p: ^Parser) {
    delete(p.errors)
}

advance :: proc(p: ^Parser) {
    p.current = next_token(&p.lexer)
}

check :: proc(p: ^Parser, kind: TokenKind) -> bool {
    return p.current.kind == kind
}

expect :: proc(p: ^Parser, kind: TokenKind) -> bool {
    if check(p, kind) {
        advance(p)
        return true
    }
    record_error(p, fmt.tprintf("expected %v but got %v", kind, p.current.kind))
    return false
}

// Skip forward until we find a token to restart from 
synchronise :: proc(p: ^Parser) {
    for !check(p, .Stoptext) && !check(p, .EOF) {
        advance(p)
    }
}
 
record_error :: proc(p: ^Parser, msg: string) {
    append(&p.errors, ParseError {
        message = msg,
        token = p.current,
    })
}

// GRAMMAR RULES
parse_document :: proc(p: ^Parser) {
    parse_body(p)
    for check(p, .Whitespace) {
        advance(p)
    }
    expect(p, .EOF)
}

parse_body :: proc(p: ^Parser) {
    // Expect \starttext
    if !expect(p, .Starttext) {
        synchronise(p)
        return 
    }
    fmt.println("parse_body: got \\starttext, parsing content")

    parse_content(p)

    fmt.println("parse_body: expecting \\stoptext")
    if !expect(p, .Stoptext) {
        record_error(p, "missing \\stoptext - document was not closed")
    }
}

parse_content :: proc(p: ^Parser) {
    for !check(p, .Stoptext) && !check(p, .EOF) {
        #partial switch p.current.kind {
        case .Text, .Whitespace: 
            advance(p)
        case .Invalid:
            record_error(p, fmt.tprintf("unknown command: %q", p.current.kind))
            advance(p)
        case: 
            record_error(p, fmt.tprintf("unknown command: %q", p.current.kind))
            synchronise(p)
            return
        }

    }
    fmt.println("parse_content: done")
}

report_errors :: proc(p: ^Parser) -> bool {
    if len(p.errors) == 0 {
        fmt.println("Passed successfully.")
        return true
    }

    for err in p.errors {
        fmt.printf("Error: %s (got %q)\n", err.message, err.token.value)
    }
    return false
}


TokenKind :: enum {
    Invalid,
    EOF,

    SetupHead,
    SetupBodyfont,

    StartText,
    StopText,

    BracketOpen,
    BracketClose,

    ParagraphBreak,
    SoftNewline,

    Text,
}

Token :: struct {
    kind: TokenKind,
    lexeme: string,
    span: TextRange,
}

// AST 
Document :: struct {
    preamble: Maybe([]PreambleCommand),
    body: DocumentBody,
    span: TextRange,
}

TextRange :: struct {
    start: int,
    end: int,
}

PreambleComand :: union {
    SetupBodyfont,
    SetupHead,
}

SetupBodyfont :: struct {
    argument: BracketArgument,
    span: TextRange,
}

SetupHead :: struct {
    arguments: []BracketArgument,
    span: TextRange,
}

BracketArgument :: struct {
    text: string,
    span: TextRange,
}

DocumentBody :: struct {
    paragraphs: []Paragraph,
    span: TextRange,
}

Paragraph :: struct {
    text: string,
    span: TextRange,
}
