package main

import "core:fmt"
import "core:os"
import "core:strings"

import "src:basic/mem"

BUF_SIZE :: mem.MIB
TOKEN_CAP :: 2000

Token :: struct
{
  kind: Token_Kind,
  str:  string,
}

Token_Store :: struct
{
  arena: ^mem.Arena,
  data:   []Token,
  cnt:    int,
  cap:    int,
}

Token_Kind :: enum
{
  Nil,
  String,
  Number,
  Boolean,
  Open_Brace,
  Closed_Brace,
  Open_Bracket,
  Closed_Bracket,
}

tokenize_json_from_path :: proc(path: string, arena: ^mem.Arena) -> Token_Store
{
  push_token :: proc(tokens: ^Token_Store, str: string, kind: Token_Kind)
  {
    assert(tokens.cnt < tokens.cap)

    tokens.data[tokens.cnt] = {
      str = strings.clone(str, mem.allocator(tokens.arena)), 
      kind = kind,
    }
    tokens.cnt += 1
  }

  temp := mem.scope_temp(mem.get_scratch())

  tokens: Token_Store
  tokens.cap = TOKEN_CAP
  tokens.data = make([]Token, tokens.cap)
  tokens.arena = arena

  file, o_err := os.open(path, os.O_RDONLY)
  if o_err != os.ERROR_NONE
  {
    fmt.eprintln("Error opening file!", o_err)
    return {}
  }
  
  buf: []byte = make([]byte, BUF_SIZE, mem.allocator(temp.arena))

  stream_len, r_err := os.read(file, buf[:])
  if r_err != os.ERROR_NONE
  {
    fmt.eprintln("Error reading file!", r_err)
    return {}
  }

  stream := cast(string) buf[:stream_len]

  for i := 0; i < stream_len;
  {
    // - Tokenize symbols ---
    {
      kind: Token_Kind
      switch stream[i]
      {
        case '{': kind = .Open_Brace
        case '}': kind = .Closed_Brace
        case '[': kind = .Open_Bracket
        case ']': kind = .Closed_Bracket
      }
  
      if kind != .Nil
      {
        push_token(&tokens, stream[i:i+1], kind)
        i += 1
        continue
      }
    }

    // - Tokenize string ---
    if stream[i] == '\"'
    {
      i += 1
      closing_quote_idx: int = strings.index_byte(stream[i:], '\"')
      if closing_quote_idx != -1
      {
        push_token(&tokens, stream[i:i+closing_quote_idx], .String)
        i += closing_quote_idx + 1
        continue
      }
    }

    // - Tokenize number ---
    if stream[i] >= '0' && stream[i] <= '9'
    {
      substr := stream[i:i+1]
      for j := 1; j < stream_len-i; j += 1
      {
        if stream[i+j] >= '0' && stream[i+j] <= '9'
        {
          substr = stream[i:i+1+j]
        }
        else do break
      }
      
      push_token(&tokens, substr, .Number)
      i += len(substr) + 1
      continue
    }

    // - Tokenize boolean ---
    if stream[i] == 'f' || stream[i] == 't'
    {
      substr: string
      if strings.compare(stream[i:i+5], "false") == 0
      {
        substr = "false"
      }
      else if strings.compare(stream[i:i+4], "true") == 0
      {
        substr = "true"
      }

      push_token(&tokens, substr, .Boolean)
      i += len(substr)
      continue
    }

    i += 1
  }

  tokens.data = tokens.data[:tokens.cnt]

  return tokens
}

parse_json_tokens_iterative :: proc(tokens: Token_Store)
{
  Parser_Context :: enum{Object, List}

  Parser :: struct
  {
    pos: int,
    stack: [dynamic]string,
    stack_ctx: [dynamic]Parser_Context,
  }

  consume_token :: proc(parser: ^Parser, tokens: Token_Store) -> Token
  {
    result := tokens.data[parser.pos]
    parser.pos += 1
    return result
  }

  peek_token :: proc(parser: Parser, tokens: Token_Store) -> Token
  {
    if parser.pos == tokens.cnt do return {}
    return tokens.data[parser.pos]
  }
  
  is_token_value :: proc(token: Token) -> bool
  {
    return token.kind == .Boolean || token.kind == .Number || token.kind == .String
  }

  print_stack :: proc(parser: Parser)
  {
    for str, idx in parser.stack
    {
      fmt.print(str)
      if idx != len(parser.stack) - 1
      {
        fmt.print(".")
      }
    }
    fmt.print("\n")
  }

  temp := mem.scope_temp(mem.get_scratch())

  parser: Parser
  parser.stack = make([dynamic]string, mem.allocator(temp.arena))
  parser.stack_ctx = make([dynamic]Parser_Context, mem.allocator(temp.arena))

  append(&parser.stack, "root")

  for
  {
    token := consume_token(&parser, tokens)
    if parser.pos == len(tokens.data) do break

    switch token.kind
    {
    case .Nil:
    case .Open_Brace:
      append(&parser.stack_ctx, Parser_Context.Object)
    case .Closed_Brace:
      pop(&parser.stack)
      pop(&parser.stack_ctx)
    case .Open_Bracket:
      append(&parser.stack_ctx, Parser_Context.List)
    case .Closed_Bracket:
      pop(&parser.stack)
      pop(&parser.stack_ctx)
    case .Boolean, .String, .Number:
      parser_ctx := parser.stack_ctx[len(parser.stack_ctx)-1]
      if parser_ctx == .Object
      {
        append(&parser.stack, token.str)
        print_stack(parser)

        if is_token_value(peek_token(parser, tokens))
        {
          append(&parser.stack, consume_token(&parser, tokens).str)
          print_stack(parser)
          pop(&parser.stack)
          pop(&parser.stack)
        }
      }
      else if parser_ctx == .List
      {
        append(&parser.stack, token.str)
        print_stack(parser)
        pop(&parser.stack)
      }
    }
  }
}

main :: proc()
{
  perm_arena: mem.Arena
  mem.init_arena_static(&perm_arena)
  context.allocator = mem.allocator(&perm_arena)

  temp_arena: mem.Arena
  mem.init_arena_growing(&temp_arena)
  context.temp_allocator = mem.allocator(&temp_arena)
  
  tokens := tokenize_json_from_path("data.json", &perm_arena)
  parse_json_tokens_iterative(tokens)
}
