#!/usr/local/bin/xsh --
error ScriptError = Failed(kind: Str, message: Str)

# m4 — macro processor in pure XSH.
#
# Design:  See M4.md for the full spec.
#
# State map keys:
#   mac:NAME           → macro body  ("BUILTIN" for built-ins)
#   pdepth:NAME        → push depth (int as Str; absent = 0)
#   pval:NAME:N        → body saved at push depth N
#   div:N              → diversion buffer N  (N = 0..9, or "scratch")
#   cur_div            → active diversion index as Str
#   open_q / close_q   → quote delimiters    (default "`" / "'")
#   com_start          → comment-start delimiter  (default "#")
#   wrap               → m4wrap queue text
#   sysval             → Str of last esyscmd exit code
#   include_paths      → newline-joined search paths
#   prefix             → "1" when -P is active
#   file / line        → current input position
type TextRest = {content: Str, rest: Str}

type RawRest = {raw: Str, rest: Str}

type ExpandResult = {text: Str, st: Map[Str]}

pure regex_captures(text: Str, pattern: Str) -> Result[List[Str]] {
  let re = regex.compile(pattern)?
  return re.captures(text)
}

# ── state helpers ─────────────────────────────────────────────────────────────
pure sg(st: Map[Str], k: Str, d: Str) -> Str {
  return st.get(k, d)
}

pure si(st: Map[Str], k: Str, d: Int) -> Int {
  return sg(st, k, "").parse_int() ?? d
}

pure take_char(text: Str) -> Result[TextRest] {
  match regex_captures(text, "(?s)^(.)(.*)") {
    Ok(c) => {
      if c.len() >= 3 {
        return {content: c[1], rest: c[2]}
      }
    }
    Err(_) => {}
  }

  return {content: "", rest: ""}
}

proc drop_prefix(text: Str, prefix: Str) [error] -> Result[Str] {
  if prefix == "" {
    return text
  }

  var remaining_text = text
  var remaining_prefix = prefix

  while remaining_prefix != "" {
    let prefix_char = take_char(remaining_prefix)?
    remaining_prefix = prefix_char.rest
    let text_char = take_char(remaining_text)?
    remaining_text = text_char.rest
  }

  return remaining_text
}

proc preview_text(text: Str, limit: Int) [error] -> Result[Str] {
  var cur = text
  var out = ""
  var count = 0

  while cur != "" and count < limit {
    let ch = take_char(cur)?
    out = f"${out}${ch.content}"
    cur = ch.rest
    count = count + 1
  }

  return out.replace(
    """
""",
    "\\n",
  )
}

pure repeat_space(count: Int) -> Str {
  if count <= 0 {
    return ""
  }

  return f" ${repeat_space(count - 1)}"
}

proc take_chars(text: Str, limit: Int) [error] -> Result[Str] {
  var cur = text
  var out = ""
  var count = 0

  while cur != "" and count < limit {
    let ch = take_char(cur)?
    out = f"${out}${ch.content}"
    cur = ch.rest
    count = count + 1
  }

  return out
}

pure format_field(value: Str, width: Int, left: Bool) -> Str {
  let missing = width - value.count_chars()

  if missing <= 0 {
    return value
  }

  let pad = repeat_space(missing)

  if left {
    return f"${value}${pad}"
  }

  return f"${pad}${value}"
}

proc take_literal_chunk(text: Str, oq: Str, cs: Str) [error] -> Result[TextRest] {
  if cs == "" and oq == "[[" {
    match regex_captures(text, "(?s)^([^A-Za-z_\\[]+)(.*)") {
      Ok(c) => {
        if c.len() >= 3 {
          return {content: c[1], rest: c[2]}
        }
      }
      Err(_) => {}
    }
  }

  if cs == "" and oq == "[" {
    match regex_captures(text, "(?s)^([^A-Za-z_\\[]+)(.*)") {
      Ok(c) => {
        if c.len() >= 3 {
          return {content: c[1], rest: c[2]}
        }
      }
      Err(_) => {}
    }
  }

  if cs == "" and oq == "`" {
    match regex_captures(text, "(?s)^([^A-Za-z_`]+)(.*)") {
      Ok(c) => {
        if c.len() >= 3 {
          return {content: c[1], rest: c[2]}
        }
      }
      Err(_) => {}
    }
  }

  if cs == "#" and oq == "`" {
    match regex_captures(text, "(?s)^([^A-Za-z_`#]+)(.*)") {
      Ok(c) => {
        if c.len() >= 3 {
          return {content: c[1], rest: c[2]}
        }
      }
      Err(_) => {}
    }
  }

  var cur = text
  var out = ""

  while cur != "" {
    if oq != "" and cur.starts_with(oq) or cs != "" and cur.starts_with(cs) {
      return {content: out, rest: cur}
    }

    match regex_captures(cur, "^[A-Za-z_]") {
      Ok(_) => return {content: out, rest: cur}
      Err(_) => {}
    }

    let ch = take_char(cur)?
    out = f"${out}${ch.content}"
    cur = ch.rest
  }

  return {content: out, rest: ""}
}

proc take_undefined_tail(text: Str, oq: Str, cs: Str, st: Map[Str]) [error] -> Result[TextRest] {
  var cur = text
  var out = ""

  while cur != "" {
    if oq != "" and cur.starts_with(oq) or cs != "" and cur.starts_with(cs) {
      return {content: out, rest: cur}
    }

    match regex_captures(cur, "(?s)^([A-Za-z_][A-Za-z0-9_]*)(.*)") {
      Ok(id) => {
        if id.len() >= 3 {
          let word = id[1]

          if mac_defined(st, word) {
            return {content: out, rest: cur}
          }

          out = f"${out}${word}"
          cur = id[2]
          continue
        }
      }
      Err(_) => {}
    }

    let chunk = take_literal_chunk(cur, oq, cs)?

    if chunk.content != "" {
      out = f"${out}${chunk.content}"
      cur = chunk.rest
    } else {
      let ch = take_char(cur)?
      out = f"${out}${ch.content}"
      cur = ch.rest
    }
  }

  return {content: out, rest: ""}
}

# Emit text to the current diversion (or discard if cur_div == "-1").
pure emit(chunk: Str, st: Map[Str]) -> Map[Str] {
  let cd = sg(st, "cur_div", "0")

  if cd == "-1" or chunk == "" {
    return st
  } else {
    let k = f"div:${cd}"
    let prev = sg(st, k, "")
    return st.set(k, f"${prev}${chunk}")
  }
}

pure mac_get(st: Map[Str], name: Str) -> Str {
  return sg(st, f"mac:${name}", "")
}

pure mac_exists(st: Map[Str], name: Str) -> Bool {
  return st.has(f"mac:${name}")
}

pure mac_set(st: Map[Str], name: Str, body: Str) -> Map[Str] {
  return st.set(f"mac:${name}", body)
}

pure mac_unset(st: Map[Str], name: Str) -> Map[Str] {
  # XSH Map has no delete; overwrite with sentinel that mac_exists filters.
  return st.set(f"mac:${name}", "\0UNDEF\0")
}

pure mac_defined(st: Map[Str], name: Str) -> Bool {
  if ! mac_exists(st, name) {
    return false
  }

  return mac_get(st, name) != "\0UNDEF\0"
}

