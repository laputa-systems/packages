#!/usr/local/bin/xsh --
error ToolError = Failed(kind: Str, message: Str)

type TextRest = {content: Str, rest: Str}

type LexRule = {pattern: Str, action: Str, bol: Bool, state: Str}

type LexOptions = {input: Str, output: Str, to_stdout: Bool, verbose: Bool, delegate: Bool, delegate_reason: Str}

type LexProgram = {rules: List[LexRule], user_code: Str, states: List[Str], exclusive: List[Str]}

type PatternAction = {pattern: Str, action: Str}

type StateQualifier = {states: List[Str], pattern: Str}

pure regex_captures(text: Str, pattern: Str) -> Result[List[Str]] {
  let re = regex.compile(pattern)?
  return re.captures(text)
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
  var cur = text
  var rem = prefix

  while rem != "" {
    let next_rem = take_char(rem)?
    let next_cur = take_char(cur)?
    rem = next_rem.rest
    cur = next_cur.rest
  }

  return cur
}

pure c_quote(text: Str) -> Str {
  return text.replace("\\", "\\\\").replace("\"", "\\\"").replace(
    """
""",
    "\\n",
  )
}

proc lex_literal_to_regex(raw: Str) [error] -> Result[Str] {
  var cur = raw
  var out = ""

  while cur != "" {
    let ch = take_char(cur)?
    cur = ch.rest

    if ch.content == "\\" and cur != "" {
      let escaped = take_char(cur)?
      cur = escaped.rest

      if escaped.content == "n" {
        out = f"${out}\\n"
      } else if escaped.content == "t" {
        out = f"${out}\\t"
      } else {
        out = f"${out}\\${escaped.content}"
      }
    } else {
      match ch.content {
        "." => out = f"${out}\\."
        "*" => out = f"${out}\\*"
        "+" => out = f"${out}\\+"
        "?" => out = f"${out}\\?"
        "(" => out = f"${out}\\("
        ")" => out = f"${out}\\)"
        "[" => out = f"${out}\\["
        "]" => out = f"${out}\\]"
        "{" => out = f"${out}\\{"
        "}" => out = f"${out}\\}"
        "|" => out = f"${out}\\|"
        "^" => out = f"${out}\\^"
        "$" => out = f"${out}\\$"
        "\\" => out = f"${out}\\\\"
        _ => out = f"${out}${ch.content}"
      }
    }
  }

  return out
}

proc strip_quotes(pattern: Str) [error] -> Result[Str] {
  match regex_captures(pattern, "(?s)^\"(.*)\"$") {
    Ok(c) => {
      if c.len() >= 2 {
        return lex_literal_to_regex(c[1])
      }
    }
    Err(_) => {}
  }

  return pattern
}

proc expand_definitions(pattern: Str, defs: Map[Str]) [error] -> Result[Str] {
  var out = pattern

  for name in defs.keys() {
    out = out.replace(f"{${name}}", f"(${defs.get(name, "")})")
  }

  return out
}

proc parse_definitions(text: Str) [error] -> Result[Map[Str]] {
  var defs: Map[Str] = map.empty()

  for raw in text.lines() {
    let line = raw.trim()
    continue when line == "" or line.starts_with("%")

    match regex_captures(line, "^([A-Za-z_][A-Za-z0-9_]*)[ \t]+(.+)$") {
      Ok(c) => {
        if c.len() >= 3 {
          defs[c[1]] = c[2].trim()
        }
      }
      Err(_) => {}
    }
  }

  return defs
}

proc parse_start_conditions(text: Str) [error] -> Result[List[Str]] {
  var states: List[Str] = []

  for raw in text.lines() {
    let words = raw.trim().split(" ") |> where . != ""

    if words.len() >= 2 and (words[0] == "%s" or words[0] == "%x") {
      var i = 1

      while i < words.len() {
        if ! states.contains(words[i]) {
          states = states.push(words[i])
        }

        i = i + 1
      }
    }
  }

  return states
}

proc parse_exclusive_start_conditions(text: Str) [error] -> Result[List[Str]] {
  var states: List[Str] = []

  for raw in text.lines() {
    let words = raw.trim().split(" ") |> where . != ""

    if words.len() >= 2 and words[0] == "%x" {
      var i = 1

      while i < words.len() {
        if ! states.contains(words[i]) {
          states = states.push(words[i])
        }

        i = i + 1
      }
    }
  }

  return states
}

