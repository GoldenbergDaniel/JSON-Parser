package main

import "core:fmt"
import "core:os"
import "core:strings"

import "src:basic/mem"

BUF_SIZE  :: mem.MIB
TOKEN_CAP :: 2000

Token :: struct
{
  kind: Token_Kind,
  str:  string,
}

Token_Store :: struct
{
  data:     []Token,
  count:    int,
  capacity: int,
  arena:    ^mem.Arena,
}

Token_Kind :: enum
{
  Nil,
  String,
  Number,
  Boolean,
  Brace_Open,
  Brace_Closed,
  Bracket_Open,
  Bracket_Closed,
}

Tokenizer :: struct
{
  pos: int,
}

tokenize_json_from_bytes :: proc(data: []byte, arena: ^mem.Arena) -> Token_Store
{
  store: Token_Store
  store.capacity = TOKEN_CAP
  store.data = make([]Token, store.capacity)
  store.arena = arena

  tokenizer: Tokenizer

  push_token :: proc(store: ^Token_Store, token: Token)
  {
    assert(store.count < store.capacity)

    store.data[store.count] = token
    store.count += 1
  }

  stream := cast(string) data

  for
  {
    if tokenizer.pos >= len(stream) do break

    // - Tokenize symbols ---
    {
      kind: Token_Kind
      switch stream[tokenizer.pos]
      {
        case '{': kind = .Brace_Open
        case '}': kind = .Brace_Closed
        case '[': kind = .Bracket_Open
        case ']': kind = .Bracket_Closed
      }
  
      if kind != .Nil
      {
        push_token(&store, {kind, stream[tokenizer.pos:tokenizer.pos+1]})
        tokenizer.pos += 1
        continue
      }
    }

    // - Tokenize string ---
    if stream[tokenizer.pos] == '\"'
    {
      tokenizer.pos += 1
      closing_quote_idx: int = strings.index_byte(stream[tokenizer.pos:], '\"')
      if closing_quote_idx != -1
      {
        push_token(&store, {.String, stream[tokenizer.pos:tokenizer.pos+closing_quote_idx]})
        tokenizer.pos += closing_quote_idx + 1
        continue
      }
    }

    // - Tokenize number ---
    if stream[tokenizer.pos] >= '0' && stream[tokenizer.pos] <= '9'
    {
      substr := stream[tokenizer.pos:tokenizer.pos+1]
      for i := 1; i < len(stream)-tokenizer.pos; i += 1
      {
        if stream[tokenizer.pos+i] < '0' || stream[tokenizer.pos+i] > '9' do break
        substr = stream[tokenizer.pos:tokenizer.pos+1+i]
      }
      
      push_token(&store, {.Number, substr})
      tokenizer.pos += len(substr) + 1
      continue
    }

    // - Tokenize boolean ---
    if stream[tokenizer.pos] == 'f' || stream[tokenizer.pos] == 't'
    {
      substr: string
      if strings.compare(stream[tokenizer.pos:tokenizer.pos+5], "false") == 0
      {
        substr = "false"
      }
      else if strings.compare(stream[tokenizer.pos:tokenizer.pos+4], "true") == 0
      {
        substr = "true"
      }

      push_token(&store, {.Boolean, substr})
      tokenizer.pos += len(substr)
      continue
    }

    tokenizer.pos += 1
  }

  store.data = store.data[:store.count]

  return store
}

Parser :: struct
{
  pos:       int,
  val_stack: [dynamic]string,
  ctx_stack: [dynamic]Parser_Context,
}

Parser_Context :: enum{Object, List}

consume_token :: proc(parser: ^Parser, tokens: Token_Store) -> Token
{
  result := tokens.data[parser.pos]
  parser.pos += 1
  return result
}

peek_token :: proc(parser: Parser, tokens: Token_Store, offset := 0) -> Token
{
  return tokens.data[parser.pos + offset]
}

token_is_value :: proc(token: Token) -> bool
{
  return token.kind == .Boolean || token.kind == .Number || token.kind == .String
}

parse_json_iterative :: proc(tokens: Token_Store)
{
  print_stack :: proc(parser: Parser)
  {
    for str, idx in parser.val_stack
    {
      fmt.print(str)
      if idx != len(parser.val_stack) - 1
      {
        fmt.print(".")
      }
    }
    fmt.print("\n")
  }

  temp := mem.scope_temp(mem.get_scratch())

  parser: Parser
  parser.val_stack = make([dynamic]string, mem.allocator(temp.arena))
  parser.ctx_stack = make([dynamic]Parser_Context, mem.allocator(temp.arena))

  append(&parser.val_stack, "root")
  print_stack(parser)

  for
  {
    token := consume_token(&parser, tokens)
    if parser.pos == len(tokens.data) do break

    switch token.kind
    {
    case .Nil:
    case .Brace_Open:
      append(&parser.ctx_stack, Parser_Context.Object)
    case .Brace_Closed:
      pop(&parser.val_stack)
      pop(&parser.ctx_stack)
    case .Bracket_Open:
      append(&parser.ctx_stack, Parser_Context.List)
    case .Bracket_Closed:
      pop(&parser.val_stack)
      pop(&parser.ctx_stack)
    case .Boolean, .String, .Number:
      parser_ctx := parser.ctx_stack[len(parser.ctx_stack)-1]
      if parser_ctx == .Object
      {
        append(&parser.val_stack, token.str)
        print_stack(parser)

        if token_is_value(peek_token(parser, tokens))
        {
          append(&parser.val_stack, consume_token(&parser, tokens).str)
          print_stack(parser)
          pop(&parser.val_stack)
          pop(&parser.val_stack)
        }
      }
      else if parser_ctx == .List
      {
        append(&parser.val_stack, token.str)
        print_stack(parser)
        pop(&parser.val_stack)
      }
    }
  }
}

parse_json_recursive :: proc(tokens: Token_Store)
{

}

main :: proc()
{
  perm_arena: mem.Arena
  mem.init_arena_static(&perm_arena)

  PATH_TO_JSON :: "data.json"
  file, o_err := os.open(PATH_TO_JSON, os.O_RDONLY)
  if o_err != os.ERROR_NONE
  {
    fmt.eprintln("Error opening file!", o_err)
    return
  }

  file_data := make([]byte, BUF_SIZE, mem.allocator(&perm_arena))
  file_size, r_err := os.read(file, file_data[:])
  if r_err != os.ERROR_NONE
  {
    fmt.eprintln("Error reading file!", r_err)
    return
  }
  
  tokens := tokenize_json_from_bytes(file_data[:file_size], &perm_arena)
  parse_json_iterative(tokens)
}