# ── tokenizer ─────────────────────────────────────────────────────────────────
# Collect balanced quote delimiters starting at rem.
# Returns Map with "content" and "rest".
proc collect_quoted(rem: Str, oq: Str, cq: Str) [error] -> Result[TextRest] {
  if ! rem.starts_with(oq) {
    return Err(ScriptError.Failed("m4", f"expected ${oq}"))
  }

  var cur = drop_prefix(rem, oq)?
  var depth = 1
  var content_parts: List[Str] = []

  while cur != "" {
    if cq != "" and cur.starts_with(cq) {
      depth = depth - 1

      if depth == 0 {
        return {content: content_parts.join(""), rest: drop_prefix(cur, cq)?}
      }

      content_parts = content_parts.push(cq)
      cur = drop_prefix(cur, cq)?
    } else if oq != "" and cur.starts_with(oq) {
      depth = depth + 1
      content_parts = content_parts.push(oq)
      cur = drop_prefix(cur, oq)?
    } else {
      if oq == "[[" or oq == "[" {
        match regex_captures(cur, "(?s)^([^\\[\\]]+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              content_parts = content_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if oq == "`" and cq == "'" {
        match regex_captures(cur, "(?s)^([^`']+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              content_parts = content_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      }

      let ch = take_char(cur)?
      content_parts = content_parts.push(ch.content)
      cur = ch.rest
    }
  }

  Err(ScriptError.Failed("m4", f"unterminated quote ${oq}...${cq} near ${preview_text(rem, 120)?}"))
}

# Collect raw argument text from rem starting after '('.
# Returns Map with "raw" (contents between the outer parens) and "rest".
proc collect_args_raw(rem: Str, oq: Str, cq: Str) [error] -> Result[RawRest] {
  var cur = rem

  match regex_captures(cur, "(?s)^\\((.*)") {
    Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
    Err(_) => {}
  }

  var pdepth = 1
  var qdepth = 0
  var raw_parts: List[Str] = []

  while cur != "" {
    if qdepth == 0 and cur.starts_with("(") {
      pdepth = pdepth + 1
      raw_parts = raw_parts.push("(")

      match regex_captures(cur, "(?s)^.(.*)") {
        Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
        Err(_) => cur = ""
      }
    } else if qdepth == 0 and cur.starts_with(")") {
      pdepth = pdepth - 1

      if pdepth == 0 {
        match regex_captures(cur, "(?s)^.(.*)") {
          Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
          Err(_) => cur = ""
        }

        return {raw: raw_parts.join(""), rest: cur}
      }

      raw_parts = raw_parts.push(")")

      match regex_captures(cur, "(?s)^.(.*)") {
        Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
        Err(_) => cur = ""
      }
    } else if oq != "" and cur.starts_with(oq) {
      qdepth = qdepth + 1
      raw_parts = raw_parts.push(oq)
      cur = drop_prefix(cur, oq)?
    } else if cq != "" and cur.starts_with(cq) {
      if qdepth > 0 {
        qdepth = qdepth - 1
      }

      raw_parts = raw_parts.push(cq)
      cur = drop_prefix(cur, cq)?
    } else {
      if qdepth > 0 and (oq == "[[" or oq == "[") {
        match regex_captures(cur, "(?s)^([^\\[\\]]+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              raw_parts = raw_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if oq == "[[" or oq == "[" {
        match regex_captures(cur, "(?s)^([^()\\[\\]]+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              raw_parts = raw_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if qdepth > 0 and oq == "`" and cq == "'" {
        match regex_captures(cur, "(?s)^([^`']+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              raw_parts = raw_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if oq == "`" and cq == "'" {
        match regex_captures(cur, "(?s)^([^()`']+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              raw_parts = raw_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      }

      let ch = take_char(cur)?
      raw_parts = raw_parts.push(ch.content)
      cur = ch.rest
    }
  }

  Err(ScriptError.Failed("m4", f"unmatched paren near ${preview_text(raw_parts.join(""), 120)?}"))
}

# Split raw arg text on top-level commas.
proc split_args(raw: Str, oq: Str, cq: Str) [error] -> Result[List[Str]] {
  var margs: List[Str] = []
  var qdepth = 0
  var pdepth = 0
  var cur_arg_parts: List[Str] = []
  var cur = raw

  while cur != "" {
    if oq != "" and cur.starts_with(oq) {
      qdepth = qdepth + 1
      cur_arg_parts = cur_arg_parts.push(oq)
      cur = drop_prefix(cur, oq)?
    } else if cq != "" and cur.starts_with(cq) {
      if qdepth > 0 {
        qdepth = qdepth - 1
      }

      cur_arg_parts = cur_arg_parts.push(cq)
      cur = drop_prefix(cur, cq)?
    } else if qdepth == 0 and cur.starts_with("(") {
      pdepth = pdepth + 1
      cur_arg_parts = cur_arg_parts.push("(")

      match regex_captures(cur, "(?s)^.(.*)") {
        Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
        Err(_) => cur = ""
      }
    } else if qdepth == 0 and cur.starts_with(")") {
      if pdepth > 0 {
        pdepth = pdepth - 1
      }

      cur_arg_parts = cur_arg_parts.push(")")

      match regex_captures(cur, "(?s)^.(.*)") {
        Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
        Err(_) => cur = ""
      }
    } else if qdepth == 0 and pdepth == 0 and cur.starts_with(",") {
      margs = margs.push(cur_arg_parts.join(""))
      cur_arg_parts = []

      match regex_captures(cur, "(?s)^.(.*)") {
        Ok(c) => cur = if c.len() >= 2 { c[1] } else { "" }
        Err(_) => cur = ""
      }
    } else {
      if qdepth > 0 and (oq == "[[" or oq == "[") {
        match regex_captures(cur, "(?s)^([^\\[\\]]+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              cur_arg_parts = cur_arg_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if oq == "[[" or oq == "[" {
        match regex_captures(cur, "(?s)^([^(),\\[\\]]+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              cur_arg_parts = cur_arg_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if qdepth > 0 and oq == "`" and cq == "'" {
        match regex_captures(cur, "(?s)^([^`']+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              cur_arg_parts = cur_arg_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      } else if oq == "`" and cq == "'" {
        match regex_captures(cur, "(?s)^([^(),`']+)(.*)") {
          Ok(c) => {
            if c.len() >= 3 {
              cur_arg_parts = cur_arg_parts.push(c[1])
              cur = c[2]
              continue
            }
          }
          Err(_) => {}
        }
      }

      let ch = take_char(cur)?
      cur_arg_parts = cur_arg_parts.push(ch.content)
      cur = ch.rest
    }
  }

  margs = margs.push(cur_arg_parts.join(""))
  margs
}

# Substitute $1..$9, $0, $@, $* in a macro body.
proc subst_args(body: Str, name: Str, margs: List[Str], oq: Str, cq: Str) [error] -> Result[Str] {
  var r = body
  r = r.replace("$0", name)
  r = r.replace("$#", f"${margs.len()}")
  var i = 1

  while i <= 9 {
    let ph = f"$${i}"
    let val = if i <= margs.len() { margs[i - 1] } else { "" }
    r = r.replace(ph, val)
    i = i + 1
  }

  let all = margs.join(",")
  var quoted: List[Str] = []

  for arg in margs {
    if oq == "" or cq == "" {
      quoted = quoted.push(arg)
    } else {
      quoted = quoted.push(f"${oq}${oq}${arg}${cq}${cq}")
    }
  }

  r = r.replace("$@", quoted.join(","))
  r = r.replace("$*", all)
  return r
}

pure basic_regex_to_rust(pattern: Str) -> Str {
  let captures_open = pattern.replace("\\(", "(")
  let captures_close = captures_open.replace("\\)", ")")
  let alternation = captures_close.replace("\\|", "|")
  let plus = alternation.replace("\\+", "+")
  let question = plus.replace("\\?", "?")
  let braces_open = question.replace("\\{", "{")
  return braces_open.replace("\\}", "}")
}

proc basic_replacement_to_rust(replacement: Str) [error] -> Result[Str] {
  var r = replacement.replace("$", "$$")
  r = r.replace("\\&", "$0")
  r = r.replace("\\0", "$0")
  var i = 1

  while i <= 9 {
    r = r.replace(f"\\${i}", f"$${i}")
    i = i + 1
  }

  return r
}

pure normalize_builtin_name(name: Str) -> Str {
  if name.starts_with("m4_") {
    return name.replace("m4_", "")
  }

  return name
}

pure builtin_target_name(word: Str, body: Str) -> Str {
  if body.starts_with("BUILTIN:") {
    return body.replace("BUILTIN:", "")
  }

  return normalize_builtin_name(word)
}

pure strip_outer_square_quote(text: Str) -> Str {
  match regex_captures(text, "(?s)^\\[(.*)\\]$") {
    Ok(c) => {
      if c.len() >= 2 {
        return c[1]
      }
    }
    Err(_) => {}
  }

  return text
}

pure strip_outer_square_quotes(text: Str) -> Str {
  return strip_outer_square_quote(strip_outer_square_quote(strip_outer_square_quote(text)))
}

pure b4_percent_value(st: Map[Str], varname: Str, fallback: Str) -> Str {
  if mac_defined(st, f"b4_percent_define(${varname})") {
    return strip_outer_square_quotes(mac_get(st, f"b4_percent_define(${varname})"))
  }

  return fallback
}

pure b4_symbol_field_raw(st: Map[Str], num: Str, field: Str) -> Str {
  let key = f"b4_symbol(${num}, ${field})"

  if mac_defined(st, key) {
    return strip_outer_square_quotes(mac_get(st, key))
  }

  return ""
}

pure b4_symbol_id_name(st: Map[Str], num: Str) -> Str {
  if num == "0" {
    return "YYEOF"
  }

  if num == "1" {
    return "YYerror"
  }

  if num == "2" {
    return "YYUNDEF"
  }

  let id = b4_symbol_field_raw(st, num, "id")

  if id != "" {
    return id
  }

  let raw_tag = b4_symbol_field_raw(st, num, "tag")

  if raw_tag == "'\\n'" {
    return "n"
  }

  if raw_tag == "';'" {
    return "SEMICOLON"
  }

  if raw_tag == "'{'" {
    return "LBRACE"
  }

  if raw_tag == "'}'" {
    return "RBRACE"
  }

  let tag = raw_tag.replace("\"", "").replace("'", "").replace("$", "").replace("[", "").replace("]", "").replace(
    " ",
    "_",
  ).replace(
    """
""",
    "_",
  ).replace("-", "_").replace("{", "_").replace("}", "_").replace(";", "_")

  if tag == "" {
    return f"symbol_${num}"
  }

  return tag
}

pure b4_symbol_kind_base(st: Map[Str], num: Str) -> Str {
  let prefix = b4_percent_value(st, "api.symbol.prefix", "YYSYMBOL_")

  if num == "-2" {
    return f"${prefix}YYEMPTY"
  }

  return f"${prefix}${b4_symbol_id_name(st, num)}"
}

pure b4_symbol_lookup(st: Map[Str], num: Str, field: Str) -> Str {
  let n = if num == "empty" {
    "-2"
  } else {
    if num == "eof" { "0" } else { if num == "error" { "1" } else { if num == "undef" { "2" } else { num } } }
  }

  if n.starts_with("orig ") and field != "number" {
    let mapped = b4_symbol_field_raw(st, n, "number")

    if mapped != "" {
      return b4_symbol_lookup(st, mapped, field)
    }
  }

  if field == "kind_base" or field == "kind" {
    return b4_symbol_kind_base(st, n)
  }

  if field == "id" {
    return b4_symbol_id_name(st, n)
  }

  if field == "slot" {
    return b4_symbol_field_raw(st, n, "type")
  }

  return b4_symbol_field_raw(st, n, field)
}

pure b4_comment_text(text: Str) -> Str {
  let body = text.replace("/*", "/ *").replace("*/", "* /").replace("[", "").replace("]", "")
  return f"/* ${body} */"
}

pure b4_parse_error_kind(st: Map[Str]) -> Str {
  return b4_percent_value(st, "parse.error", "simple")
}

proc b4_pattern_matches(pattern: Str, value: Str) [error] -> Bool {
  var rest = pattern

  while rest != "" {
    match regex_captures(rest, "(?s)^([^|]*)(\\|)?(.*)$") {
      Ok(c) => {
        if c.len() >= 4 {
          if c[1] == value {
            return true
          }

          rest = c[3]
        } else {
          rest = ""
        }
      }
      Err(_) => rest = ""
    }
  }

  return false
}

proc b4_declare_symbol_enum_text(st: Map[Str]) [error] -> Result[Str] {
  let count = strip_outer_square_quotes(mac_get(st, "b4_symbols_number")).parse_int() ?? 0

  var out = """/* Symbol kind.  */
enum yysymbol_kind_t
{
"""

  let empty_name = b4_symbol_lookup(st, "empty", "kind_base")

  out = f"""${out}  ${empty_name} = -2,
"""

  var i = 0

  while i < count {
    let comma = if i + 1 == count { "" } else { "," }
    let name = b4_symbol_lookup(st, f"${i}", "kind_base")
    let comment = b4_comment_text(b4_symbol_lookup(st, f"${i}", "tag"))
    let padded = format_field(name, 42, false)

    out = f"""${out}${padded} = ${i}${comma} ${comment}
"""

    i = i + 1
  }

  return f"""${out}};
typedef enum yysymbol_kind_t yysymbol_kind_t;
"""
}

proc b4_token_enums_defines_text(st: Map[Str]) [error] -> Result[Str] {
  let count = strip_outer_square_quotes(mac_get(st, "b4_symbols_number")).parse_int() ?? 0

  var out = """/* Token kinds.  */
#define YYEMPTY -2
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
enum yytokentype
{
"""

  var first = true
  var i = 0

  while i < count {
    let is_token = b4_symbol_lookup(st, f"${i}", "is_token") == "1"
    let raw_id = b4_symbol_field_raw(st, f"${i}", "id")

    if is_token and (i <= 2 or raw_id != "") {
      let comma = if first {
        ""
      } else {
        """,
"""
      }

      let name = b4_symbol_id_name(st, f"${i}")
      let code = b4_symbol_lookup(st, f"${i}", "code")
      let comment = b4_comment_text(b4_symbol_lookup(st, f"${i}", "tag"))
      let padded = format_field(name, 34, false)
      out = f"${out}${comma}  ${padded} = ${code} ${comment}"
      first = false
    }

    i = i + 1
  }

  return f"""${out}
};
typedef enum yytokentype yytoken_kind_t;
#endif
"""
}

proc copy_macro(st: Map[Str], src: Str, dst: Str) [error] -> Result[Map[Str]] {
  let src_body = mac_get(st, src)
  let dst_body = if src_body == "BUILTIN" { f"BUILTIN:${normalize_builtin_name(src)}" } else { src_body }
  var s2 = mac_set(st, dst, dst_body)
  let depth = si(st, f"pdepth:${src}", 0)
  s2 = s2.set(f"pdepth:${dst}", f"${depth}")
  var i = 0

  while i < depth {
    s2 = s2.set(f"pval:${dst}:${i}", sg(st, f"pval:${src}:${i}", ""))
    i = i + 1
  }

  return s2
}

pure native_sugar_builtin(name: Str) -> Bool {
  return name == "m4_case" or name == "m4_bmatch" or name == "m4_copy" or name == "m4_copy_force" or name == "m4_rename" or name == "m4_rename_force" or name == "m4_define_default" or name == "m4_for" or name == "b4_define_silent" or name == "b4_divert_kill" or name == "b4_value_type_setup" or name == "b4_value_type_define" or name == "b4_token_enums" or name == "b4_token_enums_defines" or name == "b4_declare_symbol_enum" or name == "b4_symbol" or name == "_b4_symbol" or name == "__b4_symbol" or name == "b4_symbol_value" or name == "b4_lhs_value" or name == "b4_rhs_value" or name == "b4_symbol_if" or name == "b4_symbol_tag_comment" or name == "b4_header_if" or name == "b4_locations_if" or name == "b4_user_formals" or name == "b4_parse_error_case" or name == "b4_parse_error_bmatch" or name == "b4_define_flag_if" or name == "_b4_define_flag_if" or name == "b4_flag_if" or name == "b4_percent_define_default" or name == "b4_percent_define_flag_if" or name == "b4_percent_define_if_define" or name == "b4_percent_define_use" or name == "b4_percent_define_get" or name == "b4_percent_define_get_kind" or name == "b4_percent_define_get_loc" or name == "b4_percent_define_get_syncline" or name == "b4_percent_define_check_values" or name == "_b4_percent_define_check_values" or name == "b4_percent_define_check_kind" or name == "b4_percent_define_check_file" or name == "b4_percent_define_check_file_complain" or name == "_b4_percent_define_ifdef" or name == "b4_percent_define_ifdef"
}

# ── built-ins ─────────────────────────────────────────────────────────────────
proc call_builtin(name: Str, margs: List[Str], st: Map[Str]) [fs, process, env, error, io] -> Result[ExpandResult] {
  let oq = sg(st, "open_q", "`")
  let cq = sg(st, "close_q", "'")

  if name == "define" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let b = if margs.len() >= 2 { margs[1] } else { "" }
    let s2 = if n != "" { mac_set(st, n, b) } else { st }
    return {text: "", st: s2}
  }

  if name == "undefine" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    return {text: "", st: mac_unset(st, n)}
  }

  if name == "defn" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let b = mac_get(st, n)
    return {text: f"${oq}${b}${cq}", st}
  }

  if name == "pushdef" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let b = if margs.len() >= 2 { margs[1] } else { "" }
    let depth = si(st, f"pdepth:${n}", 0)
    let old = mac_get(st, n)
    var s2 = st.set(f"pval:${n}:${depth}", old)
    s2 = s2.set(f"pdepth:${n}", f"${depth + 1}")
    s2 = mac_set(s2, n, b)
    return {text: "", st: s2}
  }

  if name == "popdef" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let depth = si(st, f"pdepth:${n}", 0)
    var s2 = st

    if depth > 0 {
      let nd = depth - 1
      let saved = sg(st, f"pval:${n}:${nd}", "")
      s2 = s2.set(f"pdepth:${n}", f"${nd}")
      s2 = mac_set(s2, n, saved)
    } else {
      s2 = mac_unset(s2, n)
    }

    return {text: "", st: s2}
  }

  if name == "m4_copy" or name == "m4_copy_force" {
    let src = if margs.len() >= 1 { margs[0] } else { "" }
    let dst = if margs.len() >= 2 { margs[1] } else { "" }
    return {text: "", st: copy_macro(st, src, dst)?}
  }

  if name == "m4_rename" or name == "m4_rename_force" {
    let src = if margs.len() >= 1 { margs[0] } else { "" }
    let dst = if margs.len() >= 2 { margs[1] } else { "" }
    let copied = copy_macro(st, src, dst)?
    return {text: "", st: mac_unset(copied, src)}
  }

  if name == "m4_define_default" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }

    if mac_defined(st, n) {
      return {text: "", st}
    }

    let b = if margs.len() >= 2 { margs[1] } else { "" }
    return {text: "", st: mac_set(st, n, b)}
  }

  if name == "m4_for" {
    let varname = if margs.len() >= 1 { margs[0] } else { "" }
    let first = (if margs.len() >= 2 { margs[1] } else { "0" }).trim().parse_int()?
    let last = (if margs.len() >= 3 { margs[2] } else { "0" }).trim().parse_int()?
    let step_text = if margs.len() >= 4 { margs[3].trim() } else { "" }
    let step = if step_text != "" { step_text.parse_int()? } else { if last >= first { 1 } else { -1 } }
    let body = if margs.len() >= 5 { margs[4] } else { "" }
    var s2 = st
    var out = ""
    var i = first
    let had_var = if varname != "" { mac_defined(st, varname) } else { false }
    let old_var = if varname != "" { mac_get(st, varname) } else { "" }

    while step > 0 and i <= last or step < 0 and i >= last {
      if varname != "" {
        s2 = mac_set(s2, varname, f"${i}")
      }

      let expanded = expand_for_arg(body, s2)?
      s2 = expanded.st
      out = f"${out}${expanded.text}"
      i = i + step
    }

    if varname != "" {
      s2 = if had_var { mac_set(s2, varname, old_var) } else { mac_unset(s2, varname) }
    }

    return {text: out, st: s2}
  }

  if name == "b4_define_silent" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let b = if margs.len() >= 2 { margs[1] } else { "" }
    return {text: "", st: if n != "" { mac_set(st, n, b) } else { st }}
  }

  if name == "b4_divert_kill" {
    return {text: "", st}
  }

  if name == "m4_case" {
    let value = if margs.len() >= 1 { margs[0] } else { "" }
    var i = 1

    while i + 1 < margs.len() {
      if value == margs[i] {
        return {text: margs[i + 1], st}
      }

      i = i + 2
    }

    return {text: if i < margs.len() { margs[i] } else { "" }, st}
  }

  if name == "m4_bmatch" {
    let value = if margs.len() >= 1 { margs[0] } else { "" }
    var i = 1

    while i + 1 < margs.len() {
      let pat = basic_regex_to_rust(margs[i])

      match regex_captures(value, pat) {
        Ok(_) => return {text: margs[i + 1], st}
        Err(_) => {}
      }

      i = i + 2
    }

    return {text: if i < margs.len() { margs[i] } else { "" }, st}
  }

  if name == "b4_value_type_setup" {
    if mac_defined(st, "b4_percent_define(api.value.type)") {
      let value = strip_outer_square_quotes(mac_get(st, "b4_percent_define(api.value.type)"))

      if value == "union" or value == "union-directive" or value == "variant" or value == "yystype" {
        return {text: "", st: mac_set(st, "b4_percent_define_kind(api.value.type)", "keyword")}
      }

      return {text: "", st}
    }

    var s2 = st

    if mac_defined(st, "b4_union_members") {
      s2 = mac_set(s2, "b4_percent_define_kind(api.value.type)", "keyword")
      s2 = mac_set(s2, "b4_percent_define(api.value.type)", "union-directive")
    } else if strip_outer_square_quotes(mac_get(st, "b4_tag_seen_flag")) == "0" {
      s2 = mac_set(s2, "b4_percent_define_kind(api.value.type)", "code")
      s2 = mac_set(s2, "b4_percent_define(api.value.type)", "int")
    } else {
      s2 = mac_set(s2, "b4_percent_define_kind(api.value.type)", "keyword")
      s2 = mac_set(s2, "b4_percent_define(api.value.type)", "yystype")
    }

    return {text: "", st: s2}
  }

  if name == "b4_value_type_define" {
    let setup = call_builtin("b4_value_type_setup", [], st)?
    let s2 = setup.st
    let kind = b4_percent_value(s2, "api.value.type", "int")
    let kind_type = b4_percent_value(s2, "api.value.type", "int")

    let type_kind = if mac_defined(s2, "b4_percent_define_kind(api.value.type)") {
      strip_outer_square_quotes(mac_get(s2, "b4_percent_define_kind(api.value.type)"))
    } else {
      "code"
    }

    if kind == "union" or kind == "union-directive" {
      let members = mac_get(s2, "b4_union_members")

      return {
        text: f"""/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
${members}
};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif
""",
        st: s2,
      }
    }

    if type_kind == "code" {
      return {
        text: f"""/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
typedef ${kind_type} YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif
""",
        st: s2,
      }
    }

    return {text: "", st: s2}
  }

  if name == "b4_declare_symbol_enum" {
    return {text: b4_declare_symbol_enum_text(st)?, st}
  }

  if name == "b4_token_enums" or name == "b4_token_enums_defines" {
    return {text: b4_token_enums_defines_text(st)?, st}
  }

  if name == "b4_symbol" or name == "_b4_symbol" or name == "__b4_symbol" {
    let num = if margs.len() >= 1 { strip_outer_square_quotes(margs[0]) } else { "" }
    let field = if margs.len() >= 2 { strip_outer_square_quotes(margs[1]) } else { "" }
    return {text: b4_symbol_lookup(st, num, field), st}
  }

  if name == "b4_symbol_value" {
    let value = if margs.len() >= 1 { margs[0] } else { "" }
    let num = if margs.len() >= 2 { strip_outer_square_quotes(margs[1]) } else { "" }
    let explicit_type = if margs.len() >= 3 { strip_outer_square_quotes(margs[2]) } else { "" }

    if explicit_type != "" {
      return {text: f"(${value}.${explicit_type})", st}
    }

    if num != "" and b4_symbol_lookup(st, num, "has_type") == "1" {
      let type_name = b4_symbol_lookup(st, num, "type")
      return {text: f"(${value}.${type_name})", st}
    }

    return {text: value, st}
  }

  if name == "b4_lhs_value" {
    let num = if margs.len() >= 1 { strip_outer_square_quotes(margs[0]) } else { "" }
    let explicit_type = if margs.len() >= 2 { strip_outer_square_quotes(margs[1]) } else { "" }
    return call_builtin("b4_symbol_value", ["yyval", num, explicit_type], st)?
  }

  if name == "b4_rhs_value" {
    let len = if margs.len() >= 1 { strip_outer_square_quotes(margs[0]).parse_int() ?? 0 } else { 0 }
    let pos = if margs.len() >= 2 { strip_outer_square_quotes(margs[1]).parse_int() ?? 0 } else { 0 }
    let num = if margs.len() >= 3 { strip_outer_square_quotes(margs[2]) } else { "" }
    let explicit_type = if margs.len() >= 4 { strip_outer_square_quotes(margs[3]) } else { "" }
    let idx = pos - len
    return call_builtin("b4_symbol_value", [f"(*(yyvsp + ${idx}))", num, explicit_type], st)?
  }

  if name == "b4_symbol_if" {
    let num = if margs.len() >= 1 { strip_outer_square_quotes(margs[0]) } else { "" }
    let field = if margs.len() >= 2 { strip_outer_square_quotes(margs[1]) } else { "" }
    let yes = if margs.len() >= 3 { margs[2] } else { "" }
    let no = if margs.len() >= 4 { margs[3] } else { "" }
    return {text: if b4_symbol_lookup(st, num, field) == "1" { yes } else { no }, st}
  }

  if name == "b4_symbol_tag_comment" {
    let num = if margs.len() >= 1 { strip_outer_square_quotes(margs[0]) } else { "" }
    return {text: b4_comment_text(b4_symbol_lookup(st, num, "tag")), st}
  }

  if name == "b4_header_if" {
    let yes = if margs.len() >= 1 { margs[0] } else { "" }
    let no = if margs.len() >= 2 { margs[1] } else { "" }
    let flag = strip_outer_square_quotes(mac_get(st, "b4_header_flag"))
    return {text: if flag == "1" { yes } else { no }, st}
  }

  if name == "b4_locations_if" {
    let yes = if margs.len() >= 1 { margs[0] } else { "" }
    let no = if margs.len() >= 2 { margs[1] } else { "" }
    let flag = b4_percent_value(st, "locations", "false")
    return {text: if flag == "true" or flag == "1" { yes } else { no }, st}
  }

  if name == "b4_user_formals" {
    return {text: "", st}
  }

  if name == "b4_parse_error_case" {
    let current = b4_parse_error_kind(st)
    var i = 0

    while i + 1 < margs.len() {
      let expected = strip_outer_square_quotes(margs[i])
      let selected = margs[i + 1]

      if expected == current {
        if expected == "simple" and "b4_api_PREFIX[DEBUG" in selected {
          let token_table = strip_outer_square_quotes(mac_get(st, "b4_token_table_flag"))
          return {text: f"YYDEBUG || ${token_table}", st}
        }

        return {text: selected, st}
      }

      i = i + 2
    }

    return {text: if i < margs.len() { margs[i] } else { "" }, st}
  }

  if name == "b4_parse_error_bmatch" {
    let current = b4_parse_error_kind(st)
    var i = 0

    while i + 1 < margs.len() {
      let pattern = strip_outer_square_quotes(margs[i])

      if b4_pattern_matches(pattern, current) {
        return {text: margs[i + 1], st}
      }

      i = i + 2
    }

    return {text: if i < margs.len() { margs[i] } else { "" }, st}
  }

  if name == "b4_define_flag_if" or name == "_b4_define_flag_if" {
    let flag = strip_outer_square_quotes(
      if name == "b4_define_flag_if" {
        if margs.len() >= 1 { margs[0] } else { "" }
      } else {
        if margs.len() >= 3 { margs[2] } else { "" }
      },
    )

    let macro_name = f"b4_${flag.replace(".", "_").replace("-", "_")}_if"
    let body = f"b4_flag_if([${flag}], [$1], [$2])"
    return {text: "", st: mac_set(st, macro_name, body)}
  }

  if name == "b4_flag_if" {
    let flag = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    let yes = if margs.len() >= 2 { margs[1] } else { "" }
    let no = if margs.len() >= 3 { margs[2] } else { "" }

    let value = strip_outer_square_quotes(
      if mac_defined(st, f"b4_${flag}_flag") {
        mac_get(st, f"b4_${flag}_flag")
      } else {
        "0"
      },
    )

    return {text: if value == "1" { yes } else { no }, st}
  }

  if name == "b4_percent_define_default" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })

    if varname == "api.header.include" {
      return {text: "", st}
    }

    if mac_defined(st, f"b4_percent_define(${varname})") {
      return {text: "", st}
    }

    let value = strip_outer_square_quotes(if margs.len() >= 2 { margs[1] } else { "" })
    let kind = strip_outer_square_quotes(if margs.len() >= 3 and margs[2] != "" { margs[2] } else { "keyword" })
    var s2 = mac_set(st, f"b4_percent_define(${varname})", value)
    s2 = mac_set(s2, f"b4_percent_define_kind(${varname})", kind)

    s2 = mac_set(
      s2,
      f"b4_percent_define_loc(${varname})",
      "[[<skeleton default value>:-1.-1]], [[<skeleton default value>:-1.-1]]",
    )

    s2 = mac_set(s2, f"b4_percent_define_syncline(${varname})", "")
    return {text: "", st: s2}
  }

  if name == "b4_percent_define_get" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    let fallback = strip_outer_square_quotes(if margs.len() >= 2 { margs[1] } else { "" })
    let s2 = mac_set(st, f"b4_percent_define_bison_variables(${varname})", "")

    return {
      text: if mac_defined(s2, f"b4_percent_define(${varname})") { strip_outer_square_quotes(
        mac_get(s2, f"b4_percent_define(${varname})"),
      ) } else { fallback },
      st: s2,
    }
  }

  if name == "b4_percent_define_use" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    return {text: "", st: mac_set(st, f"b4_percent_define_bison_variables(${varname})", "")}
  }

  if name == "b4_percent_define_get_kind" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })

    return {
      text: if mac_defined(st, f"b4_percent_define_kind(${varname})") { strip_outer_square_quotes(
        mac_get(st, f"b4_percent_define_kind(${varname})"),
      ) } else { "keyword" },
      st,
    }
  }

  if name == "b4_percent_define_get_loc" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })

    return {
      text: if mac_defined(st, f"b4_percent_define_loc(${varname})") { mac_get(st, f"b4_percent_define_loc(${varname})") } else { "" },
      st,
    }
  }

  if name == "b4_percent_define_get_syncline" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })

    return {
      text: if mac_defined(st, f"b4_percent_define_syncline(${varname})") { mac_get(
        st,
        f"b4_percent_define_syncline(${varname})",
      ) } else { "" },
      st,
    }
  }

  if name == "b4_percent_define_check_values" or name == "_b4_percent_define_check_values" or name == "b4_percent_define_check_kind" or name == "b4_percent_define_check_file" or name == "b4_percent_define_check_file_complain" {
    return {text: "", st}
  }

  if name == "_b4_percent_define_ifdef" or name == "b4_percent_define_ifdef" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    let yes = if margs.len() >= 2 { margs[1] } else { "" }
    let no = if margs.len() >= 3 { margs[2] } else { "" }
    return {text: if mac_defined(st, f"b4_percent_define(${varname})") { yes } else { no }, st}
  }

  if name == "b4_percent_define_flag_if" {
    let varname = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    let yes = if margs.len() >= 2 { margs[1] } else { "" }
    let no = if margs.len() >= 3 { margs[2] } else { "" }

    let value = strip_outer_square_quotes(
      if mac_defined(st, f"b4_percent_define(${varname})") {
        mac_get(st, f"b4_percent_define(${varname})")
      } else {
        "false"
      },
    )

    return {text: if value == "" or value == "true" { yes } else { no }, st}
  }

  if name == "b4_percent_define_if_define" {
    let short_name = strip_outer_square_quotes(if margs.len() >= 1 { margs[0] } else { "" })
    let varname = strip_outer_square_quotes(if margs.len() >= 2 and margs[1] != "" { margs[1] } else { short_name })
    let macro_name = f"b4_${short_name.replace(".", "_").replace("-", "_")}_if"

    let body = f"""b4_percent_define_default([${varname}], [[false]])dnl
b4_percent_define_flag_if([${varname}], [$1], [$2])"""

    return {text: "", st: mac_set(st, macro_name, body)}
  }

  if name == "ifdef" {
    let n = if margs.len() >= 1 { margs[0] } else { "" }
    let yes = if margs.len() >= 2 { margs[1] } else { "" }
    let no = if margs.len() >= 3 { margs[2] } else { "" }
    return {text: if mac_defined(st, n) { yes } else { no }, st}
  }

  if name == "ifelse" {
    var cur_args = margs
    var result = ""
    var done = false

    while ! done {
      if cur_args.len() < 3 {
        result = if cur_args.len() == 1 { cur_args[0] } else { "" }
        done = true
      } else if cur_args[0] == cur_args[1] {
        result = cur_args[2]
        done = true
      } else if cur_args.len() == 3 {
        result = ""
        done = true
      } else if cur_args.len() == 4 {
        result = cur_args[3]
        done = true
      } else {
        var rest: List[Str] = []
        var ri = 3

        while ri < cur_args.len() {
          rest = rest.push(cur_args[ri])
          ri = ri + 1
        }

        cur_args = rest
      }
    }

    return {text: result, st}
  }

  if name == "divert" {
    let n = if margs.len() >= 1 { margs[0].trim() } else { "0" }
    let s2 = st.set("cur_div", if n == "" { "0" } else { n })
    return {text: "", st: s2}
  }

  if name == "undivert" {
    var s2 = st

    let targets = if margs.len() == 0 {
      [
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
      ]
    } else {
      margs
    }

    for t in targets {
      let n = t.trim()

      if n != "" {
        let content = sg(s2, f"div:${n}", "")

        if content != "" {
          s2 = emit(content, s2)
          s2 = s2.set(f"div:${n}", "")
        }
      }
    }

    return {text: "", st: s2}
  }

  if name == "divnum" {
    return {text: sg(st, "cur_div", "0"), st}
  }

  if name == "changequote" {
    let no = if margs.len() >= 1 { margs[0] } else { "`" }
    let nc = if no == "" { "" } else { if margs.len() >= 2 { margs[1] } else { "'" } }
    let s2 = st.set("open_q", no).set("close_q", nc)
    return {text: "", st: s2}
  }

  if name == "changecom" {
    let ns = if margs.len() >= 1 { margs[0] } else { "" }
    return {text: "", st: st.set("com_start", ns)}
  }

  if name == "len" {
    let s = if margs.len() >= 1 { margs[0] } else { "" }
    var count = 0
    var r = s

    while r != "" {
      match regex_captures(r, "(?s)^(.)(.*)") {
        Ok(c) => {
          count = count + 1
          r = c[2]
        }
        Err(_) => r = ""
      }
    }

    return {text: f"${count}", st}
  }

  if name == "substr" {
    let s = if margs.len() >= 1 { margs[0] } else { "" }
    let from = (if margs.len() >= 2 { margs[1].trim() } else { "0" }).parse_int()?
    var chars: List[Str] = []
    var r = s

    while r != "" {
      match regex_captures(r, "(?s)^(.)(.*)") {
        Ok(c) => {
          chars = chars.push(c[1])
          r = c[2]
        }
        Err(_) => r = ""
      }
    }

    let total = chars.len()
    let len_arg = if margs.len() >= 3 { margs[2].trim().parse_int()? } else { total - from }
    var result = ""
    var idx = if from < 0 { 0 } else { from }
    let end_idx = if idx + len_arg > total { total } else { idx + len_arg }

    while idx < end_idx {
      result = f"${result}${chars[idx]}"
      idx = idx + 1
    }

    return {text: result, st}
  }

  if name == "index" {
    let hay = if margs.len() >= 1 { margs[0] } else { "" }
    let ndl = if margs.len() >= 2 { margs[1] } else { "" }
    var pos = -1
    var p = 0
    var r = hay

    while r != "" and pos == -1 {
      if r.starts_with(ndl) {
        pos = p
      } else {
        match regex_captures(r, "(?s)^(.)(.*)") {
          Ok(c) => {
            p = p + 1
            r = c[2]
          }
          Err(_) => r = ""
        }
      }
    }

    return {text: f"${pos}", st}
  }

  if name == "translit" {
    let s = if margs.len() >= 1 { margs[0] } else { "" }
    let frm = if margs.len() >= 2 { margs[1] } else { "" }
    let too = if margs.len() >= 3 { margs[2] } else { "" }
    var from_ch: List[Str] = []
    var to_ch: List[Str] = []
    var tmp = frm

    while tmp != "" {
      match regex_captures(tmp, "(?s)^(.)(.*)") {
        Ok(c) => {
          from_ch = from_ch.push(c[1])
          tmp = c[2]
        }
        Err(_) => tmp = ""
      }
    }

    tmp = too

    while tmp != "" {
      match regex_captures(tmp, "(?s)^(.)(.*)") {
        Ok(c) => {
          to_ch = to_ch.push(c[1])
          tmp = c[2]
        }
        Err(_) => tmp = ""
      }
    }

    var result = ""
    var cur = s

    while cur != "" {
      match regex_captures(cur, "(?s)^(.)(.*)") {
        Ok(c) => {
          let ch = c[1]
          cur = c[2]
          var fi = 0
          var found_i = -1

          while fi < from_ch.len() and found_i == -1 {
            if from_ch[fi] == ch {
              found_i = fi
            }

            fi = fi + 1
          }

          if found_i >= 0 and found_i < to_ch.len() {
            result = f"${result}${to_ch[found_i]}"
          } else if found_i < 0 {
            result = f"${result}${ch}"
          }
        }
        Err(_) => cur = ""
      }
    }

    # else: delete (no corresponding to_ch entry)
    return {text: result, st}
  }

  if name == "patsubst" or name == "bpatsubst" {
    let s = if margs.len() >= 1 { margs[0] } else { "" }
    let pat = if margs.len() >= 2 { margs[1] } else { "" }
    let repl = if margs.len() >= 3 { margs[2] } else { "" }

    if pat == "" {
      return {text: s, st}
    }

    let re = regex.compile(basic_regex_to_rust(pat))?
    return {text: re.replace(s, basic_replacement_to_rust(repl)?), st}
  }

  if name == "regexp" or name == "bregexp" {
    let s = if margs.len() >= 1 { margs[0] } else { "" }
    let pat = basic_regex_to_rust(if margs.len() >= 2 { margs[1] } else { "" })
    let repl = if margs.len() >= 3 { margs[2] } else { "" }
    let compiled = regex.compile(pat)

    if repl != "" {
      match compiled {
        Ok(_) => {}
        Err(_) => return {text: "", st}
      }

      match regex_captures(s, pat) {
        Ok(c) => {
          var t = repl
          t = t.replace("\\&", c[0])
          var ri = 1

          while ri <= 9 {
            if ri < c.len() {
              t = t.replace(f"\\${ri}", c[ri])
            }

            ri = ri + 1
          }

          return {text: t, st}
        }
        Err(_) => return {text: "", st}
      }
    } else {
      let anchored_pat = f"(?s)^${pat}"

      match regex.compile(anchored_pat) {
        Ok(_) => {}
        Err(_) => return {text: "-1", st}
      }

      # Position of first match
      var pos = -1
      var p = 0
      var r = s

      while r != "" and pos == -1 {
        match regex_captures(r, anchored_pat) {
          Ok(_) => pos = p
          Err(_) => {
            match regex_captures(r, "(?s)^(.)(.*)") {
              Ok(c) => {
                p = p + 1
                r = c[2]
              }
              Err(_) => r = ""
            }
          }
        }
      }

      return {text: f"${pos}", st}
    }
  }

  if name == "format" {
    let fmt = if margs.len() >= 1 { margs[0] } else { "" }
    var cur = fmt
    var result = ""
    var ai = 1

    while cur != "" {
      if cur.starts_with("%%") {
        result = f"${result}%"
        cur = drop_prefix(drop_prefix(cur, "%")?, "%")?
      } else if cur.starts_with("%.*s") and ai + 1 < margs.len() {
        let limit = margs[ai].trim().parse_int()?
        result = f"${result}${take_chars(margs[ai + 1], limit)?}"
        ai = ai + 2
        cur = drop_prefix(drop_prefix(drop_prefix(drop_prefix(cur, "%")?, ".")?, "*")?, "s")?
      } else {
        match regex_captures(cur, "(?s)^%(-?)(\\*)s(.*)") {
          Ok(c) => {
            if c.len() >= 4 and ai + 1 < margs.len() {
              let width = margs[ai].trim().parse_int()?
              result = f"${result}${format_field(margs[ai + 1], width, c[1] == "-")}"
              ai = ai + 2
              cur = c[3]
              continue
            }
          }
          Err(_) => {}
        }

        match regex_captures(cur, "(?s)^%(-?)([0-9]+)s(.*)") {
          Ok(c) => {
            if c.len() >= 4 and ai < margs.len() {
              let width = c[2].parse_int()?
              result = f"${result}${format_field(margs[ai], width, c[1] == "-")}"
              ai = ai + 1
              cur = c[3]
              continue
            }
          }
          Err(_) => {}
        }

        match regex_captures(cur, "(?s)^%[-]?[sdiouxXeEfFgGaAcp](.*)") {
          Ok(c) => {
            if c.len() >= 2 and ai < margs.len() {
              result = f"${result}${margs[ai]}"
              ai = ai + 1
              cur = c[1]
              continue
            }
          }
          Err(_) => {}
        }

        let ch = take_char(cur)?
        result = f"${result}${ch.content}"
        cur = ch.rest
      }
    }

    return {text: result, st}
  }

  if name == "eval" {
    let expr = if margs.len() >= 1 { margs[0].trim() } else { "0" }

    match expr.parse_int() {
      Ok(n) => return {text: f"${n}", st}
      Err(_) => {
        # Simple binary operations only
        match regex_captures(expr, "(?s)^\\s*(-?\\d+)\\s*([+\\-\\*\\/\\%])\\s*(-?\\d+)\\s*$") {
          Ok(c) => {
            if c.len() < 4 {
              return {text: "0", st}
            }

            let a = c[1].parse_int()?
            let op = c[2]
            let b = c[3].parse_int()?

            let result = if op == "+" {
              a + b
            } else if op == "-" {
              a - b
            } else if op == "*" {
              a * b
            } else if op == "/" {
              a / b
            } else {
              a % b
            }

            return {text: f"${result}", st}
          }
          Err(_) => return {text: "0", st}
        }
      }
    }
  }

  if name == "incr" {
    let n = (if margs.len() >= 1 { margs[0] } else { "0" }).trim().parse_int()?
    return {text: f"${n + 1}", st}
  }

  if name == "decr" {
    let n = (if margs.len() >= 1 { margs[0] } else { "0" }).trim().parse_int()?
    return {text: f"${n - 1}", st}
  }

  if name == "shift" {
    if margs.len() <= 1 {
      return {text: "", st}
    }

    var parts: List[Str] = []
    var shift_index = 1

    while shift_index < margs.len() {
      parts = parts.push(f"${oq}${margs[shift_index]}${cq}")
      shift_index = shift_index + 1
    }

    return {text: parts.join(","), st}
  }

  if name == "errprint" {
    let msg = if margs.len() >= 1 { margs[0] } else { "" }
    eprint ${msg}
    return {text: "", st}
  }

  if name == "m4exit" {
    let code = (if margs.len() >= 1 { margs[0].trim() } else { "0" }).parse_int()?
    abort(code)
    return {text: "", st}
  }

  if name == "m4wrap" {
    let wrap_text = if margs.len() >= 1 { margs[0] } else { "" }
    let prev = sg(st, "wrap", "")
    return {text: "", st: st.set("wrap", f"${prev}${wrap_text}")}
  }

  if name == "dumpdef" {
    for arg in margs {
      eprint f"${arg}: ${mac_get(st, arg)}"
    }

    return {text: "", st}
  }

  if name == "traceon" or name == "traceoff" or name == "debugmode" or name == "debugfile" {
    return {text: "", st}
  }

  if name == "builtin" {
    let target = if margs.len() >= 1 { margs[0] } else { "" }
    var iargs: List[Str] = []
    var ii = 1

    while ii < margs.len() {
      iargs = iargs.push(margs[ii])
      ii = ii + 1
    }

    return call_builtin(target, iargs, st)?
  }

  if name == "indir" {
    let target = if margs.len() >= 1 { margs[0] } else { "" }
    var iargs: List[Str] = []
    var ii = 1

    while ii < margs.len() {
      iargs = iargs.push(margs[ii])
      ii = ii + 1
    }

    if mac_defined(st, target) {
      let body = mac_get(st, target)

      if body == "BUILTIN" or body.starts_with("BUILTIN:") {
        let builtin_name = builtin_target_name(target, body)
        return call_builtin(builtin_name, iargs, st)?
      }

      return {text: subst_args(body, target, iargs, oq, cq)?, st}
    }

    return {text: "", st}
  }

  if name == "include" or name == "sinclude" {
    let filepath = if margs.len() >= 1 { margs[0] } else { "" }
    let paths_str = sg(st, "include_paths", "")
    var found_path: Path = Path.parse(filepath)?
    var found = false

    for p in paths_str.split("""
""") {
      if p != "" {
        let cand = fp"${p}/${filepath}"

        if fs.exists(cand)? {
          found_path = cand
          found = true
        }
      }
    }

    if ! found {
      let cand = Path.parse(filepath)?

      if fs.exists(cand)? {
        found_path = cand
        found = true
      }
    }

    if ! found {
      if name == "sinclude" {
        return {text: "", st}
      }

      return Err(ScriptError.Failed("m4-include", f"cannot open: ${filepath}"))
    }

    let content = fs.read_text(found_path)?
    let s2 = st.set("file", found_path.display())

    # Expand the included file, passing through the current diversion state
    return expand_full(content, s2)?
  }

  if name == "esyscmd" {
    let cmd = if margs.len() >= 1 { margs[0] } else { "" }

    match run.text "sh" "-c" $cmd {
      Ok(out) => return {text: out, st: st.set("sysval", "0")}
      Err(_) => return {text: "", st: st.set("sysval", "1")}
    }
  }

  if name == "syscmd" {
    let cmd = if margs.len() >= 1 { margs[0] } else { "" }

    match regex_captures(
      cmd,
      """(?s)^cat <<'_m4eof'
(.*)
_m4eof
?$""",
    ) {
      Ok(c) => {
        if c.len() >= 2 {
          io.write_stdout(c[1])?
          return {text: "", st: st.set("sysval", "0")}
        }
      }
      Err(_) => {}
    }

    match regex_captures(
      cmd,
      """(?s)^\\[(.*)\\]@
_m4eof
?$""",
    ) {
      Ok(c) => {
        if c.len() >= 2 {
          io.write_stdout(f"""${c[1]}@
""")?

          return {text: "", st: st.set("sysval", "0")}
        }
      }
      Err(_) => {}
    }

    let status = run.status "sh" "-c" $cmd
    return {text: "", st: st.set("sysval", if status.ok { "0" } else { "1" })}
  }

  if name == "sysval" {
    return {text: sg(st, "sysval", "0"), st}
  }

  if name == "__file__" {
    return {text: sg(st, "file", ""), st}
  }

  if name == "__line__" {
    return {text: sg(st, "line", "0"), st}
  }

  # Unknown: pass through empty
  {text: "", st}
}

