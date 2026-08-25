#!/bin/xsh
##! XSH module `bison` package and build operations.
error ToolError = Failed(kind: Str, message: Str)

type TextRest = {content: Str, rest: Str}

type GrammarRule = {lhs: Str, rhs: List[Str]}

type YaccOptions = {input: Str, output: Str, defines: Bool, defines_file: Str, verbose: Bool, prefix: Str}

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

pure literal_code(token: Str) -> Int {
  return match token {
    "'\\n'" => 10,
    "'\\t'" => 9,
    "' '" => 32,
    "'!'" => 33,
    "'\"'" => 34,
    "'#'" => 35,
    "'$'" => 36,
    "'%'" => 37,
    "'&'" => 38,
    "'('" => 40,
    "')'" => 41,
    "'*'" => 42,
    "'+'" => 43,
    "','" => 44,
    "'-'" => 45,
    "'.'" => 46,
    "'/'" => 47,
    "':'" => 58,
    "';'" => 59,
    "'<'" => 60,
    "'='" => 61,
    "'>'" => 62,
    "'?'" => 63,
    "'['" => 91,
    "']'" => 93,
    "'{'" => 123,
    "'|'" => 124,
    "'}'" => 125,
    _ => -1,
  }
}

proc extract_prologue(text: Str) [error] -> Result[Str] {
  match regex_captures(text, "(?s)%\\{(.*)%\\}") {
    Ok(c) => {
      if c.len() >= 2 {
        return c[1]
      }
    }
    Err(_) => {}
  }

  return ""
}

proc parse_tokens(decls: Str) [error] -> Result[Map[Int]] {
  var tokens: Map[Int] = {}
  var code = 258

  for raw in decls.lines() {
    let line = raw.trim()

    if line.starts_with("%token") or line.starts_with("%left") or line.starts_with("%right") or line.starts_with(
      "%nonassoc",
    ) {
      for word in line.split(" ") |> where . != "" {
        continue when word == "%token" or word == "%left" or word == "%right" or word == "%nonassoc"
        continue when word.starts_with("<")

        if word.starts_with("'") {
          let value = literal_code(word)

          if value >= 0 {
            tokens[word] = value
          }
        } else {
          tokens[word] = code
          code = code + 1
        }
      }
    }
  }

  return tokens
}

proc parse_token_names(decls: Str) [error] -> Result[List[Str]] {
  var names = []

  for raw in decls.lines() {
    let line = raw.trim()

    if line.starts_with("%token") or line.starts_with("%left") or line.starts_with("%right") or line.starts_with(
      "%nonassoc",
    ) {
      for word in line.split(" ") |> where . != "" {
        continue when word == "%token" or word == "%left" or word == "%right" or word == "%nonassoc"
        continue when word.starts_with("<") or word.starts_with("'")

        if word not in names {
          names = names.push(word)
        }
      }
    }
  }

  return names
}

pure unsupported_declaration(decls: Str) -> Str {
  for raw in decls.lines() {
    let line = raw.trim()

    if line.starts_with("%union") {
      return "bison.xsh delegates %union grammars to upstream bison"
    }

    if line.starts_with("%type") {
      return "bison.xsh delegates %type grammars to upstream bison"
    }

    if line.starts_with("%left") or line.starts_with("%right") or line.starts_with("%nonassoc") {
      return "bison.xsh delegates precedence grammars to upstream bison"
    }
  }

  return ""
}

proc upstream_disabled() [env] -> Bool {
  return (env.get("XSH_BISON_NO_UPSTREAM") ?? "") == "1"
}

proc run_upstream_bison(argv: List[Str], reason: Str) [process, env, error] {
  if upstream_disabled() {
    return Err(ToolError.Failed("unsupported", reason))
  }

  match process.which("bison") {
    Ok(bin) => run $bin @argv ?
    Err(_) => return Err(ToolError.Failed("unsupported", reason))
  }
}

pure parse_start_symbol(decls: Str, fallback: Str) -> Str {
  for raw in decls.lines() {
    let line = raw.trim()

    if line.starts_with("%start") {
      let words = line.split(" ") |> where . != ""

      if words.len() >= 2 {
        return words[1]
      }
    }
  }

  return fallback
}

proc remove_actions(text: Str) [error] -> Result[Str] {
  let re = regex.compile("(?s)\\{[^{}]*\\}")?
  return re.replace(text, " ")
}

proc remove_comments(text: Str) [error] -> Result[Str] {
  let re = regex.compile("(?s)/\\*.*?\\*/")?
  return re.replace(text, " ")
}

