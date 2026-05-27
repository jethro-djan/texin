package parser

import "core:strings"
import "core:fmt"

// === LEXER ===

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

Lexer :: struct {
    src: string,
    start: int,
    pos: int,
}

make_lexer :: proc(src: string) -> Lexer {
    return Lexer { 
        src = src, 
        start = 0, 
        pos = 0,
    }
}

next_token :: proc(l: ^Lexer) -> Token {
    // Skip whitespaces and tabs only (NOT new lines)
    for l.pos < len(l.src) && (l.src[l.pos] == ' ' || l.src[l.pos] == '\t') {
        l.pos += 1
    }

    l.start = l.pos

    // End of file
    if l.pos >= len(l.src) {
        return make_token(l, .EOF)
    }

    ch := l.src[l.pos]

    // Distinguish between '\n' and '\n\n'
    if ch == '\n' {
        l.pos += 1
        if l.pos < len(l.src) && l.src[l.pos] == '\n' {
            l.pos += 1
            return make_token(l, .ParagraphBreak)
        }
        return make_token(l, .SoftNewline)
    }

    if ch == '[' { l.pos += 1; return make_token(l, .BracketOpen) }
    if ch == ']' { l.pos += 1; return make_token(l, .BracketClose) }

    // Commands 
    if l.src[l.pos] == '\\' {
        l.pos += 1
        for l.pos < len(l.src) && is_letter(l.src[l.pos]) {
            l.pos += 1
        }
        word := l.src[l.start:l.pos]
        switch word {
        case "\\starttext": return make_token(l, .StartText)
        case "\\stoptext": return make_token(l, .StopText)
        case "\\setuphead": return make_token(l, .SetupHead)
        case "\\setupbodyfont": return make_token(l, .SetupBodyfont)
        case: return make_token(l, .Invalid)
        }
    }

    // Plain text 
    for l.pos < len(l.src) && is_text_char(l.src[l.pos]) {
        l.pos += 1
    }
    return make_token(l, .Text)
}

// === HELPERS ===

make_token :: proc(l: ^Lexer, kind: TokenKind) -> Token {
    return Token {
        kind = kind,
        lexeme = l.src[l.start:l.pos],
        span = TextRange { start = l.start, end = l.pos },
    }
}

is_letter :: proc(c: byte) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

is_text_char :: proc(c: byte) -> bool {
    return c != '\\' && c != '[' && c != ']' && 
    c != '{' && c != '}' && c != '\n'
}

// === PARSER ===

Parser :: struct {
    tokens: []Token,
    current: int,
    errors: [dynamic]ParseError,
}

ParseError :: struct {
    message: string,
    span: TextRange,
    got: TokenKind,
}

tokenise :: proc(src: string) -> []Token {
    lexer := make_lexer(src)
    tokens := make([dynamic]Token)
    for {
        tok := next_token(&lexer)
        append(&tokens, tok)
        if tok.kind == .EOF do break
    }
    return tokens[:]
}

make_parser :: proc(src: string) -> Parser {
    p := Parser {
        tokens = tokenise(src),
        current = 0,
        errors = make([dynamic]ParseError),
    }
    return p
}

destroy_parser :: proc(p: ^Parser) {
    delete(p.tokens)
    delete(p.errors)
}

check :: proc(p: ^Parser, kind: TokenKind) -> bool {
    return peek(p).kind == kind 
}

peek :: proc(p: ^Parser) -> Token {
    return p.tokens[p.current]
}

advance :: proc(p: ^Parser) -> Token {
    tok := p.tokens[p.current]
    if tok.kind != .EOF do p.current += 1
    return tok
}

expect :: proc(p: ^Parser, kind: TokenKind) -> (Token, bool) {
    if check(p, kind) {
        return advance(p), true
    }
    record_error(p, fmt.tprintf("expected %v but got %v", kind, peek(p).kind))
    return peek(p), false
}

// Skip forward until we find a token to restart from 
synchronise :: proc(p: ^Parser) {
    for !check(p, .StopText) && !check(p, .EOF) {
        advance(p)
    }
}
 
record_error :: proc(p: ^Parser, msg: string) {
    tok := peek(p)
    append(&p.errors, ParseError {
        message = msg,
        span = tok.span,
        got = tok.kind,
    })
}


// === AST ===

Document :: struct {
    preamble: Maybe([]PreambleCommand),
    body: DocumentBody,
    span: TextRange,
}

TextRange :: struct {
    start: int,
    end: int,
}

PreambleCommand :: union {
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

// GRAMMAR RULES
parse_document :: proc(p: ^Parser) -> Document {
    start := peek(p).span.start
    preamble := parse_preamble(p)
    body := parse_body(p)

    for check(p, .SoftNewline) || check(p, .ParagraphBreak) {
        advance(p)
    }

    expect(p, .EOF)

    pre: Maybe([]PreambleCommand)
    if len(preamble) > 0 do pre = preamble[:]

    return Document {
        preamble = pre,
        body = body,
        span = TextRange {start = start, end = peek(p).span.end}
    }
}

parse_preamble :: proc(p: ^Parser) -> [dynamic]PreambleCommand {
    commands := make([dynamic]PreambleCommand)
    for {
        for check(p, .SoftNewline) || check(p, .ParagraphBreak) {
            advance(p)
        }
        #partial switch peek(p).kind {
        case .SetupBodyfont: 
            append(&commands, parse_setup_bodyfont(p))
        case .SetupHead: 
            append(&commands, parse_setup_head(p))
        case: 
            return commands
        }
    }

    return commands
}