# ── core expanders ────────────────────────────────────────────────────────────
# Expand text to a string value (for argument evaluation).
# Saves and restores diversion state; macro-table changes ARE propagated
# (a define() inside an argument is unusual but should be honoured).
proc expand_for_arg(input: Str, st: Map[Str]) [fs, process, env, error, io] -> Result[ExpandResult] {
  let saved_div = sg(st, "cur_div", "0")
  let s2 = st.set("cur_div", "scratch").set("div:scratch", "")
  let s3 = expand_full(input, s2)?
  let result_text = sg(s3.st, "div:scratch", "")
  let s4 = s3.st.set("cur_div", saved_div).set("div:scratch", "")
  {text: result_text, st: s4}
}

proc expand_raw_arg(
  raw_list: List[Str],
  index: Int,
  st: Map[Str],
) [fs, process, env, error, io] -> Result[ExpandResult] {
  if index < raw_list.len() {
    return expand_for_arg(raw_list[index].trim(), st)
  }

  return {text: "", st}
}

proc call_conditional_builtin(
  name: Str,
  raw_list: List[Str],
  st: Map[Str],
) [fs, process, env, error, io] -> Result[ExpandResult] {
  if name == "ifdef" {
    let n = expand_raw_arg(raw_list, 0, st)?
    let branch = if mac_defined(n.st, n.text) { 1 } else { 2 }
    return expand_raw_arg(raw_list, branch, n.st)
  }

  var cur_args = raw_list
  var cur_st = st

  while true {
    if cur_args.len() < 3 {
      if cur_args.len() == 1 {
        return expand_raw_arg(cur_args, 0, cur_st)
      }

      return {text: "", st: cur_st}
    }

    let left = expand_raw_arg(cur_args, 0, cur_st)?
    cur_st = left.st
    let right = expand_raw_arg(cur_args, 1, cur_st)?
    cur_st = right.st

    if left.text == right.text {
      return expand_raw_arg(cur_args, 2, cur_st)
    }

    if cur_args.len() == 3 {
      return {text: "", st: cur_st}
    }

    if cur_args.len() == 4 {
      return expand_raw_arg(cur_args, 3, cur_st)
    }

    var rest: List[Str] = []
    var ri = 3

    while ri < cur_args.len() {
      rest = rest.push(cur_args[ri])
      ri = ri + 1
    }

    cur_args = rest
  }

  return {text: "", st: cur_st}
}

