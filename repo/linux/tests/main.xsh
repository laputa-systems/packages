use kbuild

proc write_fixture(root: Path) [fs, error] {
  fs.mkdir(fp"${root}/init/lib")?
  fs.mkdir(fp"${root}/block")?
  fs.mkdir(fp"${root}/net")?
  fs.mkdir(fp"${root}/fs")?
  fs.mkdir(fp"${root}/fs/proc")?
  fs.mkdir(fp"${root}/fs/devpts")?
  fs.mkdir(fp"${root}/fs/ramfs")?
  fs.mkdir(fp"${root}/mm")?
  fs.mkdir(fp"${root}/arch/arm64/kernel")?

  fs.write(
    fp"${root}/.config",
    """CONFIG_BLOCK=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_HYPERV=m
CONFIG_MMU=y
CONFIG_UNIX98_PTYS=y
# CONFIG_UNUSED is not set
""",
  )?

  fs.write(
    fp"${root}/Kbuild",
    """core-y += arch/$(SRCARCH)/kernel/
obj-y += init/
obj-y += fs/ mm/
obj-y += core.o $(core-y)
helper_files = libhelper.o
lib-y += $(helper_files)
combo-y += combo-a.o combo-b.o
obj-y += combo.o
obj-$(CONFIG_BLOCK) += block/
obj-$(CONFIG_NET) += net/
obj-$(CONFIG_UNUSED) += unused/
obj-$(subst m,y,$(CONFIG_HYPERV)) += hyperv.o
ifeq ($(CONFIG_BLOCK),y)
obj-y += conditional.o
endif
ifeq ($(CONFIG_UNUSED),y)
obj-y += skipped.o
endif
""",
  )?

  fs.write(
    fp"${root}/Makefile",
    """obj-y += wrong-precedence.o
""",
  )?

  fs.write(
    fp"${root}/init/Kbuild",
    """obj-y += main.o \\
  lib/
""",
  )?

  fs.write(
    fp"${root}/init/lib/Makefile",
    """obj-y += helper.o
""",
  )?

  fs.write(
    fp"${root}/block/Kbuild",
    """obj-y := blk-core.o
""",
  )?

  fs.write(
    fp"${root}/net/Kbuild",
    """obj-$(CONFIG_INET) += ipv4.o
""",
  )?

  fs.write(
    fp"${root}/fs/Kbuild",
    """obj-y += proc/ devpts/ ramfs/
""",
  )?

  fs.write(
    fp"${root}/fs/devpts/Kbuild",
    """obj-$(CONFIG_UNIX98_PTYS) += devpts.o
devpts-$(CONFIG_UNIX98_PTYS) := inode.o
""",
  )?

  fs.write(
    fp"${root}/fs/proc/Makefile",
    """obj-y += proc.o
proc-y := nommu.o task_nommu.o
proc-$(CONFIG_MMU) := task_mmu.o
proc-y += inode.o
""",
  )?

  fs.write(
    fp"${root}/fs/ramfs/Kbuild",
    """obj-y += ramfs.o
file-mmu-y := file-nommu.o
file-mmu-$(CONFIG_MMU) := file-mmu.o
ramfs-objs += inode.o $(file-mmu-y)
""",
  )?

  fs.write(
    fp"${root}/mm/Kbuild",
    """obj-y += mm.o
mmu-y := nommu.o
mmu-$(CONFIG_MMU) := highmem.o memory.o
""",
  )?

  fs.write(
    fp"${root}/arch/arm64/kernel/Kbuild",
    """obj-y += head.o
""",
  )?
}

pure contains_path(paths: List[Path], target: Str) -> Bool {
  for path_value in paths {
    if path_value.display() == target {
      return true
    }
  }

  return false
}

pure composite_has_member(plan: kbuild.KbuildPlan, object: Str, member: Str) -> Bool {
  for composite in plan.composites {
    if composite.object.display() == object {
      return contains_path(composite.members, member)
    }
  }

  return false
}