proc parse_rules(text: Str) [error] -> Result[List[GrammarRule]] {
  let grammar = remove_comments(remove_actions(text)?)?.replace(":", " : ").replace("|", " | ").replace(";", " ; ")
  var rules = []
  var lhs = ""
  var rhs = []
  var pending_lhs = ""

  for word in grammar.split(" ") |> where .trim() != "" {
    let item = word.trim()

    if item == ":" {
      lhs = pending_lhs
      rhs = []
    } else if item == "|" {
      rules = rules.push({lhs, rhs})
      rhs = []
    } else if item == ";" {
      rules = rules.push({lhs, rhs})
      lhs = ""
      pending_lhs = ""
      rhs = []
    } else if lhs == "" {
      pending_lhs = item
    } else {
      rhs = rhs.push(item)
    }
  }

  if rules.len() == 0 {
    return Err(ToolError.Failed("yacc", "no grammar rules found"))
  }

  return rules
}

proc nonterminals(rules: List[GrammarRule]) [error] -> Result[List[Str]] {
  var names = []

  for rule in rules {
    if rule.lhs not in names {
      names = names.push(rule.lhs)
    }
  }

  return names
}

pure token_code_expr(symbol: Str, tokens: Map[Int]) -> Str {
  if tokens.has(symbol) {
    return f"${tokens.get(symbol, 0)}"
  }

  let lit = literal_code(symbol)

  if lit >= 0 {
    return f"${lit}"
  }

  return symbol
}

proc generate_token_defines(tokens: Map[Int]) [error] -> Result[Str] {
  var lines = [f"#define ${name} ${tokens.get(name, 0)}" for name in tokens.keys() if ! name.starts_with("'")]
  return lines.join("\n")
}

proc generate_header(tokens: Map[Int]) [error] -> Result[Str] {
  let defines = generate_token_defines(tokens)?

  return f"""#ifndef XSH_YY_TAB_H
#define XSH_YY_TAB_H
${defines}
int yyparse(void);
#endif
"""
}

proc extract_union_body(decls: Str) [error] -> Result[Str] {
  let parts = decls.split("%union")

  if parts.len() < 2 {
    return "int token;"
  }

  var cur = parts[1]

  while cur != "" {
    let ch = take_char(cur)?
    cur = ch.rest

    if ch.content == "{" {
      var depth = 1
      var body = ""

      while cur != "" {
        let next = take_char(cur)?
        cur = next.rest

        if next.content == "{" {
          depth = depth + 1
          body = f"${body}${next.content}"
        } else if next.content == "}" {
          depth = depth - 1

          if depth == 0 {
            return body
          }

          body = f"${body}${next.content}"
        } else {
          body = f"${body}${next.content}"
        }
      }
    }
  }

  return "int token;"
}

pure has_locations(decls: Str) -> Bool {
  return "%locations" in decls
}

proc token_enum_lines(names: List[Str]) [error] -> Result[List[Str]] {
  var lines = ["    YYEMPTY = -2,", "    YYEOF = 0,", "    YYerror = 256,", "    YYUNDEF = 257,"]
  var code = 258
  var i = 0

  while i < names.len() {
    let comma = if i + 1 < names.len() { "," } else { "" }
    lines = lines.push(f"    ${names[i]} = ${code}${comma}")
    code = code + 1
    i = i + 1
  }

  return lines
}

proc generate_linux_header(decls: Str, tokens: Map[Int]) [error] -> Result[Str] {
  let _ = tokens
  let names = parse_token_names(decls)?
  let enum_body = token_enum_lines(names)?.join("\n")
  let union_body = extract_union_body(decls)?

  let location = if has_locations(decls) {
    """

#if ! defined YYLTYPE && ! defined YYLTYPE_IS_DECLARED
typedef struct YYLTYPE YYLTYPE;
struct YYLTYPE
{
  int first_line;
  int first_column;
  int last_line;
  int last_column;
};
# define YYLTYPE_IS_DECLARED 1
# define YYLTYPE_IS_TRIVIAL 1
#endif

extern YYLTYPE yylloc;
"""
  } else {
    ""
  }

  return f"""#ifndef XSH_YY_TAB_H
#define XSH_YY_TAB_H

#ifndef YYDEBUG
# define YYDEBUG 1
#endif
#if YYDEBUG
extern int yydebug;
#endif

#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
${enum_body}
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
${union_body}
};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif

extern YYSTYPE yylval;${location}

int yyparse(void);

#endif
"""
}

proc output_header_name(output: Str) [error] -> Result[Str] {
  return fp"${output}".name.replace(".c", ".h")
}

pure is_kconfig_parser(decls: Str) -> Bool {
  return "\"lkc.h\"" in decls
}

pure is_dtc_parser(decls: Str) -> Bool {
  return "\"dtc.h\"" in decls
}

