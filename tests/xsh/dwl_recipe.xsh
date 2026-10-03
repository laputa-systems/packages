##! Contract coverage for the minimal dwl keyboard configuration.
use repo.dwl-minimal.PKGBUILD as dwl_recipe

test test_dwl_minimal_removes_the_unavailable_menu_binding [fs, error] { |ctx|
  let upstream = """static const char *termcmd[] = { \"foot\", NULL };
static const char *menucmd[] = { \"wmenu-run\", NULL };
static const Key keys[] = {
  { MODKEY, XKB_KEY_p, spawn, {.v = menucmd} },
  { MODKEY, XKB_KEY_Return, spawn, {.v = termcmd} },
};
"""
  let configured = dwl_recipe.config_without_unavailable_menu(upstream)

  assert "menucmd" not in configured
  assert "termcmd" in configured
  assert "XKB_KEY_Return" in configured
}