proc split_rule_line(raw: Str) [error] -> Result[PatternAction] {
  var cur = raw
  var pattern = ""
  var in_class = false
  var in_quote = false
  var escaped = false

  while cur != "" {
    let ch = take_char(cur)?
    cur = ch.rest

    if ! in_class and ! in_quote and pattern != "" and (ch.content == " " or ch.content == "\t") {
      while cur.starts_with(" ") or cur.starts_with("\t") {
        let skipped = take_char(cur)?
        cur = skipped.rest
      }

      return {pattern, action: cur.trim()}
    }

    pattern = f"${pattern}${ch.content}"

    if escaped {
      escaped = false
    } else if ch.content == "\\" {
      escaped = true
    } else if ch.content == "\"" and ! in_class {
      in_quote = ! in_quote
    } else if ch.content == "[" and ! in_quote {
      in_class = true
    } else if ch.content == "]" and in_class {
      in_class = false
    }
  }

  return Err(ToolError.Failed("lex", f"missing action for rule: ${raw}"))
}

proc split_state_qualifier(pattern: Str) [error] -> Result[StateQualifier] {
  match regex_captures(pattern, "^<([^>]+)>(.+)$") {
    Ok(c) => {
      if c.len() >= 3 {
        let states = c[1].split(",")
          |> map .trim()
          |> where . != ""

        return {states, pattern: c[2]}
      }
    }
    Err(_) => {}
  }

  let states: List[Str] = []
  return {states, pattern}
}

proc parse_rules(text: Str, defs: Map[Str]) [error] -> Result[List[LexRule]] {
  var rules: List[LexRule] = []

  for raw in text.lines() {
    continue when raw.trim() == "" or raw.starts_with(" ") or raw.starts_with("\t") or raw.trim().starts_with("%")
    let parsed = split_rule_line(raw)?
    var pattern = parsed.pattern
    let action = parsed.action

    if action.contains("REJECT") {
      return Err(ToolError.Failed("unsupported", "flex.xsh does not support REJECT"))
    }

    let qualified = split_state_qualifier(pattern)?
    pattern = qualified.pattern
    var bol = false

    if pattern.starts_with("^") {
      bol = true
      pattern = drop_prefix(pattern, "^")?
    }

    pattern = strip_quotes(expand_definitions(pattern, defs)?)?

    if qualified.states.len() == 0 {
      rules = rules.push({pattern, action, bol, state: ""})
    } else {
      for state in qualified.states {
        rules = rules.push({pattern, action, bol, state})
      }
    }
  }

  if rules.len() == 0 {
    return Err(ToolError.Failed("lex", "no rules found"))
  }

  return rules
}

proc reject_unsupported_options(text: Str) [error] {
  for raw in text.lines() {
    let line = raw.trim()

    if line.starts_with("%option") and line.contains("reject") {
      return Err(ToolError.Failed("unsupported", "flex.xsh does not support REJECT"))
    }
  }
}

pure upstream_flex_source_reason(text: Str) -> Str {
  if text.contains("<<EOF>>") {
    return "flex.xsh delegates EOF-rule scanners to upstream flex"
  }

  if text.contains("YY_USER_ACTION") {
    return "flex.xsh delegates scanners with YY_USER_ACTION to upstream flex"
  }

  if text.contains("yyterminate") {
    return "flex.xsh delegates scanners using yyterminate to upstream flex"
  }

  if text.contains("yyless") or text.contains("unput") {
    return "flex.xsh delegates scanners using flex buffer mutation APIs to upstream flex"
  }

  return ""
}

proc upstream_disabled() [env] -> Bool {
  return (env.get("XSH_FLEX_NO_UPSTREAM") ?? "") == "1"
}

proc run_upstream_flex(argv: List[Str], reason: Str) [process, env, error] {
  if upstream_disabled() {
    return Err(ToolError.Failed("unsupported", reason))
  }

  match process.which("flex") {
    Ok(bin) => run $bin @argv ?
    Err(_) => return Err(ToolError.Failed("unsupported", reason))
  }
}