parse_setup_bodyfont :: proc(p: ^Parser) -> SetupBodyfont {
    tok := advance(p)
    start := tok.span.start
    arg: BracketArgument
    if check(p, .BracketOpen) {
        a := parse_bracket_argument(p)
        arg = a
    }
    return SetupBodyfont {
        argument = arg,
        span = TextRange {
            start = peek(p).span.start,
            end = peek(p).span.end,
        }
    }
}

parse_setup_head :: proc(p: ^Parser) -> SetupHead {
    tok := advance(p)
    start := tok.span.start 
    args := make([dynamic]BracketArgument)
    for check(p, .BracketOpen) {
        append(&args, parse_bracket_argument(p))
    }
    return SetupHead {
        arguments = args[:],
        span = TextRange {
            start = peek(p).span.start, 
            end = peek(p).span.end,
        }
    }
}

parse_bracket_argument :: proc(p: ^Parser) -> BracketArgument {
    open, _ := expect(p, .BracketOpen)
    start := open.span.start
    text := ""
    if check(p, .Text) {
        text = advance(p).lexeme
    }
    expect(p, .BracketClose)
    return BracketArgument {
        text = text,
        span = TextRange {
            start = peek(p).span.start,
            end = peek(p).span.end,
        }
    }
}

parse_body :: proc(p: ^Parser) -> DocumentBody {
    open, ok := expect(p, .StartText)
    if !ok {
        synchronise(p)
        return DocumentBody {}
    }
    start := open.span.start
    paragraphs := parse_content(p)
    expect(p, .StopText)
    return DocumentBody {
        paragraphs = paragraphs,
        span = TextRange {
            start = peek(p).span.start,
            end = peek(p).span.end,
        }
    }
}

parse_content :: proc(p: ^Parser) -> []Paragraph {
    paragraphs := make([dynamic]Paragraph)
    for !check(p, .StopText) && !check(p, .EOF) {
        para := parse_paragraph(p)
        append(&paragraphs, para)
        if check(p, .ParagraphBreak) do advance(p)
    }
    return paragraphs[:]
}

parse_paragraph :: proc(p: ^Parser) -> Paragraph {
    start := peek(p).span.start
    buf := strings.builder_make()
    for !check(p, .ParagraphBreak) && !check(p, .StopText) && !check(p, .EOF) {
        #partial switch peek(p).kind {
        case .Text:
            strings.write_string(&buf, advance(p).lexeme)
        case .SoftNewline:
            strings.write_byte(&buf, '\n')
            advance(p)
        case .Invalid: 
            record_error(p, fmt.tprintf("unknown command: %q", peek(p).lexeme))
            advance(p)
        case: 
            record_error(p, fmt.tprintf("unexpected token in paragraph: %v", peek(p).kind))
            advance(p)
        }
    }
    return Paragraph {
        text = strings.to_string(buf),
        span = TextRange {
            start = start,
            end = peek(p).span.end,
        }
    }
}

report_errors :: proc(p: ^Parser) -> bool {
    if len(p.errors) == 0 {
        fmt.println("Passed successfully.")
        return true
    }
    for err in p.errors {
        fmt.printf("Error at [%d:%d]: %s (got %v)\n", 
            err.span.start, err.span.end, err.message, err.got)
    }
    return false
}

// === PRETTY PRINTING ===

indent :: proc(depth: int) {
    for _ in 0..<depth {
        fmt.print("  ")
    }
}

print_node_document :: proc(doc: Document, depth: int = 0) {
    indent(depth); fmt.printf("Document [%d–%d]\n", doc.span.start, doc.span.end)
    if preamble, ok := doc.preamble.?; ok {
        indent(depth + 1); fmt.println("Preamble")
        for cmd in preamble {
            print_node_preamble_command(cmd, depth + 2)
        }
    }
    print_node_body(doc.body, depth + 1)
}

print_node_preamble_command :: proc(cmd: PreambleCommand, depth: int) {
    switch c in cmd {
    case SetupBodyfont:
        indent(depth); fmt.printf("SetupBodyfont [%d–%d]\n", c.span.start, c.span.end)
        print_node_bracket_argument(c.argument, depth + 1)
    case SetupHead:
        indent(depth); fmt.printf("SetupHead [%d–%d]\n", c.span.start, c.span.end)
        for arg in c.arguments {
            print_node_bracket_argument(arg, depth + 1)
        }
    }
}

print_node_bracket_argument :: proc(arg: BracketArgument, depth: int) {
    indent(depth); fmt.printf("BracketArgument %q [%d–%d]\n", arg.text, arg.span.start, arg.span.end)
}

print_node_body :: proc(body: DocumentBody, depth: int) {
    indent(depth); fmt.printf("DocumentBody [%d–%d]\n", body.span.start, body.span.end)
    for para, i in body.paragraphs {
        indent(depth + 1); fmt.printf("Paragraph %d %q [%d–%d]\n", i, para.text, para.span.start, para.span.end)
    }
}
