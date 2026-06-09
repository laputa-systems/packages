#define _POSIX_C_SOURCE 200809L

#include <elf.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int read_file(const char *path, unsigned char **out, size_t *out_size) {
  FILE *file = fopen(path, "rb");
  if (!file) {
    return -1;
  }

  struct stat st;
  if (fstat(fileno(file), &st) != 0 || st.st_size < 0) {
    fclose(file);
    return -1;
  }

  size_t size = (size_t)st.st_size;
  unsigned char *data = malloc(size ? size : 1);
  if (!data) {
    fclose(file);
    return -1;
  }

  if (size > 0 && fread(data, 1, size, file) != size) {
    free(data);
    fclose(file);
    return -1;
  }

  fclose(file);
  *out = data;
  *out_size = size;
  return 0;
}

static int write_file(const char *path, const unsigned char *data, size_t size) {
  FILE *file = fopen(path, "wb");
  if (!file) {
    return -1;
  }

  if (size > 0 && fwrite(data, 1, size, file) != size) {
    fclose(file);
    return -1;
  }

  return fclose(file);
}

static int has_at(const unsigned char *data, size_t size, uint64_t off, const unsigned char *bytes, size_t len) {
  if (off > size || len > size - (size_t)off) {
    return 0;
  }

  return memcmp(data + off, bytes, len) == 0;
}

static int write_at(unsigned char *data, size_t size, uint64_t off, const unsigned char *bytes, size_t len) {
  if (off > size || len > size - (size_t)off) {
    return -1;
  }

  memcpy(data + off, bytes, len);
  return 0;
}

static const char *section_name(const unsigned char *names, size_t names_size, uint32_t off) {
  if (off >= names_size) {
    return "";
  }

  return (const char *)names + off;
}

