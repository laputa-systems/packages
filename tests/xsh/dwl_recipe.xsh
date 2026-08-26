##! Contract coverage for the minimal dwl keyboard configuration.
use repo.dwl-minimal.PKGBUILD as dwl_recipe

proc test_dwl_minimal_removes_the_unavailable_menu_binding(ctx: TestContext) [fs, error] {
  let upstream = """static const char *termcmd[] = { \"foot\", NULL };
static const char *menucmd[] = { \"wmenu-run\", NULL };
static const Key keys[] = {
  { MODKEY, XKB_KEY_p, spawn, {.v = menucmd} },
  { MODKEY, XKB_KEY_Return, spawn, {.v = termcmd} },
};
"""
  let configured = dwl_recipe.config_without_unavailable_menu(upstream)

  test.eq(configured.contains("menucmd"), false)?
  test.ok(configured.contains("termcmd"))?
  test.ok(configured.contains("XKB_KEY_Return"))?
}