proc parse_lex_file(source: Str) [error] -> Result[LexProgram] {
  let parts = source.split("%%")

  if parts.len() < 2 {
    return Err(ToolError.Failed("lex", "input must contain definitions and rules separated by %%"))
  }

  reject_unsupported_options(parts[0])?
  let defs = parse_definitions(parts[0])?
  let states = parse_start_conditions(parts[0])?
  let exclusive = parse_exclusive_start_conditions(parts[0])?
  var user_code = ""
  var i = 2

  while i < parts.len() {
    if i > 2 {
      user_code = f"${user_code}%%"
    }

    user_code = f"${user_code}${parts[i]}"
    i = i + 1
  }

  return {rules: parse_rules(parts[1], defs)?, user_code, states, exclusive}
}

proc extract_c_block(text: Str) [error] -> Result[Str] {
  match regex_captures(text, "(?s)%\\{(.*?)%\\}") {
    Ok(c) => {
      if c.len() >= 2 {
        return c[1]
      }
    }
    Err(_) => {}
  }

  return ""
}

proc lex_user_code(source: Str) [error] -> Result[Str] {
  let parts = source.split("%%")
  var user_code = ""
  var i = 2

  while i < parts.len() {
    if i > 2 {
      user_code = f"${user_code}%%"
    }

    user_code = f"${user_code}${parts[i]}"
    i = i + 1
  }

  return user_code
}

proc generate_linux_stub(source: Str) [error] -> Result[Str] {
  let parts = source.split("%%")

  if parts.len() < 2 {
    return Err(ToolError.Failed("lex", "input must contain definitions and rules separated by %%"))
  }

  let prologue = extract_c_block(parts[0])?
  let user_code = lex_user_code(source)?
  let states = parse_start_conditions(parts[0])?
  let state_defines = generate_state_defines(states)?

  return f"""#include <stdio.h>
#include <stdlib.h>
#include <string.h>

FILE *yyin;
FILE *yyout;
char *yytext;
int yyleng;
int yylineno = 1;

typedef struct yy_buffer_state *YY_BUFFER_STATE;
struct yy_buffer_state {
  FILE *file;
};

#define YY_BUF_SIZE 16384
#define YY_CURRENT_BUFFER ((YY_BUFFER_STATE)0)
${state_defines}
#define BEGIN(state) ((void)(state))
#define YY_START 0

#ifndef ECHO
#define ECHO fwrite(yytext, 1, (size_t)yyleng, yyout)
#endif

static int input(void)
{
  return yyin ? fgetc(yyin) : EOF;
}

static void unput(int c)
{
  if (yyin && c != EOF) {
    ungetc(c, yyin);
  }
}

YY_BUFFER_STATE yy_create_buffer(FILE *file, int size)
{
  (void)size;
  YY_BUFFER_STATE buffer = malloc(sizeof(*buffer));
  if (buffer) {
    buffer->file = file;
  }
  return buffer;
}

void yy_switch_to_buffer(YY_BUFFER_STATE buffer)
{
  if (buffer) {
    yyin = buffer->file;
  }
}

void yypush_buffer_state(YY_BUFFER_STATE buffer)
{
  yy_switch_to_buffer(buffer);
}

void yy_delete_buffer(YY_BUFFER_STATE buffer)
{
  free(buffer);
}

void yy_pop_buffer_state(void)
{
}

void yypop_buffer_state(void)
{
  yy_pop_buffer_state();
}

int yywrap(void)
{
  return 1;
}

${prologue}

#ifndef YY_DECL
#define YY_DECL int yylex(void)
#endif

YY_DECL
{
  return 0;
}

${user_code}
"""
}

proc state_id(state: Str, states: List[Str]) [error] -> Result[Int] {
  var i = 0

  while i < states.len() {
    if states[i] == state {
      return i + 1
    }

    i = i + 1
  }

  return -1
}

proc generate_state_defines(states: List[Str]) [error] -> Result[Str] {
  var lines: List[Str] = ["#define INITIAL 0"]
  var i = 0

  while i < states.len() {
    lines = lines.push(f"#define ${states[i]} ${i + 1}")
    i = i + 1
  }

  return lines.join("""
""")
}

proc generate_exclusive_table(states: List[Str], exclusive: List[Str]) [error] -> Result[Str] {
  var values: List[Str] = ["0"]

  for state in states {
    values = values.push(if exclusive.contains(state) { "1" } else { "0" })
  }

  return values.join(", ")
}