proc test_kbuild_discovers_configured_obj_y_dirs_and_objects(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-kbuild")?
  write_fixture(root)?
  let config = kbuild.load_config(fp"${root}/.config")?
  let plan = kbuild.discover_plan(root, config, "arm64")?
  test.ok(contains_path(plan.dirs, "."))?
  test.ok(contains_path(plan.dirs, "init"))?
  test.ok(contains_path(plan.dirs, "init/lib"))?
  test.ok(contains_path(plan.dirs, "block"))?
  test.ok(contains_path(plan.dirs, "net"))?
  test.ok(contains_path(plan.dirs, "arch/arm64/kernel"))?
  test.eq(contains_path(plan.dirs, "unused"), false)?
  test.ok(contains_path(plan.objects, "core.o"))?
  test.eq(contains_path(plan.objects, "wrong-precedence.o"), false)?
  test.ok(contains_path(plan.lib_objects, "libhelper.o"))?
  test.ok(contains_path(plan.objects, "combo.o"))?
  test.eq(plan.composites.len(), 4)?
  test.eq(plan.composites[0].object.display(), "combo.o")?
  test.ok(contains_path(plan.composites[0].members, "combo-a.o"))?
  test.ok(contains_path(plan.composites[0].members, "combo-b.o"))?
  test.ok(contains_path(plan.objects, "hyperv.o"))?
  test.ok(contains_path(plan.objects, "conditional.o"))?
  test.eq(contains_path(plan.objects, "skipped.o"), false)?
  test.ok(contains_path(plan.objects, "init/main.o"))?
  test.ok(contains_path(plan.objects, "init/lib/helper.o"))?
  test.ok(contains_path(plan.objects, "block/blk-core.o"))?
  test.ok(contains_path(plan.objects, "net/ipv4.o"))?
  test.ok(contains_path(plan.objects, "arch/arm64/kernel/head.o"))?
  test.ok(contains_path(plan.objects, "fs/proc/proc.o"))?
  test.ok(contains_path(plan.objects, "fs/ramfs/ramfs.o"))?
  test.ok(contains_path(plan.objects, "mm/mm.o"))?
  test.eq(contains_path(plan.objects, "fs/proc/nommu.o"), false)?
  test.eq(contains_path(plan.objects, "fs/proc/task_nommu.o"), false)?
  test.eq(contains_path(plan.objects, "fs/ramfs/file-nommu.o"), false)?
  test.eq(contains_path(plan.objects, "mm/nommu.o"), false)?
  test.ok(composite_has_member(plan, "fs/proc/proc.o", "fs/proc/task_mmu.o"))?
  test.ok(composite_has_member(plan, "fs/ramfs/ramfs.o", "fs/ramfs/file-mmu.o"))?
  test.ok(composite_has_member(plan, "fs/devpts/devpts.o", "fs/devpts/inode.o"))?
  test.eq(plan.unsupported.len(), 0)?
}

proc test_kbuild_local_record_graph_matches_default(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-kbuild-local-records")?
  let default_out = test.temp_path(ctx, name: "linux-kbuild-default-plan")
  let local_out = test.temp_path(ctx, name: "linux-kbuild-local-plan")
  write_fixture(root)?
  let config = kbuild.load_config(fp"${root}/.config")?
  let default_plan = kbuild.discover_plan(root, config, "arm64")?
  let local_plan = kbuild.discover_plan_with_options(
    root,
    config,
    "arm64",
    {
      progress: false,
      progress_every: 100,
      jobs: 1,
      local_records: true,
      local_record_cache: false,
      build_plan: true,
    },
  )?
  kbuild.write_discovered_plan(default_plan, default_out)?
  kbuild.write_discovered_plan(local_plan, local_out)?
  test.eq(default_out.read_text()?, local_out.read_text()?)?
}

proc test_kbuild_local_record_cache_reuses_and_invalidates(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-kbuild-local-cache")?
  write_fixture(root)?
  let config = kbuild.load_config(fp"${root}/.config")?
  let options = {
    progress: false,
    progress_every: 100,
    jobs: 1,
    local_records: true,
    local_record_cache: true,
    build_plan: true,
  }
  let first = kbuild.discover_plan_with_options(root, config, "arm64", options)?
  let second = kbuild.discover_plan_with_options(root, config, "arm64", options)?
  test.eq(first.objects.len(), second.objects.len())?

  let root_kbuild = fp"${root}/Kbuild"
  let original = root_kbuild.read_text()?
  fs.write(
    root_kbuild,
    f"""${original}obj-y += cached.o
""",
  )?
  let third = kbuild.discover_plan_with_options(root, config, "arm64", options)?
  test.ok(contains_path(third.objects, "cached.o"))?
}