# Full expansion: process input, emit to current diversion, return updated state.
proc expand_full(input: Str, st: Map[Str]) [fs, process, env, error, io] -> Result[ExpandResult] {
  var rem = input
  var cur_st = st

  while rem != "" {
    let oq = sg(cur_st, "open_q", "`")
    let cq = sg(cur_st, "close_q", "'")
    let cs = sg(cur_st, "com_start", "#")

    # Comment: pass through to output (comments are uninterpreted text in GNU m4).
    # Only recognized when not inside an argument list; we rely on the caller to
    # use expand_for_arg (scratch diversion) for arguments.
    if rem.starts_with("# b4_") or rem.starts_with("# m4_") {
      match regex_captures(
        rem,
        """(?s)^[^
]*
?(.*)""",
      ) {
        Ok(c) => {
          if c.len() >= 2 {
            rem = c[1]
          } else {
            rem = ""
          }
        }
        Err(_) => rem = ""
      }
    } else if cs != "" and rem.starts_with(cs) {
      match regex_captures(
        rem,
        """(?s)^([^
]*
?)(.*)""",
      ) {
        Ok(c) => {
          cur_st = emit(c[1], cur_st)
          rem = c[2]
        }
        Err(_) => rem = ""
      }
    } else if oq != "" and rem.starts_with(oq) {
      # Quoted string: strip quotes, emit content verbatim (no re-expansion)
      let qr = collect_quoted(rem, oq, cq)?
      cur_st = emit(qr.content, cur_st)
      rem = qr.rest
    } else {
      # Identifier: possible macro call
      match regex_captures(rem, "(?s)^([A-Za-z_][A-Za-z0-9_]*)(.*)") {
        Ok(id) => {
          if id.len() >= 3 {
            let word = id[1]
            rem = id[2]

            # dnl: discard from here to (and including) the next newline.
            if word == "dnl" or word == "m4_dnl" {
              match regex_captures(
                rem,
                """(?s)^[^
]*
?(.*)""",
              ) {
                Ok(c) => {
                  if c.len() >= 2 {
                    rem = c[1]
                  } else {
                    rem = ""
                  }
                }
                Err(_) => rem = ""
              }
            } else if mac_defined(cur_st, word) {
              # Collect arguments if '(' immediately follows
              var call_args: List[Str] = []
              var raw_list: List[Str] = []

              if rem.starts_with("(") {
                let ar = collect_args_raw(rem, oq, cq)?
                rem = ar.rest
                raw_list = split_args(ar.raw, oq, cq)?
              }

              # Dispatch: built-in or user macro
              let body = mac_get(cur_st, word)
              var result = {text: "", st: cur_st}

              if native_sugar_builtin(word) {
                for ra in raw_list {
                  let ae = expand_for_arg(ra.trim(), cur_st)?
                  cur_st = ae.st
                  call_args = call_args.push(ae.text)
                }

                result = call_builtin(word, call_args, cur_st)?
              } else if body == "BUILTIN" or body.starts_with("BUILTIN:") {
                let builtin_name = builtin_target_name(word, body)

                if builtin_name == "ifdef" or builtin_name == "ifelse" {
                  result = call_conditional_builtin(builtin_name, raw_list, cur_st)?
                } else {
                  for ra in raw_list {
                    # Expand each argument: macro-table changes propagate, diversion isolated
                    let ae = expand_for_arg(ra.trim(), cur_st)?
                    cur_st = ae.st
                    call_args = call_args.push(ae.text)
                  }

                  result = call_builtin(builtin_name, call_args, cur_st)?
                }
              } else {
                for ra in raw_list {
                  # Expand each argument: macro-table changes propagate, diversion isolated
                  let ae = expand_for_arg(ra.trim(), cur_st)?
                  cur_st = ae.st
                  call_args = call_args.push(ae.text)
                }

                let expanded_body = subst_args(body, word, call_args, oq, cq)?

                # Re-scan: prepend expansion to rem rather than recursing
                rem = f"${expanded_body}${rem}"
              }

              cur_st = result.st

              if result.text != "" {
                # Re-scan the built-in's return text
                rem = f"${result.text}${rem}"
              }
            } else {
              let tail = take_undefined_tail(rem, oq, cs, cur_st)?
              cur_st = emit(f"${word}${tail.content}", cur_st)
              rem = tail.rest
            }
          } else {
            match regex_captures(rem, "(?s)^(.)(.*)") {
              Ok(c) => {
                if c.len() >= 3 {
                  cur_st = emit(c[1], cur_st)
                  rem = c[2]
                } else {
                  rem = ""
                }
              }
              Err(_) => rem = ""
            }
          }
        }
        Err(_) => {
          let chunk = take_literal_chunk(rem, oq, cs)?
          cur_st = emit(chunk.content, cur_st)
          rem = chunk.rest
        }
      }
    }
  }

  return {text: sg(cur_st, f"div:{sg(cur_st, 'cur_div', '0')}", ""), st: cur_st}
}