proc generate_rule_table(rules: List[LexRule], states: List[Str]) [error] -> Result[Str] {
  var lines: List[Str] = []

  for rule in rules {
    let bol = if rule.bol { "1" } else { "0" }

    let state = if rule.state == "" {
      "-1"
    } else if rule.state == "*" {
      "-2"
    } else {
      f"${state_id(rule.state, states)?}"
    }

    if state == "-1" and rule.state != "" {
      return Err(ToolError.Failed("lex", f"unknown start condition: ${rule.state}"))
    }

    lines = lines.push(f"  {\"^(${c_quote(rule.pattern)})\", ${bol}, ${state}},")
  }

  return lines.join("""
""")
}

proc generate_actions(rules: List[LexRule]) [error] -> Result[Str] {
  var lines: List[Str] = []
  var i = 0

  for rule in rules {
    lines = lines.push(f"    case ${i}: { ${rule.action} } break;")
    i = i + 1
  }

  return lines.join("""
""")
}

pure generated_main(user_code: Str) -> Str {
  if user_code.contains(" main(") or user_code.contains("int main(") {
    return ""
  }

  return """
#ifndef YY_NO_MAIN
int main(void) {
  return yylex();
}
#endif
"""
}

proc generate_c(rules: List[LexRule], user_code: Str, states: List[Str], exclusive: List[Str]) [error] -> Result[Str] {
  let table = generate_rule_table(rules, states)?
  let actions = generate_actions(rules)?
  let generated_main_text = generated_main(user_code)
  let state_defines = generate_state_defines(states)?
  let exclusive_table = generate_exclusive_table(states, exclusive)?

  return f"""#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

FILE *yyin;
FILE *yyout;
char *yytext;
int yyleng;

${state_defines}
#define BEGIN(state) (yy_start = (state))

#ifndef ECHO
#define ECHO fwrite(yytext, 1, (size_t)yyleng, yyout)
#endif

struct yy_rule {
  const char *pattern;
  int bol;
  int state;
};

static struct yy_rule yy_rules[] = {
${table}
};

static int yy_start;
static int yy_exclusive[] = {${exclusive_table}};
static regex_t yy_regexes[sizeof(yy_rules) / sizeof(yy_rules[0])];
static int yy_ready;
static char *yy_input;
static size_t yy_pos;
static size_t yy_len;
static int yy_has_hold;
static size_t yy_hold_pos;
static char yy_hold;

static char *yy_read_all(FILE *in) {
  size_t cap = 4096;
  size_t len = 0;
  char *buf = malloc(cap);
  int ch;

  if (!buf) {
    return NULL;
  }

  while ((ch = fgetc(in)) != EOF) {
    if (len + 2 >= cap) {
      cap *= 2;
      char *next = realloc(buf, cap);
      if (!next) {
        free(buf);
        return NULL;
      }
      buf = next;
    }
    buf[len++] = (char)ch;
  }

  buf[len] = 0;
  return buf;
}

static void yy_restore_hold(void) {
  if (yy_has_hold) {
    yy_input[yy_hold_pos] = yy_hold;
    yy_has_hold = 0;
  }
}

static int yy_rule_active(struct yy_rule *rule) {
  if (rule->state == -2) {
    return 1;
  }
  if (rule->state >= 0) {
    return rule->state == yy_start;
  }
  if (yy_start == 0) {
    return 1;
  }
  return !yy_exclusive[yy_start];
}

int yylex(void) {
  if (!yy_ready) {
    yyin = yyin ? yyin : stdin;
    yyout = yyout ? yyout : stdout;

    for (size_t i = 0; i < sizeof(yy_rules) / sizeof(yy_rules[0]); i++) {
      int rc = regcomp(&yy_regexes[i], yy_rules[i].pattern, REG_EXTENDED | REG_NEWLINE);
      if (rc != 0) {
        fprintf(stderr, "lex.yy.c: failed to compile generated regex %zu\\n", i);
        return 2;
      }
    }

    yy_input = yy_read_all(yyin);
    if (!yy_input) {
      return 2;
    }

    yy_len = strlen(yy_input);
    yy_ready = 1;
  }

  yy_restore_hold();

  while (yy_pos < yy_len) {
    int best = -1;
    size_t best_len = 0;

    for (size_t i = 0; i < sizeof(yy_rules) / sizeof(yy_rules[0]); i++) {
      if (!yy_rule_active(&yy_rules[i])) {
        continue;
      }

      if (yy_rules[i].bol && yy_pos != 0 && yy_input[yy_pos - 1] != '\\n') {
        continue;
      }

      regmatch_t match;
      if (regexec(&yy_regexes[i], yy_input + yy_pos, 1, &match, 0) == 0 && match.rm_so == 0) {
        size_t n = (size_t)match.rm_eo;
        if (n > best_len) {
          best = (int)i;
          best_len = n;
        }
      }
    }

    if (best < 0 || best_len == 0) {
      yytext = yy_input + yy_pos;
      yyleng = 1;
      ECHO;
      yy_pos++;
      continue;
    }

    yy_hold_pos = yy_pos + best_len;
    yy_hold = yy_input[yy_hold_pos];
    yy_input[yy_hold_pos] = 0;
    yy_has_hold = 1;
    yytext = yy_input + yy_pos;
    yyleng = (int)best_len;
    yy_pos += best_len;

    switch (best) {
${actions}
    }

    yy_restore_hold();
  }

  return 0;
}

${user_code}
${generated_main_text}
"""
}