static int patch_object(const char *path, long *patched_objects, long *patches) {
  unsigned char *data = NULL;
  size_t size = 0;
  if (read_file(path, &data, &size) != 0) {
    return 0;
  }

  if (size < sizeof(Elf64_Ehdr) || memcmp(data, ELFMAG, SELFMAG) != 0 || data[EI_CLASS] != ELFCLASS64 ||
      data[EI_DATA] != ELFDATA2LSB) {
    free(data);
    return 0;
  }

  Elf64_Ehdr *eh = (Elf64_Ehdr *)(void *)data;
  if (eh->e_shoff > size || eh->e_shentsize < sizeof(Elf64_Shdr) || eh->e_shnum == 0 ||
      (uint64_t)eh->e_shnum * eh->e_shentsize > size - eh->e_shoff || eh->e_shstrndx >= eh->e_shnum) {
    free(data);
    return -1;
  }

  Elf64_Shdr *sh = (Elf64_Shdr *)(void *)(data + eh->e_shoff);
  Elf64_Shdr *shstr = &sh[eh->e_shstrndx];
  if (shstr->sh_offset > size || shstr->sh_size > size - shstr->sh_offset) {
    free(data);
    return -1;
  }

  const unsigned char *shnames = data + shstr->sh_offset;
  size_t shnames_size = (size_t)shstr->sh_size;
  int jump_rela = -1;
  for (int i = 0; i < eh->e_shnum; i++) {
    if (sh[i].sh_type == SHT_RELA && strcmp(section_name(shnames, shnames_size, sh[i].sh_name), ".rela__jump_table") == 0) {
      jump_rela = i;
      break;
    }
  }

  if (jump_rela < 0) {
    free(data);
    return 0;
  }

  Elf64_Shdr *jr = &sh[jump_rela];
  if (jr->sh_entsize < sizeof(Elf64_Rela) || jr->sh_offset > size || jr->sh_size > size - jr->sh_offset ||
      jr->sh_link >= eh->e_shnum) {
    free(data);
    return -1;
  }

  Elf64_Shdr *symsec = &sh[jr->sh_link];
  if (symsec->sh_entsize < sizeof(Elf64_Sym) || symsec->sh_offset > size || symsec->sh_size > size - symsec->sh_offset) {
    free(data);
    return -1;
  }

  Elf64_Sym *syms = (Elf64_Sym *)(void *)(data + symsec->sh_offset);
  size_t sym_count = symsec->sh_size / symsec->sh_entsize;
  size_t rela_count = jr->sh_size / jr->sh_entsize;
  Elf64_Rela *rela = (Elf64_Rela *)(void *)(data + jr->sh_offset);
  int changed = 0;

  for (size_t i = 0; i < rela_count; i++) {
    if ((rela[i].r_offset % 16) != 8) {
      continue;
    }

    int64_t addend_mod = rela[i].r_addend % 4;
    if (addend_mod < 0) {
      addend_mod += 4;
    }

    if (addend_mod < 2) {
      continue;
    }

    Elf64_Rela *orig = NULL;
    uint64_t orig_off = rela[i].r_offset - 8;
    for (size_t j = 0; j < rela_count; j++) {
      if (rela[j].r_offset == orig_off) {
        orig = &rela[j];
        break;
      }
    }

    if (!orig) {
      fprintf(stderr, "%s: missing jump-table origin relocation\n", path);
      free(data);
      return -1;
    }

    uint32_t sym_index = ELF64_R_SYM(orig->r_info);
    if (sym_index >= sym_count) {
      free(data);
      return -1;
    }

    Elf64_Sym *sym = &syms[sym_index];
    if (sym->st_shndx == SHN_UNDEF || sym->st_shndx >= eh->e_shnum) {
      free(data);
      return -1;
    }

    Elf64_Shdr *text = &sh[sym->st_shndx];
    uint64_t insn_off = sym->st_value + (uint64_t)orig->r_addend;
    uint64_t file_off = text->sh_offset + insn_off;
    static const unsigned char nop5[5] = {0x0f, 0x1f, 0x44, 0x00, 0x00};
    static const unsigned char nop2[2] = {0x66, 0x90};

    if (file_off >= size) {
      free(data);
      return -1;
    }

    if (data[file_off] == 0xe9) {
      if (write_at(data, size, file_off, nop5, sizeof(nop5)) != 0) {
        free(data);
        return -1;
      }
      changed++;
    } else if (data[file_off] == 0xeb) {
      if (write_at(data, size, file_off, nop2, sizeof(nop2)) != 0) {
        free(data);
        return -1;
      }
      changed++;
    } else if (!has_at(data, size, file_off, nop5, sizeof(nop5)) && !has_at(data, size, file_off, nop2, sizeof(nop2))) {
      fprintf(stderr, "%s: unexpected jump-label opcode 0x%02x\n", path, data[file_off]);
      free(data);
      return -1;
    }

    for (int r = 0; r < eh->e_shnum; r++) {
      if (sh[r].sh_type != SHT_RELA || sh[r].sh_info != sym->st_shndx || sh[r].sh_entsize < sizeof(Elf64_Rela)) {
        continue;
      }

      if (sh[r].sh_offset > size || sh[r].sh_size > size - sh[r].sh_offset) {
        free(data);
        return -1;
      }

      size_t count = sh[r].sh_size / sh[r].sh_entsize;
      Elf64_Rela *relocs = (Elf64_Rela *)(void *)(data + sh[r].sh_offset);
      for (size_t ri = 0; ri < count; ri++) {
        if (relocs[ri].r_offset == insn_off) {
          relocs[ri].r_info = ELF64_R_INFO(ELF64_R_SYM(relocs[ri].r_info), 0);
        }
      }
    }
  }

  if (changed > 0) {
    if (write_file(path, data, size) != 0) {
      free(data);
      return -1;
    }
    (*patched_objects)++;
    *patches += changed;
  }

  free(data);
  return 0;
}

int main(int argc, char **argv) {
  long scanned = 0;
  long patched_objects = 0;
  long patches = 0;

  for (int i = 1; i < argc; i++) {
    if (patch_object(argv[i], &patched_objects, &patches) != 0) {
      return 2;
    }
    scanned++;
  }

  printf("xsh-kbuild-x86-jump-label-direct %ld objects %ld patched-objects %ld patches\n", scanned, patched_objects, patches);
  return 0;
}