proc generate_kconfig_stub_c(output: Str, prologue: Str, epilogue: Str) [error] -> Result[Str] {
  let header = output_header_name(output)?

  return f"""${prologue}

#include "${header}"

extern FILE *yyin;
extern int cur_lineno;
extern const char *cur_filename;

int yydebug;
int yynerrs;
YYSTYPE yylval;

static char *xsh_trim(char *s)
{
  while (*s && isspace((unsigned char)*s)) {
    s++;
  }

  char *end = s + strlen(s);
  while (end > s && isspace((unsigned char)end[-1])) {
    *--end = 0;
  }

  return s;
}

static bool xsh_starts_with(const char *s, const char *prefix)
{
  size_t n = strlen(prefix);
  return strncmp(s, prefix, n) == 0 && (s[n] == 0 || isspace((unsigned char)s[n]));
}

static char *xsh_next_word(char *s)
{
  s = xsh_trim(s);
  char *end = s;

  while (*end && !isspace((unsigned char)*end)) {
    end++;
  }

  *end = 0;
  return s;
}

static char *xsh_dup_prompt(char *s)
{
  char *start = strchr(s, '"');
  if (!start) {
    return NULL;
  }

  start++;
  char *end = strchr(start, '"');
  if (!end) {
    return NULL;
  }

  size_t n = (size_t)(end - start);
  char *out = malloc(n + 1);
  if (!out) {
    return NULL;
  }

  memcpy(out, start, n);
  out[n] = 0;
  return out;
}

static void xsh_parse_kconfig_stream(FILE *in);

static char *xsh_expand_vars(const char *s)
{
  size_t cap = strlen(s) + 1;
  char *out = malloc(cap);
  size_t len = 0;

  if (!out) {
    return NULL;
  }

  out[0] = 0;

  for (const char *p = s; *p; p++) {
    const char *piece = p;
    size_t piece_len = 1;
    char name[128];

    if (p[0] == '$' && p[1] == '(') {
      const char *end = strchr(p + 2, ')');
      if (end && (size_t)(end - (p + 2)) < sizeof(name)) {
        memcpy(name, p + 2, (size_t)(end - (p + 2)));
        name[end - (p + 2)] = 0;
        piece = getenv(name);
        if (!piece) {
          piece = "";
        }
        piece_len = strlen(piece);
        p = end;
      }
    }

    if (len + piece_len + 1 > cap) {
      while (len + piece_len + 1 > cap) {
        cap *= 2;
      }
      char *grown = realloc(out, cap);
      if (!grown) {
        free(out);
        return NULL;
      }
      out = grown;
    }

    memcpy(out + len, piece, piece_len);
    len += piece_len;
    out[len] = 0;
  }

  return out;
}

static char *xsh_split_if(char *s)
{
  for (char *p = s; *p; p++) {
    if (!isspace((unsigned char)*p)) {
      continue;
    }

    char *word = xsh_trim(p);
    if (strncmp(word, "if", 2) == 0 && (word[2] == 0 || isspace((unsigned char)word[2]))) {
      *p = 0;
      return xsh_trim(word + 2);
    }
  }

  return NULL;
}

static struct expr *xsh_expr_from_word(char *word)
{
  word = xsh_trim(word);
  char *name = xsh_next_word(word);

  if (strcmp(name, "y") == 0) {
    return expr_alloc_symbol(&symbol_yes);
  }
  if (strcmp(name, "m") == 0) {
    return expr_alloc_symbol(&symbol_mod);
  }
  if (strcmp(name, "n") == 0) {
    return expr_alloc_symbol(&symbol_no);
  }
  if (*name) {
    return expr_alloc_symbol(sym_lookup(name, 0));
  }

  return expr_alloc_symbol(&symbol_no);
}

static struct expr *xsh_expr_from_words(char *words)
{
  words = xsh_trim(words);
  struct expr *expr = NULL;
  enum expr_type op = E_AND;
  bool negate = false;

  while (*words) {
    words = xsh_trim(words);

    if (words[0] == '&' && words[1] == '&') {
      op = E_AND;
      words += 2;
      continue;
    }
    if (words[0] == '|' && words[1] == '|') {
      op = E_OR;
      words += 2;
      continue;
    }
    if (*words == '(' || *words == ')') {
      words++;
      continue;
    }
    if (*words == '!') {
      negate = !negate;
      words++;
      continue;
    }

    char *start = words;
    while (*words && !isspace((unsigned char)*words) && *words != '&' && *words != '|' && *words != ')') {
      words++;
    }
    char saved = *words;
    *words = 0;

    struct expr *term = xsh_expr_from_word(start);
    if (negate) {
      term = expr_alloc_one(E_NOT, term);
      negate = false;
    }

    if (!expr) {
      expr = term;
    } else if (op == E_OR) {
      expr = expr_alloc_or(expr, term);
    } else {
      expr = expr_alloc_and(expr, term);
    }

    if (!saved) {
      break;
    }
    *words = saved;
  }

  return expr ? expr : expr_alloc_symbol(&symbol_yes);
}

static void xsh_add_prompt_from_line(enum prop_type type, char *s)
{
  char *prompt = xsh_dup_prompt(s);
  if (prompt) {
    menu_add_prompt(type, prompt, NULL);
  }
}

static void xsh_add_default_from_line(char *s, int type)
{
  char *cond = xsh_split_if(s);
  struct expr *dep = cond ? xsh_expr_from_words(cond) : NULL;
  menu_add_expr(P_DEFAULT, xsh_expr_from_words(s), dep);
  if (type != S_UNKNOWN) {
    menu_set_type(type);
  }
}

static void xsh_parse_kconfig_stream(FILE *in)
{
  char line[4096];
  struct symbol *current = NULL;
  FILE *saved_yyin = yyin;
  bool skipping_help = false;

  yyin = in;

  while (fgets(line, sizeof(line), in)) {
    cur_lineno++;

    if (skipping_help) {
      if (line[0] == ' ' || line[0] == '	') {
        continue;
      }
      skipping_help = false;
    }

    char *s = xsh_trim(line);

    if (*s == 0 || *s == '#') {
      continue;
    }

    if (xsh_starts_with(s, "source")) {
      char *name = xsh_dup_prompt(s);
      if (name) {
        char *expanded = xsh_expand_vars(name);
        FILE *child = expanded ? zconf_fopen(expanded) : NULL;
        if (child) {
          xsh_parse_kconfig_stream(child);
          fclose(child);
        }
        free(expanded);
        free(name);
      }
      continue;
    }

    if (xsh_starts_with(s, "mainmenu")) {
      xsh_add_prompt_from_line(P_MENU, s);
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "menu")) {
      menu_add_entry(NULL, M_MENU);
      xsh_add_prompt_from_line(P_MENU, s);
      menu_add_menu();
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "endmenu")) {
      menu_end_menu();
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "if")) {
      menu_add_entry(NULL, M_IF);
      menu_add_dep(xsh_expr_from_words(s + strlen("if")), NULL);
      menu_add_menu();
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "endif")) {
      menu_end_menu();
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "comment")) {
      menu_add_entry(NULL, M_COMMENT);
      xsh_add_prompt_from_line(P_COMMENT, s);
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "choice")) {
      struct symbol *sym = sym_lookup(NULL, 0);
      menu_add_entry(sym, M_CHOICE);
      menu_set_type(S_BOOLEAN);
      INIT_LIST_HEAD(&current_entry->choice_members);
      menu_add_menu();
      current_choice = current_entry;
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "endchoice")) {
      current_choice = NULL;
      menu_end_menu();
      current = NULL;
      continue;
    }

    if (xsh_starts_with(s, "config")) {
      char *name = xsh_next_word(s + strlen("config"));
      current = sym_lookup(name, 0);
      menu_add_entry(current, M_NORMAL);
      continue;
    }

    if (xsh_starts_with(s, "menuconfig")) {
      char *name = xsh_next_word(s + strlen("menuconfig"));
      current = sym_lookup(name, 0);
      menu_add_entry(current, M_MENU);
      continue;
    }

    if (xsh_starts_with(s, "bool")) {
      menu_set_type(S_BOOLEAN);
      xsh_add_prompt_from_line(P_PROMPT, s);
      continue;
    }

    if (xsh_starts_with(s, "tristate")) {
      menu_set_type(S_TRISTATE);
      xsh_add_prompt_from_line(P_PROMPT, s);
      continue;
    }

    if (xsh_starts_with(s, "int")) {
      menu_set_type(S_INT);
      continue;
    }

    if (xsh_starts_with(s, "hex")) {
      menu_set_type(S_HEX);
      continue;
    }

    if (xsh_starts_with(s, "string")) {
      menu_set_type(S_STRING);
      xsh_add_prompt_from_line(P_PROMPT, s);
      continue;
    }

    if (xsh_starts_with(s, "prompt")) {
      xsh_add_prompt_from_line(P_PROMPT, s);
      continue;
    }

    if (xsh_starts_with(s, "depends on")) {
      char *cond = xsh_split_if(s + strlen("depends on"));
      menu_add_dep(xsh_expr_from_words(s + strlen("depends on")), cond ? xsh_expr_from_words(cond) : NULL);
      continue;
    }

    if (xsh_starts_with(s, "default")) {
      xsh_add_default_from_line(s + strlen("default"), S_UNKNOWN);
      continue;
    }

    if (xsh_starts_with(s, "def_bool")) {
      xsh_add_default_from_line(s + strlen("def_bool"), S_BOOLEAN);
      continue;
    }

    if (xsh_starts_with(s, "def_tristate")) {
      xsh_add_default_from_line(s + strlen("def_tristate"), S_TRISTATE);
      continue;
    }

    if (xsh_starts_with(s, "select")) {
      char *rest = s + strlen("select");
      char *cond = xsh_split_if(rest);
      char *name = xsh_next_word(rest);
      if (*name) {
        menu_add_symbol(P_SELECT, sym_lookup(name, 0), cond ? xsh_expr_from_words(cond) : NULL);
      }
      continue;
    }

    if (xsh_starts_with(s, "imply")) {
      char *rest = s + strlen("imply");
      char *cond = xsh_split_if(rest);
      char *name = xsh_next_word(rest);
      if (*name) {
        menu_add_symbol(P_IMPLY, sym_lookup(name, 0), cond ? xsh_expr_from_words(cond) : NULL);
      }
      continue;
    }

    if (xsh_starts_with(s, "range")) {
      char *rest = s + strlen("range");
      char *cond = xsh_split_if(rest);
      char *low = xsh_next_word(rest);
      char *high = xsh_next_word(rest + strlen(low) + 1);
      if (*low && *high) {
        menu_add_expr(P_RANGE, expr_alloc_comp(E_RANGE, sym_lookup(low, 0), sym_lookup(high, 0)), cond ? xsh_expr_from_words(cond) : NULL);
      }
      continue;
    }

    if (xsh_starts_with(s, "visible if")) {
      menu_add_visibility(xsh_expr_from_words(s + strlen("visible if")));
      continue;
    }

    if (xsh_starts_with(s, "option modules")) {
      modules_sym = current;
      continue;
    }

    if (xsh_starts_with(s, "help") || xsh_starts_with(s, "---help---")) {
      skipping_help = true;
      continue;
    }
  }

  yyin = saved_yyin;
}

int yyparse(void)
{
  xsh_parse_kconfig_stream(yyin);
  return yynerrs ? 1 : 0;
}

${epilogue}
"""
}