proc test_kbuild_writes_text_plan(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-kbuild-text")?
  let out = test.temp_path(ctx, name: "plan.json")
  write_fixture(root)?
  let plan = kbuild.write_plan(root, fp"${root}/.config", out, "arm64")?
  let stored = out.read_text()?
  test.ok("obj\tinit/main.o" in stored)?
  let loaded = kbuild.read_discovered_plan(out)?
  test.eq(loaded.objects.len(), plan.objects.len())?
  test.ok(contains_path(loaded.objects, "init/main.o"))?
}

proc test_kbuild_constructs_builtin_archive_tasks(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-archive-tasks")?
  write_fixture(root)?

  fs.write(
    fp"${root}/core.c",
    """int core(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/libhelper.c",
    """int libhelper(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/hyperv.c",
    """int hyperv(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/conditional.c",
    """int conditional(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/combo-a.c",
    """int combo_a(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/combo-b.c",
    """int combo_b(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/init/main.c",
    """int init_main(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/init/lib/helper.S",
    """.text
""",
  )?

  fs.write(
    fp"${root}/block/blk-core.c",
    """int blk_core(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/net/ipv4.c",
    """int ipv4(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/arch/arm64/kernel/head.S",
    """.text
""",
  )?

  let config = kbuild.load_config(fp"${root}/.config")?
  let plan = kbuild.discover_plan(root, config, "arm64")?

  cd root {
    let archive_plan = kbuild.plan_builtin_archives(
      plan,
      /usr/bin/cc,
      "aarch64-linux-gnu",
      ["-D__KERNEL__", "-O2", "-mgeneral-regs-only", "-mbranch-protection=pac-ret"],
      [],
      [
        "-Iinclude",
        "-nostdinc",
        "-include",
        "include/linux/compiler-version.h",
        "-include",
        "include/linux/kconfig.h",
        "-include",
        "include/generated/utsversion.h",
        "-include",
        "include/linux/compiler_types.h",
      ],
    )?

    test.eq(archive_plan.missing_sources.len(), 0)?
    test.eq(archive_plan.generated_objects.len(), 0)?
    test.eq(archive_plan.tasks.len(), 18)?
    test.ok(contains_path(archive_plan.archives, ".xsh-kbuild/built-in.a"))?
    test.ok(contains_path(archive_plan.archives, ".xsh-kbuild/lib.a"))?
    test.ok(contains_path(archive_plan.archives, ".xsh-kbuild/init/built-in.a"))?
    test.ok(contains_path(archive_plan.archives, ".xsh-kbuild/init/lib/built-in.a"))?
    let report = fp"${root}/archive-plan.json"
    kbuild.write_archive_plan_report(archive_plan, report)?
    let stored: Record = json.read(report)?
    let task_count: Int = stored.get("task_count")?
    let tasks: List[Record] = stored.get("tasks")?
    test.eq(task_count, archive_plan.tasks.len())?
    test.eq(tasks.len(), archive_plan.tasks.len())?
    let first = tasks[0]
    let argv: List[Str] = first.get("argv")?
    let outputs: List[Str] = first.get("outputs")?
    test.ok(argv.len() > 0)?
    test.ok(outputs.len() > 0)?
    let asm_task = tasks[7]
    let asm_argv: List[Str] = asm_task.get("argv")?
    test.ok("-D__ASSEMBLY__" in asm_argv)?
    test.ok("-fno-PIE" in asm_argv)?
    test.ok("-DKASAN_SHADOW_SCALE_SHIFT=" in asm_argv)?
    test.ok("-nostdinc" in asm_argv)?
    test.ok("include/linux/compiler-version.h" in asm_argv)?
    test.ok("include/linux/kconfig.h" in asm_argv)?
    test.eq("-O2" in asm_argv, false)?
    test.eq("-mgeneral-regs-only" in asm_argv, false)?
    test.eq("-mbranch-protection=pac-ret" in asm_argv, false)?
    test.eq("include/generated/utsversion.h" in asm_argv, false)?
    test.eq("include/linux/compiler_types.h" in asm_argv, false)?
  } ?
}

proc test_kbuild_plans_pi_relacheck_after_objcopy(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-pi-relacheck")?
  fs.mkdir(fp"${root}/arch/arm64/kernel/pi")?
  fs.write(fp"${root}/.config", "")?

  fs.write(
    fp"${root}/Kbuild",
    """obj-y += arch/arm64/kernel/pi/
""",
  )?

  fs.write(
    fp"${root}/arch/arm64/kernel/pi/Makefile",
    """obj-y += idreg-override.pi.o
""",
  )?

  fs.write(
    fp"${root}/arch/arm64/kernel/pi/idreg-override.c",
    """int idreg_override;
""",
  )?

  fs.write(
    fp"${root}/arch/arm64/kernel/pi/relacheck.c",
    """int main(int argc, char **argv) { return argc < 3; }
""",
  )?

  cd root {
    let config = kbuild.load_config(p".config")?
    let plan = kbuild.discover_plan(p".", config, "arm64")?

    let archive_plan = kbuild.plan_builtin_archives(
      plan,
      /usr/bin/cc,
      "aarch64-linux-gnu",
      ["-fno-function-sections", "-fno-data-sections"],
      [],
      [],
    )?

    let relacheck = ".xsh-kbuild/host/arch/arm64/kernel/pi/relacheck"
    let pi_object = p".xsh-kbuild/obj/arch/arm64/kernel/pi/idreg-override.pi.o"
    let relacheck_task_name = f"${pi_object.display()}:relacheck"
    var saw_build_task = false
    var saw_check_task = false
    var saw_archive_dep = false

    for task in archive_plan.tasks {
      if task.name == relacheck {
        saw_build_task = true
      }

      if task.name == relacheck_task_name {
        saw_check_task = true
        test.ok(relacheck in task.argv)?
        test.ok(pi_object.display() in task.argv)?
        test.ok(fp"${pi_object}.relacheck.cmd" in task.outputs)?
        test.ok(pi_object.display() in task.deps)?
        test.ok(relacheck in task.deps)?
      }

      if task.name == ".xsh-kbuild/arch/arm64/kernel/pi/built-in.a" {
        saw_archive_dep = relacheck_task_name in task.deps
      }
    }

    test.ok(saw_build_task)?
    test.ok(saw_check_task)?
    test.ok(saw_archive_dep)?
  } ?
}

proc test_kbuild_runs_archive_plan_output_from_json(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "linux-archive-runner")?
  let first = fp"${root}/first.txt"
  let second = fp"${root}/second.txt"
  let plan = fp"${root}/archive-plan.json"
  let no_strings: List[Str] = []

  json.write(
    plan,
    {
      archives: no_strings,
      generated_objects: no_strings,
      missing_sources: no_strings,
      task_count: 2,
      tasks: [
        {
          name: "first",
          outputs: [
            first.display(),
          ],
          inputs: no_strings,
          deps: no_strings,
          argv: [
            "/bin/sh",
            "-c",
            f"printf first > ${first.display()}",
          ],
          env: {},
          cwd: root.display(),
          depfile: "",
          stamp: fp"${root}/first.cmd".display(),
        },
        {
          name: "second",
          outputs: [
            second.display(),
          ],
          inputs: [
            first.display(),
          ],
          deps: [
            "first",
          ],
          argv: [
            "/bin/sh",
            "-c",
            f"cat ${first.display()} > ${second.display()}; printf second >> ${second.display()}",
          ],
          env: {},
          cwd: root.display(),
          depfile: "",
          stamp: fp"${root}/second.cmd".display(),
        },
      ],
    },
  )?

  kbuild.run_archive_plan_output(plan, second, 1)?
  test.eq(first.read_text()?, "first")?
  test.eq(second.read_text()?, "firstsecond")?
}

proc test_kbuild_reports_missing_builtin_archive_sources(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-archive-missing")?

  fs.write(
    fp"${root}/present.c",
    """int present(void) { return 0; }
""",
  )?

  let plan: kbuild.KbuildPlan = {
    dirs: [
      p".",
    ],
    objects: [
      p"present.o",
      p"missing.o",
    ],
    lib_objects: [],
    archive_owners: [],
    composites: [],
    unsupported: [],
  }

  cd root {
    let archive_plan = kbuild.plan_builtin_archives(plan, /usr/bin/cc, "aarch64-linux-gnu", [], [], [])?
    test.eq(archive_plan.missing_sources.len(), 1)?
    test.eq(archive_plan.generated_objects.len(), 0)?
    test.ok(contains_path(archive_plan.missing_sources, "missing.o"))?
    test.eq(archive_plan.archives.len(), 1)?
  } ?
}

proc test_kbuild_archive_analysis_preserves_item_order(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-archive-analysis")?
  fs.write(
    fp"${root}/first.c",
    """int first(void) { return 0; }
""",
  )?
  fs.write(
    fp"${root}/second.c",
    """int second(void) { return 0; }
""",
  )?

  cd root {
    let results = kbuild.analyze_archive_items(
      [
        {
          object: "first.o",
          owner: ".",
          library: false,
          pi: false,
          composite: "",
          members: [],
          flags: [
            "-DFIRST",
          ],
        },
        {
          object: "second.o",
          owner: "lib",
          library: true,
          pi: false,
          composite: "",
          members: [],
          flags: [
            "-DSECOND",
          ],
        },
      ],
    )?
    test.eq(results.len(), 2)?
    test.eq(results[0].get("object")?, "first.o")?
    test.eq(results[1].get("object")?, "second.o")?

    let first_tasks: List[Record] = results[0].get("tasks")?
    let second_tasks: List[Record] = results[1].get("tasks")?
    test.eq(first_tasks[0].get("source")?, "first.c")?
    test.eq(second_tasks[0].get("source")?, "second.c")?
    test.eq(first_tasks[0].get("flags")?, ["-DFIRST"])?
    test.eq(second_tasks[0].get("flags")?, ["-DSECOND"])?
  } ?
}

proc test_kbuild_parallel_archive_analysis_matches_serial(ctx: TestContext) [fs, process, env, time, error] {
  let root = test.temp_dir(ctx, name: "linux-archive-analysis-pool")?
  let worker = path.absolute(p"kbuild-archive-analysis-worker.xsh")?
  let xsh_bin = process.which("xsh")?
  fs.write(fp"${root}/.config", "")?
  fs.write(fp"${root}/Kbuild", "")?
  fs.write(
    fp"${root}/first.c",
    """int first(void) { return 0; }
""",
  )?
  fs.write(
    fp"${root}/second.c",
    """int second(void) { return 0; }
""",
  )?

  let plan: kbuild.KbuildPlan = {
    dirs: [
      p".",
    ],
    objects: [
      p"first.o",
      p"second.o",
    ],
    lib_objects: [],
    archive_owners: [
      {
        object: p"first.o",
        dir: p".",
      },
      {
        object: p"second.o",
        dir: p".",
      },
    ],
    composites: [],
    unsupported: [],
  }

  cd root {
    let serial = kbuild.plan_builtin_archives(plan, /usr/bin/cc, "aarch64-linux-gnu", [], [], [])?
    let parallel = kbuild.plan_builtin_archives_with_analysis_workers(
      plan,
      /usr/bin/cc,
      "aarch64-linux-gnu",
      [],
      [],
      [],
      2,
      xsh_bin,
      worker,
    )?
    test.eq(parallel.archives, serial.archives)?
    test.eq(parallel.link_inputs, serial.link_inputs)?
    test.eq(parallel.generated_objects, serial.generated_objects)?
    test.eq(parallel.missing_sources, serial.missing_sources)?
    test.eq(parallel.tasks.len(), serial.tasks.len())?

    for index in range(serial.tasks.len()) {
      test.eq(parallel.tasks[index].name, serial.tasks[index].name)?
      test.eq(
        [
          f"${arg}"
          for arg in parallel.tasks[index].argv
        ],
        [
          f"${arg}"
          for arg in serial.tasks[index].argv
        ],
      )?
      test.eq(parallel.tasks[index].deps, serial.tasks[index].deps)?
    }
  } ?
}

proc test_kbuild_adds_x86_kvm_local_include(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-x86-kvm-include")?
  fs.mkdir(fp"${root}/arch/x86/kvm/mmu")?

  fs.write(
    fp"${root}/arch/x86/kvm/mmu/mmu.c",
    """#include "irq.h"
int mmu(void) { return 0; }
""",
  )?

  let plan: kbuild.KbuildPlan = {
    dirs: [
      p"arch/x86/kvm",
    ],
    objects: [
      p"arch/x86/kvm/kvm.o",
    ],
    lib_objects: [],
    archive_owners: [],
    composites: [
      {
        object: p"arch/x86/kvm/kvm.o",
        members: [
          p"arch/x86/kvm/mmu/mmu.o",
        ],
      },
    ],
    unsupported: [],
  }

  cd root {
    let archive_plan = kbuild.plan_builtin_archives(plan, /usr/bin/cc, "x86_64-linux-gnu", [], [], [])?
    var saw_mmu = false

    for task in archive_plan.tasks {
      if task.name == ".xsh-kbuild/obj/arch/x86/kvm/mmu/mmu.o" {
        saw_mmu = true
        test.ok("-I./arch/x86/kvm" in task.argv)?
      }
    }

    test.ok(saw_mmu)?
  } ?
}

proc test_kbuild_applies_object_and_subdir_cflags(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-cflags")?
  fs.mkdir(fp"${root}/sound/hda/common")?
  fs.mkdir(fp"${root}/sound/hda/controllers")?
  fs.write(fp"${root}/.config", "")?

  fs.write(
    fp"${root}/sound/hda/common/Makefile",
    """CFLAGS_controller.o := -I$(src)
""",
  )?

  fs.write(
    fp"${root}/sound/hda/controllers/Makefile",
    """subdir-ccflags-y += -I$(src)/../common
CFLAGS_intel.o := -I$(src)
""",
  )?

  fs.write(
    fp"${root}/sound/hda/common/controller.c",
    """int controller(void) { return 0; }
""",
  )?

  fs.write(
    fp"${root}/sound/hda/controllers/intel.c",
    """int intel(void) { return 0; }
""",
  )?

  let plan: kbuild.KbuildPlan = {
    dirs: [
      p"sound/hda/common",
      p"sound/hda/controllers",
    ],
    objects: [
      p"sound/hda/common/controller.o",
      p"sound/hda/controllers/intel.o",
    ],
    lib_objects: [],
    archive_owners: [],
    composites: [],
    unsupported: [],
  }

  cd root {
    let archive_plan = kbuild.plan_builtin_archives(plan, /usr/bin/cc, "x86_64-linux-gnu", [], [], [])?
    var saw_controller = false
    var saw_intel = false

    for task in archive_plan.tasks {
      if task.name == ".xsh-kbuild/obj/sound/hda/common/controller.o" {
        saw_controller = true
        test.ok("-I./sound/hda/common" in task.argv)?
      }

      if task.name == ".xsh-kbuild/obj/sound/hda/controllers/intel.o" {
        saw_intel = true
        test.ok("-I./sound/hda/controllers" in task.argv)?
        test.ok("-I./sound/hda/controllers/../common" in task.argv)?
      }
    }

    test.ok(saw_controller)?
    test.ok(saw_intel)?
  } ?
}

proc test_kbuild_generates_config_headers(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-config-headers")?
  let config = fp"${root}/.config"

  fs.write(
    config,
    """CONFIG_ALPHA=y
CONFIG_NUMBER=12
CONFIG_TEXT="value"
""",
  )?

  kbuild.write_config_headers(config, root, "7.0.5", "arm64")?
  let autoconf = fp"${root}/include/generated/autoconf.h".read_text()?
  let auto_conf = fp"${root}/include/config/auto.conf".read_text()?
  test.contains(autoconf, "#define CONFIG_ALPHA 1")?
  test.contains(autoconf, "#define CONFIG_NUMBER 12")?
  test.contains(autoconf, "#define CONFIG_TEXT \"value\"")?
  test.contains(auto_conf, "CONFIG_ALPHA=y")?
  test.contains(auto_conf, "CONFIG_NUMBER=12")?
}

proc test_kbuild_generates_syscall_table(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-syscalls")?
  let table = fp"${root}/syscall.tbl"
  let out = fp"${root}/syscall_table.h"
  let numbers = fp"${root}/unistd.h"

  fs.write(
    table,
    """0 common read sys_read
2 common open sys_open compat_sys_open
3 64 exit sys_exit - noreturn
4 32 skip32 sys_skip32
""",
  )?

  kbuild.generate_syscall_table(table, out, ["common", "64"])?

  test.eq(
    out.read_text()?,
    """__SYSCALL(0, sys_read)
__SYSCALL(1, sys_ni_syscall)
__SYSCALL_WITH_COMPAT(2, sys_open, compat_sys_open)
__SYSCALL_NORETURN(3, sys_exit)
""",
  )?

  kbuild.generate_syscall_numbers(table, numbers, "_ASM_UNISTD_H", "__NR_syscalls", "", ["common", "64"])?
  test.contains(numbers.read_text()?, "#define __NR_read 0")?
  test.contains(numbers.read_text()?, "#define __NR_exit 3")?
  test.contains(numbers.read_text()?, "#define __NR_syscalls 4")?
}

proc test_kbuild_generates_offsets_header(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "linux-offsets")?
  let asm_path = fp"${root}/asm-offsets.s"
  let out = fp"${root}/include/generated/asm-offsets.h"

  fs.write(
    asm_path,
    """.ascii "->FOO 8 offsetof(struct demo, foo)"
.ascii "->"
.ascii "->BAR 16 sizeof(struct demo)"
""",
  )?

  kbuild.generate_offsets_header(asm_path, out, "__ASM_OFFSETS_H__")?

  test.eq(
    out.read_text()?,
    """#ifndef __ASM_OFFSETS_H__
#define __ASM_OFFSETS_H__
/*
 * DO NOT MODIFY.
 *
 * This file was generated by Kbuild
 */

#define FOO 8 /* offsetof(struct demo, foo) */

#define BAR 16 /* sizeof(struct demo) */

#endif
""",
  )?
}

proc test_kbuild_models_final_link_tasks(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-link-tasks")?
  let ar = /usr/bin/ar
  let ld = /usr/bin/ld
  let objcopy = /usr/bin/objcopy
  let built_in = fp"${root}/built-in.a"
  let arch_lib = fp"${root}/arch/arm64/lib/lib.a"
  let efi_lib = fp"${root}/drivers/firmware/efi/libstub/lib.a"
  let vmlinux_a = fp"${root}/vmlinux.a"
  let vmlinux_o = fp"${root}/vmlinux.o"
  let script = fp"${root}/arch/arm64/kernel/vmlinux.lds"
  let export_obj = fp"${root}/.vmlinux.export.o"
  let version_obj = fp"${root}/init/version-timestamp.o"
  let unstripped = fp"${root}/vmlinux.unstripped"
  let vmlinux = fp"${root}/vmlinux"
  let image = fp"${root}/arch/arm64/boot/Image"
  let archive_task = kbuild.vmlinux_archive_task(ar, [built_in, arch_lib], vmlinux_a)
  test.eq(archive_task.argv, ["/usr/bin/ar", "cDPrST", vmlinux_a.display(), built_in.display(), arch_lib.display()])?
  let reloc = kbuild.vmlinux_o_task(ld, ["-EL", "-maarch64elf"], vmlinux_a, [efi_lib], vmlinux_o)
  test.ok("--whole-archive" in reloc.argv)?
  test.ok("--start-group" in reloc.argv)?
  test.ok(efi_lib in reloc.inputs)?

  let linked = kbuild.vmlinux_unstripped_task(
    ld,
    ["-EL", "-maarch64elf"],
    ["--no-undefined", "-X", "--pic-veneer"],
    script,
    vmlinux_a,
    [efi_lib],
    export_obj,
    version_obj,
    unstripped,
  )

  test.ok("--script" in linked.argv)?
  test.ok(version_obj in linked.inputs)?
  let stripped = kbuild.vmlinux_strip_task(objcopy, unstripped, vmlinux)
  test.ok("--remove-section=.modinfo" in stripped.argv)?
  let image_task = kbuild.image_task(objcopy, vmlinux, image)
  test.eq(image_task.argv.get(1)?, "-O")?
  test.eq(image_task.argv.get(2)?, "binary")?
  let llvm_image_task = kbuild.image_argv_task(["llvm-objcopy"], vmlinux, image)
  test.eq(llvm_image_task.argv.get(0)?, "llvm-objcopy")?
  let nonrel_config: kbuild.Kconfig = {enabled: map.empty(), values: map.empty().set("RELR", "y")}
  let nonrel_flags = kbuild.arm64_vmlinux_ldflags(nonrel_config)
  test.eq("-shared" in nonrel_flags, false)?
  test.ok("--pack-dyn-relocs=relr" in nonrel_flags)?
  let rel_config: kbuild.Kconfig = {enabled: map.empty(), values: map.empty().set("RELOCATABLE", "y").set("RELR", "y")}
  let rel_flags = kbuild.arm64_vmlinux_ldflags(rel_config)
  test.ok("-shared" in rel_flags)?
  test.ok("--no-apply-dynamic-relocs" in rel_flags)?
}