# ── built-in registration ─────────────────────────────────────────────────────
proc register_builtins(st: Map[Str], prefix: Bool) [error] -> Result[Map[Str]] {
  var s = st

  let names = [
    "define",
    "undefine",
    "defn",
    "pushdef",
    "popdef",
    "ifdef",
    "ifelse",
    "include",
    "sinclude",
    "divert",
    "undivert",
    "divnum",
    "dnl",
    "changequote",
    "changecom",
    "len",
    "substr",
    "index",
    "translit",
    "patsubst",
    "regexp",
    "bpatsubst",
    "bregexp",
    "format",
    "eval",
    "incr",
    "decr",
    "shift",
    "errprint",
    "m4exit",
    "m4wrap",
    "dumpdef",
    "traceon",
    "traceoff",
    "debugmode",
    "debugfile",
    "indir",
    "builtin",
    "esyscmd",
    "syscmd",
    "sysval",
    "__file__",
    "__line__",
  ]

  for n in names {
    if ! prefix {
      s = mac_set(s, n, "BUILTIN")
    }

    s = mac_set(s, f"m4_${n}", "BUILTIN")
  }

  return s
}

proc parse_define_arg(def: Str) [error] -> Result[List[Str]] {
  match regex_captures(def, "^([^=]+)=(.*)") {
    Ok(c) => return [c[1], c[2]]
    Err(_) => {}
  }

  return [def, "1"]
}