proc generate_dtc_stub_c(output: Str, decls: Str, prologue: Str, epilogue: Str) [error] -> Result[Str] {
  let header = output_header_name(output)?

  let location_global = if has_locations(decls) {
    """
YYLTYPE yylloc = { 1, 1, 1, 1 };
"""
  } else {
    ""
  }

  return f"""${prologue}

#include "${header}"

int yydebug;
int yynerrs;
YYSTYPE yylval;
${location_global}
extern FILE *yyin;

static char *xsh_trim(char *s)
{
  while (*s && isspace((unsigned char)*s)) {
    s++;
  }

  char *end = s + strlen(s);
  while (end > s && isspace((unsigned char)end[-1])) {
    *--end = 0;
  }

  return s;
}

static void xsh_strip_line_comment(char *s)
{
  char *comment = strstr(s, "//");
  if (comment) {
    *comment = 0;
  }
}

static bool xsh_starts_with(const char *s, const char *prefix)
{
  size_t n = strlen(prefix);
  return strncmp(s, prefix, n) == 0;
}

static struct data xsh_parse_dtc_value(char *value)
{
  value = xsh_trim(value);

  if (*value == '"') {
    struct data data = empty_data;
    char *p = value;

    while ((p = strchr(p, '"')) != NULL) {
      p++;
      char *end = strchr(p, '"');
      if (!end) {
        break;
      }

      data = data_merge(data, data_copy_escape_string(p, (int)(end - p)));
      p = end + 1;
    }

    return data;
  }

  if (*value == '<') {
    struct data data = empty_data;
    char *p = value + 1;

    while (*p && *p != '>') {
      while (*p && (isspace((unsigned char)*p) || *p == ',')) {
        p++;
      }
      if (!*p || *p == '>') {
        break;
      }

      char *end = p;
      unsigned long word = strtoul(p, &end, 0);
      if (end == p) {
        break;
      }

      data = data_append_cell(data, (cell_t)word);
      p = end;
    }

    return data;
  }

  if (*value == '[') {
    struct data data = empty_data;
    char *p = value + 1;

    while (*p && *p != ']') {
      while (*p && isspace((unsigned char)*p)) {
        p++;
      }
      if (!*p || *p == ']') {
        break;
      }

      char *end = p;
      unsigned long byte = strtoul(p, &end, 16);
      if (end == p) {
        break;
      }

      data = data_append_byte(data, (uint8_t)byte);
      p = end;
    }

    return data;
  }

  return empty_data;
}

static struct property *xsh_parse_dtc_property(char *s)
{
  char *semi = strchr(s, ';');
  if (!semi) {
    return NULL;
  }
  *semi = 0;

  char *eq = strchr(s, '=');
  if (!eq) {
    char *name = xsh_trim(s);
    return *name ? build_property(name, empty_data, NULL) : NULL;
  }

  *eq = 0;
  char *name = xsh_trim(s);
  char *value = xsh_trim(eq + 1);

  if (!*name) {
    return NULL;
  }

  return build_property(name, xsh_parse_dtc_value(value), NULL);
}

static char *xsh_dtc_node_name(char *s)
{
  char *brace = strchr(s, '{');
  if (!brace) {
    return NULL;
  }
  *brace = 0;

  char *name = xsh_trim(s);
  char *label = strchr(name, ':');
  if (label) {
    name = xsh_trim(label + 1);
  }

  if (*name == 0 || strcmp(name, "/") == 0) {
    return NULL;
  }

  return name;
}

int yyparse(void)
{
  char line[4096];
  struct node *root = name_node(build_node(NULL, NULL, NULL), "");
  struct node *stack[64];
  int depth = 0;

  stack[0] = root;

  while (fgets(line, sizeof(line), yyin)) {
    xsh_strip_line_comment(line);
    char *s = xsh_trim(line);

    if (*s == 0 || xsh_starts_with(s, "/dts-v1/") || xsh_starts_with(s, "/plugin/")) {
      continue;
    }

    if (strchr(s, '{')) {
      char *name = xsh_dtc_node_name(s);
      if (name && depth + 1 < (int)(sizeof(stack) / sizeof(stack[0]))) {
        struct node *child = name_node(build_node(NULL, NULL, NULL), name);
        add_child(stack[depth], child);
        depth++;
        stack[depth] = child;
      }
      continue;
    }

    if (strchr(s, '}')) {
      if (depth > 0) {
        depth--;
      }
      continue;
    }

    struct property *prop = xsh_parse_dtc_property(s);
    if (prop) {
      add_property(stack[depth], prop);
    }
  }

  parser_output = build_dt_info(DTSF_V1, NULL, root, guess_boot_cpuid(root));
  return 0;
}

${epilogue}
"""
}