proc usage() [error, io] {
  io.write_stdout("""usage: flex.xsh [OPTIONS] [FILE]

Options:
  -o, --outfile FILE  write scanner to FILE
  -L                  accepted through upstream flex compatibility
  -t, --stdout        write scanner to stdout
  -n                  accepted for POSIX compatibility
  -v, --verbose       print a short generation summary to stderr
  --help              show this help
  --version           show version
""")?
}

proc parse_options(argv: List[Str]) [error, io] -> Result[LexOptions] {
  var input = "-"
  var output = "lex.yy.c"
  var to_stdout = false
  var verbose = false
  var delegate = false
  var delegate_reason = ""
  var i = 0

  while i < argv.len() {
    let a = argv[i]

    if a == "--help" {
      usage()?
      abort(0)
    } else if a == "--version" {
      io.write_stdout("""flex.xsh 0.1
""")?

      abort(0)
    } else if a == "-t" or a == "--stdout" {
      to_stdout = true
    } else if a == "-L" or a == "--noline" {} else if a == "-n" or a == "--nounput" or a == "--noyywrap" {} else if a == "-v" or a == "--verbose" {
      verbose = true
    } else if (a == "-o" or a == "--outfile") and i + 1 < argv.len() {
      i = i + 1
      output = argv[i]
    } else if a.starts_with("-o") and a != "-o" {
      output = drop_prefix(a, "-o")?
    } else if a.starts_with("--outfile=") {
      output = drop_prefix(a, "--outfile=")?
    } else if a.starts_with("-") {
      return Err(ToolError.Failed("usage", f"unsupported option: ${a}"))
    } else {
      input = a
    }

    i = i + 1
  }

  return {
    input,
    output,
    to_stdout,
    verbose,
    delegate,
    delegate_reason,
  }
}

proc main(argv: List[Str] = []) [fs, process, env, error, io] {
  let opt = parse_options(argv)?

  if opt.delegate {
    run_upstream_flex(argv, opt.delegate_reason)?
    return
  }

  let source = if opt.input == "-" { io.stdin_text()? } else { fs.read_text(Path.parse(opt.input)?)? }
  let upstream_reason = upstream_flex_source_reason(source)

  if upstream_reason != "" {
    if upstream_disabled() {
      let code = generate_linux_stub(source)?

      if opt.to_stdout {
        io.write_stdout(code)?
      } else {
        fs.write(Path.parse(opt.output)?, code)?
      }

      return
    }

    run_upstream_flex(argv, upstream_reason)?
    return
  }

  let parsed = parse_lex_file(source)?
  let code = generate_c(parsed.rules, parsed.user_code, parsed.states, parsed.exclusive)?

  if opt.verbose {
    eprint f"flex.xsh: ${parsed.rules.len()} rules"
  }

  if opt.to_stdout {
    io.write_stdout(code)?
  } else {
    fs.write(Path.parse(opt.output)?, code)?
  }
}

main(args)?
