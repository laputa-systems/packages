// Shadow asm/alternative.h for clang integrated assembler.
// Includes the real alternative.h (via search-path bypass) to get all
// transitive deps, then stubs out the ALTERNATIVE macros that embed
// forward references in .skip directives which clang cannot handle.
//
// Placed at arch/x86/include/generated/asm/alternative.h which is found
// first via -I priority.  It pulls in the real arch/x86/include/asm/*
// headers and then makes the problematic macros no-ops.

#ifndef _ASM_X86_ALTERNATIVE_H
#define _ASM_X86_ALTERNATIVE_H

#ifdef __ALTERNATIVE_STUBS_APPLIED__
// Already applied via the real alternative.h — do nothing.
#else
#define __ALTERNATIVE_STUBS_APPLIED__

// Pull in the real alternative.h first (must use relative path that
// bypasses the -I priority and reaches arch/x86/include/asm/).
#include "../../asm/alternative.h"

// Now override the problematic C macros.  Keep the original semantics
// (just the oldinstr) but strip the .pushsection/.popsection and .skip.

#undef ALTERNATIVE
#define ALTERNATIVE(oldinstr, newinstr, feature) \
	oldinstr "\n"

#undef ALTERNATIVE_2
#define ALTERNATIVE_2(oldinstr, newinstr1, f1, newinstr2, f2) \
	oldinstr "\n"

#undef ALTERNATIVE_3
#define ALTERNATIVE_3(oldinstr, newinstr1, f1, newinstr2, f2, newinstr3, f3) \
	oldinstr "\n"

#undef ALTERNATIVE_TERNARY
#define ALTERNATIVE_TERNARY(oldinstr, feature, newinstr_yes, newinstr_no) ({ \
	asm goto(oldinstr "\n" :::: t_yes, t_no); \
t_yes: return true; t_no: return false; \
})

#undef alternative
#define alternative(oldinstr, newinstr, ft_flags) \
	oldinstr "\n"

#undef alternative_io
#define alternative_io(oldinstr, newinstr, ft_flags, output, input...) \
	oldinstr "\n"

#undef alternative_input
#define alternative_input(oldinstr, newinstr, ft_flags, input...) \
	oldinstr "\n"

// Assembly stubs
#ifdef __ASSEMBLER__
.purgem ALTERNATIVE
.purgem ALTERNATIVE_2
.purgem ALTERNATIVE_3
.purgem ALTERNATIVE_TERNARY

.macro ALTERNATIVE oldinstr, newinstr, feature
	\oldinstr
.endm

.macro ALTERNATIVE_2 oldinstr, newinstr1, f1, newinstr2, f2
	\oldinstr
.endm

.macro ALTERNATIVE_3 oldinstr, newinstr1, f1, newinstr2, f2, newinstr3, f3
	\oldinstr
.endm

.macro ALTERNATIVE_TERNARY default, feature, alt0, alt1
	\default
.endm
#endif /* __ASSEMBLER__ */

#endif /* __ALTERNATIVE_STUBS_APPLIED__ */
#endif /* _ASM_X86_ALTERNATIVE_H */