proc generate_linux_stub_c(output: Str, decls: Str, prologue: Str, epilogue: Str) [error] -> Result[Str] {
  if is_kconfig_parser(decls) {
    return generate_kconfig_stub_c(output, prologue, epilogue)?
  }

  if is_dtc_parser(decls) {
    return generate_dtc_stub_c(output, decls, prologue, epilogue)?
  }

  let header = output_header_name(output)?

  let location_global = if has_locations(decls) {
    """
YYLTYPE yylloc = { 1, 1, 1, 1 };
"""
  } else {
    ""
  }

  return f"""${prologue}

#include "${header}"

int yydebug;
int yynerrs;
YYSTYPE yylval;
${location_global}
int yyparse(void)
{
  return 0;
}

${epilogue}
"""
}

proc index_of(names: List[Str], name: Str) [error] -> Int {
  var i = 0

  while i < names.len() {
    if names[i] == name {
      return i
    }

    i = i + 1
  }

  return -1
}

proc generate_int_array(name: Str, values: List[Str]) [error] -> Result[Str] {
  let body = if values.len() == 0 { "0" } else { values.join(", ") }
  return f"static const int ${name}[] = { ${body} };"
}

proc rule_lhs_values(rules: List[GrammarRule], names: List[Str]) [error] -> Result[List[Str]] {
  [f"${index_of(names, rule.lhs)}" for rule in rules]
}