# ── main ─────────────────────────────────────────────────────────────────────
proc main(margs: List[Str] = []) [fs, process, env, error, io] {
  var include_paths: List[Str] = []
  var defines: List[List[Str]] = []
  var files: List[Str] = []
  var prefix = false
  var i = 0

  while i < margs.len() {
    let a = margs[i]

    if a == "--version" {
      io.write_stdout("m4.xsh 1.0\n")?
      return
    } else if a == "--help" or a == "-h" {
      io.write_stdout("usage: m4 [OPTION]... [FILE]...\n")?
      return
    } else if a == "-P" or a == "--prefix-builtins" {
      prefix = true
    } else if a == "--" {
      i = i + 1

      while i < margs.len() {
        files = files.push(margs[i])
        i = i + 1
      }
    } else if a == "-I" and i + 1 < margs.len() {
      i = i + 1
      include_paths = include_paths.push(margs[i])
    } else if a.starts_with("-I") {
      include_paths = include_paths.push(a.replace("-I", ""))
    } else if a == "-D" and i + 1 < margs.len() {
      i = i + 1
      defines = defines.push(parse_define_arg(margs[i])?)
    } else if a.starts_with("-D") {
      let def = a.replace("-D", "")
      defines = defines.push(parse_define_arg(def)?)
    } else if a == "-" {
      files = files.push(a)
    } else if a.starts_with("-") {} else {
      # ignore unknown flags
      files = files.push(a)
    }

    i = i + 1
  }

  var st: Map[Str] = map.empty()
  st = st.set("open_q", "`").set("close_q", "'")
  st = st.set("com_start", "#")
  st = st.set("cur_div", "0").set("div:0", "")
  st = st.set("wrap", "").set("sysval", "0")
  st = st.set("file", "").set("line", "1")

  st = st.set(
    "include_paths",
    include_paths.join("""
"""),
  )

  st = register_builtins(st, prefix)?
  st = mac_set(st, "__gnu__", "")
  st = mac_set(st, "__unix__", "")
  st = mac_set(st, "__m4_version__", "1")

  for def_pair in defines {
    let n = def_pair[0]
    let v = if def_pair.len() >= 2 { def_pair[1] } else { "" }
    st = mac_set(st, n, v)

    if prefix {
      st = mac_set(st, f"m4_${n}", v)
    }
  }

  if files.len() == 0 {
    # No file args: read stdin
    let content = io.stdin_text()?
    st = st.set("file", "stdin")
    let r = expand_full(content, st)?
    st = r.st
  } else {
    for filepath in files {
      let content = if filepath == "-" { io.stdin_text()? } else { fs.read_text(Path.parse(filepath)?)? }
      st = st.set("file", if filepath == "-" { "stdin" } else { filepath })
      let r = expand_full(content, st)?
      st = r.st
    }
  }

  # Process m4wrap queue
  let wrap = sg(st, "wrap", "")

  if wrap != "" {
    st = st.set("wrap", "")
    let r = expand_full(wrap, st)?
    st = r.st
  }

  # Flush div:0 to stdout
  let output = sg(st, "div:0", "")
  io.write_stdout(output)?
}

main(args)?