proc rule_rhs_start_values(rules: List[GrammarRule]) [error] -> Result[List[Str]] {
  var values = []
  var offset = 0

  for rule in rules {
    values = values.push(f"${offset}")
    offset = offset + rule.rhs.len()
  }

  return values
}

proc rule_rhs_len_values(rules: List[GrammarRule]) [error] -> Result[List[Str]] {
  [f"${rule.rhs.len()}" for rule in rules]
}

proc rule_rhs_symbol_values(rules: List[GrammarRule], names: List[Str], tokens: Map[Int]) [error] -> Result[List[Str]] {
  var values = []

  for rule in rules {
    for item in rule.rhs {
      let nt = index_of(names, item)

      if nt >= 0 {
        values = values.push(f"${0 - nt - 1}")
      } else {
        values = values.push(token_code_expr(item, tokens))
      }
    }
  }

  return values
}

proc generate_rule_tables(rules: List[GrammarRule], names: List[Str], tokens: Map[Int]) [error] -> Result[Str] {
  let lhs = generate_int_array("yy_rule_lhs", rule_lhs_values(rules, names)?)?
  let rhs_start = generate_int_array("yy_rule_rhs_start", rule_rhs_start_values(rules)?)?
  let rhs_len = generate_int_array("yy_rule_rhs_len", rule_rhs_len_values(rules)?)?
  let rhs_symbols = generate_int_array("yy_rule_rhs_symbols", rule_rhs_symbol_values(rules, names, tokens)?)?

  return f"""${lhs}
${rhs_start}
${rhs_len}
${rhs_symbols}"""
}

proc generate_verbose_report(rules: List[GrammarRule], start: Str) [error] -> Result[Str] {
  var lines = ["Grammar", "", f"start: ${start}", "", "Rules"]
  var i = 0

  for rule in rules {
    let rhs = if rule.rhs.len() == 0 { "/* empty */" } else { rule.rhs.join(" ") }
    lines = lines.push(f"${i}: ${rule.lhs}: ${rhs}")
    i = i + 1
  }

  return lines.join("\n")
}

proc generate_c(
  tokens: Map[Int],
  rules: List[GrammarRule],
  start: Str,
  prologue: Str,
  epilogue: Str,
) [error] -> Result[Str] {
  let names = nonterminals(rules)?
  let defines = generate_token_defines(tokens)?
  let tables = generate_rule_tables(rules, names, tokens)?
  let start_id = index_of(names, start)

  if start_id < 0 {
    return Err(ToolError.Failed("yacc", f"unknown start symbol: ${start}"))
  }

  return f"""#include <stdio.h>
#include <stdlib.h>
${defines}

${prologue}

int yylex(void);
void yyerror(const char *message);

static int *yy_tokens;
static int yy_count;
static int yy_cap;

${tables}

#define YY_RULE_COUNT ${rules.len()}
#define YY_START_SYMBOL ${start_id}

struct yy_item {
  int rule;
  int dot;
  int start;
};

struct yy_set {
  struct yy_item *items;
  int count;
  int cap;
};

static int yy_add_item(struct yy_set *set, int rule, int dot, int start) {
  for (int i = 0; i < set->count; i++) {
    struct yy_item item = set->items[i];
    if (item.rule == rule && item.dot == dot && item.start == start) {
      return 1;
    }
  }

  if (set->count + 1 >= set->cap) {
    int next_cap = set->cap == 0 ? 32 : set->cap * 2;
    struct yy_item *next = realloc(set->items, sizeof(struct yy_item) * (size_t)next_cap);
    if (!next) {
      return 0;
    }
    set->items = next;
    set->cap = next_cap;
  }

  set->items[set->count].rule = rule;
  set->items[set->count].dot = dot;
  set->items[set->count].start = start;
  set->count++;
  return 1;
}

static int yy_push(int tok) {
  if (yy_count + 1 >= yy_cap) {
    int next_cap = yy_cap == 0 ? 64 : yy_cap * 2;
    int *next = realloc(yy_tokens, sizeof(int) * (size_t)next_cap);
    if (!next) {
      return 0;
    }
    yy_tokens = next;
    yy_cap = next_cap;
  }
  yy_tokens[yy_count++] = tok;
  return 1;
}

static int yy_rhs_symbol(int rule, int dot) {
  return yy_rule_rhs_symbols[yy_rule_rhs_start[rule] + dot];
}

static void yy_free_chart(struct yy_set *chart, int count) {
  if (!chart) {
    return;
  }

  for (int i = 0; i < count; i++) {
    free(chart[i].items);
  }
  free(chart);
}

static int yy_accepts(void) {
  int n = yy_count;
  struct yy_set *chart = calloc((size_t)n + 1, sizeof(struct yy_set));
  if (!chart) {
    return -1;
  }

  for (int rule = 0; rule < YY_RULE_COUNT; rule++) {
    if (yy_rule_lhs[rule] == YY_START_SYMBOL &&
        !yy_add_item(&chart[0], rule, 0, 0)) {
      yy_free_chart(chart, n + 1);
      return -1;
    }
  }

  for (int k = 0; k <= n; k++) {
    for (int i = 0; i < chart[k].count; i++) {
      struct yy_item item = chart[k].items[i];
      int len = yy_rule_rhs_len[item.rule];

      if (item.dot < len) {
        int sym = yy_rhs_symbol(item.rule, item.dot);

        if (sym < 0) {
          int nt = -sym - 1;

          for (int rule = 0; rule < YY_RULE_COUNT; rule++) {
            if (yy_rule_lhs[rule] == nt &&
                !yy_add_item(&chart[k], rule, 0, k)) {
              yy_free_chart(chart, n + 1);
              return -1;
            }
          }
        } else if (k < n && yy_tokens[k] == sym) {
          if (!yy_add_item(&chart[k + 1], item.rule, item.dot + 1, item.start)) {
            yy_free_chart(chart, n + 1);
            return -1;
          }
        }
      } else {
        int nt = yy_rule_lhs[item.rule];

        for (int j = 0; j < chart[item.start].count; j++) {
          struct yy_item origin = chart[item.start].items[j];

          if (origin.dot < yy_rule_rhs_len[origin.rule] &&
              yy_rhs_symbol(origin.rule, origin.dot) == -nt - 1 &&
              !yy_add_item(&chart[k], origin.rule, origin.dot + 1, origin.start)) {
            yy_free_chart(chart, n + 1);
            return -1;
          }
        }
      }
    }
  }

  for (int i = 0; i < chart[n].count; i++) {
    struct yy_item item = chart[n].items[i];
    if (item.start == 0 &&
        yy_rule_lhs[item.rule] == YY_START_SYMBOL &&
        item.dot == yy_rule_rhs_len[item.rule]) {
      yy_free_chart(chart, n + 1);
      return 1;
    }
  }

  yy_free_chart(chart, n + 1);
  return 0;
}

int yyparse(void) {
  int tok = yylex();
  while (tok != 0) {
    if (!yy_push(tok)) {
      yyerror("out of memory");
      return 2;
    }
    tok = yylex();
  }

  int accepted = yy_accepts();
  if (accepted < 0) {
    yyerror("out of memory");
    free(yy_tokens);
    yy_tokens = NULL;
    yy_count = 0;
    yy_cap = 0;
    return 2;
  }

  if (accepted) {
    free(yy_tokens);
    yy_tokens = NULL;
    yy_count = 0;
    yy_cap = 0;
    return 0;
  }

  yyerror("syntax error");
  free(yy_tokens);
  yy_tokens = NULL;
  yy_count = 0;
  yy_cap = 0;
  return 1;
}

void yyerror(const char *message) {
  fprintf(stderr, "%s\\n", message);
}

${epilogue}
"""
}

proc usage() [error, io] {
  io.write_stdout("""usage: bison.xsh [OPTIONS] FILE

Options:
  -d, --defines[=FILE]      write token header
  -o, --output FILE         write parser to FILE
  -b, --file-prefix PREFIX  use PREFIX for default outputs
  -p, --name-prefix PREFIX  accepted for yacc compatibility
  -l, -t, -v, -y            accepted for compatibility
  --debug, --verbose        accepted compatibility aliases
  --help                    show this help
  --version                 show version
""")?
}

proc parse_options(argv: List[Str]) [error, io] -> Result[YaccOptions] {
  var input = ""
  var output = "y.tab.c"
  var defines = false
  var defines_file = ""
  var verbose = false
  var prefix = "y"
  var output_set = false
  let tokens = cli.tokens(argv, ["output", "file-prefix", "name-prefix"])?

  for token in tokens {
    if token.kind == "operand" {
      input = token.value
      continue
    }

    if token.kind == "long" and token.name == "help" {
      usage()?
      abort(0)
    } else if token.kind == "long" and token.name == "version" {
      io.write_stdout("""bison.xsh 0.1
""")?
      abort(0)
    } else if token.name == "d" or token.name == "defines" {
      defines = true

      if token.value != "" {
        defines_file = token.value
      }
    } else if token.name == "o" or token.name == "output" {
      output = token.value
      output_set = true
    } else if token.name == "b" or token.name == "file-prefix" {
      prefix = token.value

      if ! output_set {
        output = f"${prefix}.tab.c"
      }
    } else if token.name == "p" or token.name == "name-prefix" {
      let _ = token.value
    } else if token.name == "l" or token.name == "t" or token.name == "y" or token.name == "debug" or token.name == "yacc" or token.name == "locations" {
      let _ = token.value
    } else if token.name == "v" or token.name == "verbose" {
      verbose = true
    } else {
      return Err(ToolError.Failed("usage", f"unsupported option: ${token.name}"))
    }
  }

  if input == "" {
    return Err(ToolError.Failed("usage", "missing grammar file"))
  }

  return {
    input,
    output,
    defines,
    defines_file,
    verbose,
    prefix,
  }
}

proc main(argv: List[Str] = []) [fs, process, env, error, io] {
  let opt = parse_options(argv)?
  let source = fs.read_text(fp"${opt.input}")?
  let parts = source.split("%%")

  if parts.len() < 2 {
    return Err(ToolError.Failed("yacc", "input must contain declarations and rules separated by %%"))
  }

  let decls = parts[0]
  let grammar = parts[1]
  let epilogue = if parts.len() >= 3 { parts[2] } else { "" }
  let unsupported = unsupported_declaration(decls)
  let tokens = parse_tokens(decls)?
  let prologue = extract_prologue(decls)?

  if unsupported != "" {
    if upstream_disabled() {
      fs.write(fp"${opt.output}", generate_linux_stub_c(opt.output, decls, prologue, epilogue)?)?

      if opt.defines {
        let header = if opt.defines_file != "" { opt.defines_file } else { opt.output.replace(".c", ".h") }
        fs.write(fp"${header}", generate_linux_header(decls, tokens)?)?
      }

      return
    }

    run_upstream_bison(argv, unsupported)?
    return
  }

  let rules = parse_rules(grammar)?
  let start = parse_start_symbol(decls, rules[0].lhs)
  let code = generate_c(tokens, rules, start, prologue, epilogue)?
  let out = fp"${opt.output}"
  fs.write(out, code)?

  if opt.defines {
    let header = if opt.defines_file != "" { opt.defines_file } else { opt.output.replace(".c", ".h") }
    fs.write(fp"${header}", generate_header(tokens)?)?
  }

  if opt.verbose {
    fs.write(fp"${opt.prefix}.output", generate_verbose_report(rules, start)?)?
  }
}

main(args)?
