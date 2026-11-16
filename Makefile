# Makefile — the bootstrap and the oracles it has to reproduce.
#
# Nothing here compiles. There is no compiler, no system assembler and no
# interpreter in this project: every rule runs one of the two hand-built
# assemblers and compares BYTES with cmp.
#
# The comparison is the point. A rule that only checked an exit status would
# pass on an assembler that emitted garbage and returned 0, and would pass
# hardest when the assembler was missing entirely.
.DEFAULT_GOAL := all
ASM0A := ./asm0a
ASM1  := ./asm1
SEED  := seed/asm1
DIS   := ./dis
CC    := ./cc
# src/<name>.s assembles to ref/<name>
PAIRS := addr32 callret cmp32 cmp8 count10 dbnum inc8 jmp jz load loop movrr \
         r8 rel32 stack store
# src/hello_num.s assembles to the hand-written ref/hello
HELLO := hello_num
# no oracle: the program's exit status is the assertion
BEHAVE := exit42:42
TOTAL := $(words $(PAIRS) $(HELLO) $(BEHAVE))
.PHONY: all bootstrap asm1 dis cc hello test test-asm0a test-asm1 test-dis test-cc test-tools test-coverage test-reject test-reject-msg test-msg-exact test-capability test-superior fixpoint bootstrap-check triage promote demo record verify-provenance which check clean help
help:
	@echo 'make            build asm1 from seed/asm1, then the decoder (which needs it)'
	@echo 'make dis        build the branch decoder (src/dis.s) with asm1'
	@echo 'make test       assemble every fixture with both assemblers, compare to ref/'
	@echo 'make test-reject  sources that must be refused, with no output'
	@echo 'make test-dis   decode cases: hand-written expectations, positive and negative'
	@echo 'make test-tools  no compiler, assembler, disassembler or debugger is invoked'
	@echo 'make test-coverage  every supported form is exercised by some test input'
	@echo 'make test-capability  new syntax vs the old spelling: same bytes'
	@echo 'make test-superior  inputs asm1 handles and asm0a cannot'
	@echo 'make fixpoint   the built asm1 must reproduce itself, byte for byte'
	@echo 'make bootstrap-check  asm0a and seed/asm1 must agree on src/asm1.s'
	@echo 'make triage     which is broken: your source edit, or the seed'
	@echo 'make promote    replace seed/asm1 with the built asm1 (deliberate)'
	@echo 'make demo       build count10 and run it'
	@echo 'make record     rebuild and write the provenance ledger (a deliberate act)'
	@echo 'make which FILE=f which assembler produced f (by content sha)'
	@echo 'make check      forbidden tools, bootstrap, shas, branch decodes, provenance'
	@echo 'make clean      remove generated binaries'
all: asm1 dis cc

# The branch decoder. It is built by asm1 from src/dis.s like any other program,
# and it exists because the gate that checks docs/branches.tsv may not use
# objdump: a disassembler is the tool this project replaces.
dis: src/dis.s asm1
	@$(ASM1) < src/dis.s > $@
	@chmod +x $@
	@printf '  dis   %s bytes  sha %s  (built by %s from src/dis.s)\n' \
	  "$$(wc -c < $@)" "$$(sha256sum $@ | cut -c1-16)" "$(ASM1)"
bootstrap:
	@printf '  asm0a %s bytes  sha %s  (hand-written machine code; nothing to build)\n' \
	  "$$(wc -c < $(ASM0A))" "$$(sha256sum $(ASM0A) | cut -c1-16)"
# asm1 is built by the SEED, never by itself. seed/asm1 is the promoted previous
# stage: a binary must never be its own reference, or a miscompilation survives
# every generation with nothing to compare against.
asm1: src/asm1.s $(SEED)
	@$(SEED) < src/asm1.s > $@
	@chmod +x $@
	@printf '  asm1  %s bytes  sha %s  (built by %s from src/asm1.s)\n' \
	  "$$(wc -c < $@)" "$$(sha256sum $@ | cut -c1-16)" "$(SEED)"
test: test-asm0a asm1 test-asm1 test-dis test-reject test-reject-msg test-capability test-superior
test-asm0a:
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	for f in $(PAIRS); do \
	  $(ASM0A) < src/$$f.s > $$tmp/$$f || { echo "  asm0a cannot assemble $$f.s"; fail=1; continue; }; \
	  if cmp -s $$tmp/$$f ref/$$f; then ok=$$((ok+1)); else echo "  MISMATCH $$f"; fail=1; fi; \
	done; \
	for f in $(HELLO); do \
	  $(ASM0A) < src/$$f.s > $$tmp/$$f || { echo "  asm0a cannot assemble $$f.s"; fail=1; continue; }; \
	  if cmp -s $$tmp/$$f ref/hello; then ok=$$((ok+1)); else echo "  MISMATCH $$f"; fail=1; fi; \
	done; \
	for b in $(BEHAVE); do \
	  n=$${b%%:*}; want=$${b##*:}; \
	  $(ASM0A) < src/$$n.s > $$tmp/$$n || { echo "  asm0a cannot assemble $$n.s"; fail=1; continue; }; \
	  chmod +x $$tmp/$$n; \
	  if $$tmp/$$n; then got=0; else got=$$?; fi; \
	  if [ $$got -eq $$want ]; then ok=$$((ok+1)); else echo "  WRONG EXIT $$n: $$got, wanted $$want"; fail=1; fi; \
	done; \
	printf '  asm0a  %s/%s oracles reproduced\n' $$ok $(TOTAL); \
	exit $$fail
test-asm1: asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	for f in $(PAIRS); do \
	  $(ASM1) < src/$$f.s > $$tmp/$$f || { echo "  asm1 cannot assemble $$f.s"; fail=1; continue; }; \
	  if cmp -s $$tmp/$$f ref/$$f; then ok=$$((ok+1)); else echo "  MISMATCH $$f"; fail=1; fi; \
	done; \
	for f in $(HELLO); do \
	  $(ASM1) < src/$$f.s > $$tmp/$$f || { echo "  asm1 cannot assemble $$f.s"; fail=1; continue; }; \
	  if cmp -s $$tmp/$$f ref/hello; then ok=$$((ok+1)); else echo "  MISMATCH $$f"; fail=1; fi; \
	done; \
	for b in $(BEHAVE); do \
	  n=$${b%%:*}; want=$${b##*:}; \
	  $(ASM1) < src/$$n.s > $$tmp/$$n || { echo "  asm1 cannot assemble $$n.s"; fail=1; continue; }; \
	  chmod +x $$tmp/$$n; \
	  if $$tmp/$$n; then got=0; else got=$$?; fi; \
	  if [ $$got -eq $$want ]; then ok=$$((ok+1)); else echo "  WRONG EXIT $$n: $$got, wanted $$want"; fail=1; fi; \
	done; \
	printf '  asm1   %s/%s oracles reproduced\n' $$ok $(TOTAL); \
	exit $$fail
# ---- the fixpoint -----------------------------------------------------------
fixpoint: asm1
	@$(ASM1) < src/asm1.s > asm1b
	@chmod +x asm1b
	@if cmp -s asm1 asm1b; then \
	  printf '  fixpoint holds: asm1(asm1.s) == asm1, %s bytes\n' "$$(wc -c < asm1)"; \
	else \
	  echo '  FIXPOINT BROKEN: the second generation differs'; cmp -l asm1 asm1b | head -5; exit 1; \
	fi
demo: asm1
	@$(ASM0A) < src/count10.s > count10
	@chmod +x count10
	@printf '  count10 (built by asm0a): '; ./count10 | tr '\n' ' '; echo
	@$(ASM1) < src/count10.s > count10
	@printf '  count10 (built by asm1):  '; ./count10 | tr '\n' ' '; echo
# ---- provenance -------------------------------------------------------------
# asm0a is frozen and only src/asm1.s moves, so every artifact is attributable to
# a specific assembler binary by sha256. The ledger is written only by `record`:
# recording asserts a change is intended, and a build step that absorbed drift
# silently is exactly how a stale record would go unnoticed.
record: asm1 dis
	@./tools/provenance.sh record
verify-provenance: asm1 dis
	@./tools/provenance.sh verify
which: asm1
	@[ -n "$(FILE)" ] || { echo 'usage: make which FILE=<artifact>' >&2; exit 2; }
	@./tools/provenance.sh which $(FILE)
check: test-tools asm1 dis cc test-coverage fixpoint bootstrap-check test-reject test-reject-msg test-msg-exact test-capability test-superior test-dis test-cc verify-provenance
	@sha256sum -c docs/SHAS > /dev/null && echo "  docs/SHAS: pinned artifacts match"
	@sha256sum -c docs/asm1.sha > /dev/null 2>&1 \
	  && echo "  docs/asm1.sha: this asm1 is the recorded one" \
	  || { echo "  asm1 DOES NOT MATCH docs/asm1.sha -- the assembler changed"; \
	       echo "  if that is intended: make record"; exit 1; }
	@./tools/check-branches.sh
clean:
	@rm -f asm1 asm1b count10 dis cc hello hello.s
	@echo "  removed asm1, asm1b, count10, dis, cc, hello, hello.s"

# ---- bootstrap chain --------------------------------------------------------
# Two builders exist while the dialect is still within asm0a's reach:
#   asm0a      hand-written, frozen, and a completely independent implementation
#   seed/asm1  the promoted previous stage
# They must agree on src/asm1.s. That agreement stops being available the moment
# src/asm1.s uses a form asm0a cannot parse (Stage 1 of docs/ROADMAP.md), so this
# target reports "not applicable" rather than passing silently when that happens.
bootstrap-check: asm1
	@if $(ASM0A) < src/asm1.s > asm1.from-asm0a 2>/dev/null; then \
	  if cmp -s asm1.from-asm0a asm1; then \
	    echo "  bootstrap: asm0a and $(SEED) agree on src/asm1.s"; \
	  else \
	    echo "  BOOTSTRAP MISMATCH: asm0a and $(SEED) disagree on src/asm1.s"; \
	    cmp -l asm1.from-asm0a asm1 | head -5; exit 1; \
	  fi; \
	else \
	  echo "  bootstrap: asm0a can no longer parse the dialect -- NOT APPLICABLE,"; \
	  echo "             $(SEED) is the only builder (expected from Stage 1 on)"; \
	fi
	@rm -f asm1.from-asm0a

# Replacing the seed is an assertion that the new stage is good. It is never done
# by a build step, because an automatic promote makes the chain unfalsifiable.
promote: asm1 fixpoint
	@old=$$(sha256sum $(SEED) | cut -d' ' -f1); \
	 cp asm1 $(SEED) && chmod +x $(SEED); \
	 new=$$(sha256sum $(SEED) | cut -d' ' -f1); \
	 if [ "$$old" = "$$new" ]; then \
	   echo "  seed/asm1 unchanged ($${new%%????????????????}); nothing to promote"; \
	 else \
	   printf 'asm1\t%s\t%s\t%s\tpromoted from src/asm1.s\n' "$$new" "$(SEED)" "$$old" >> docs/toolchain.tsv; \
	   echo "  promoted seed/asm1: $${new%%????????????????} (was $${old%%????????????????})"; \
	 fi
	@./tools/provenance.sh record

# ---- the decoder ------------------------------------------------------------
# Each case is an input, a site, and the whole line the decoder must print --
# hand-written from the encoding rules, not produced by the decoder. A decoder
# tested against its own output proves nothing, so refusals are here in the same
# file: `refuse:<reason>` means exit non-zero, NOT ONE BYTE on stdout, and
# exactly `dis: <reason>` on stderr -- the reason is pinned, so a refusal that
# names the wrong rule fails.
test-dis: dis
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; n=0; \
	while read -r hex site want; do \
	  case "$$hex" in ''|'#'*) continue ;; esac; \
	  n=$$((n+1)); \
	  case "$$hex" in \
	    -) : > $$tmp/in ;; \
	    *) printf '%s\n' "$$hex" | xxd -r -p > $$tmp/in ;; \
	  esac; \
	  $(DIS) "$$site" < $$tmp/in > $$tmp/got 2> $$tmp/err; rc=$$?; \
	  case "$$want" in \
	  refuse*) \
	    printf 'dis: %s\n' "$${want#refuse:}" > $$tmp/want; \
	    if [ $$rc -ne 0 ] && [ ! -s $$tmp/got ] && cmp -s $$tmp/err $$tmp/want; then ok=$$((ok+1)); \
	    else echo "  REFUSAL: [$$hex] site $$site -> '$$(cat $$tmp/got)' / '$$(cat $$tmp/err)' (exit $$rc), want '$$want'"; fail=1; fi ;; \
	  *) \
	    printf '%s\n' "$$want" > $$tmp/want; \
	    if [ $$rc -eq 0 ] && cmp -s $$tmp/got $$tmp/want; then ok=$$((ok+1)); \
	    else echo "  DECODE: [$$hex] site $$site -> '$$(cat $$tmp/got)' (exit $$rc), want '$$want'"; fail=1; fi ;; \
	  esac; \
	done < tests/dis/cases.tsv; \
	if [ $$n -lt 30 ]; then echo "  only $$n cases -- the suite has been emptied"; exit 1; fi; \
	if [ $$ok -ne $$n ]; then echo "  dis: $$ok/$$n cases"; exit 1; fi; \
	printf '  dis   %s/%s cases: decoded and refused as hand-written\n' $$ok $$n

# ---- forbidden tools ---------------------------------------------------------
# Invariant 10: no compiler, system assembler, disassembler, interpreter or
# debugger in the creation OR diagnosis path. Its check used to be "by
# inspection", and inspection failed twice: the branch gate shelled out to
# objdump for weeks, and docs/oracles.md told the next session to do the same.
# This is that inspection made executable -- every recipe line of this file and
# every non-comment line of tools/*.sh, against a list of tool names.
#
# It is a tripwire, not a proof. `as` and `ld` are absent on purpose: two letters
# that match inside shell code (this file already has a variable called `as`), so
# they stay under inspection. Byte-comparison utilities -- cmp, od, xxd, sed, awk,
# shell itself -- are not on the list: they read and compare the artifact, they do
# not decode or translate it.
#
# The docs are deliberately not scanned. They have to be able to say "this was
# done with objdump, and that is now forbidden", which is the record; what must
# not survive is an invocation.
FORBIDDEN := objdump|objcopy|readelf|gcc|g\+\+|clang|nasm|gas|gdb|lldb|strace|python|python3|perl|ruby|node
test-tools:
	@scan() { grep -v '^[[:space:]]*#' "$$1" | grep -nwE '$(FORBIDDEN)'; }; \
	mscan() { awk '/^\t/' Makefile | grep -nwE '$(FORBIDDEN)'; }; \
	fail=0; \
	if [ -n "$$(mscan)" ]; then \
	  echo '  FORBIDDEN TOOL invoked in a Makefile recipe:'; mscan | sed 's/^/    /'; fail=1; \
	fi; \
	for f in tools/*.sh; do \
	  if [ -n "$$(scan $$f)" ]; then \
	    echo "  FORBIDDEN TOOL invoked in $$f:"; scan $$f | sed 's/^/    /'; fail=1; \
	  fi; \
	done; \
	tmp=$$(mktemp); trap 'rm -f $$tmp' EXIT; \
	tool=$$(echo '$(FORBIDDEN)' | cut -d'|' -f1); \
	printf '%s -d artifact\n' "$$tool" > $$tmp; \
	if [ -z "$$(scan $$tmp)" ]; then \
	  echo "  the forbidden-tool check cannot fail: '$$tool -d' was not caught"; fail=1; \
	fi; \
	[ $$fail -eq 0 ] && echo '  forbidden tools: none invoked in a Makefile recipe or tools/*.sh'; \
	exit $$fail

# ---- the compiler -----------------------------------------------------------
# cc is built by asm1 from src/cc.s like every other program here, and it emits
# DIALECT SOURCE, not machine code. That is the whole point: the compiler's
# output is a file a person can read and diff, asm1 remains the only thing that
# produces bytes, and everything the assembler already proves applies to what
# the compiler writes.
cc: src/cc.s asm1
	@$(ASM1) < src/cc.s > $@
	@chmod +x $@
	@printf '  cc    %s bytes  sha %s  (built by %s from src/cc.s)\n' \
	  "$$(wc -c < $@)" "$$(sha256sum $@ | cut -c1-16)" "$(ASM1)"

# One command for the whole pipeline. The two-stage version is easy to half-copy
# -- and half-copied, cc's output is dialect TEXT that the shell will happily
# try to run, one `command not found` per line. So: build it, assemble it, run it.
hello: cc asm1 helloworld.c
	@$(CC) < helloworld.c > hello.s
	@$(ASM1) < hello.s > $@
	@chmod +x $@
	@printf '  helloworld.c -> hello.s -> hello (%s bytes, sha %s)\n' \
	  "$$(wc -c < $@)" "$$(sha256sum $@ | cut -c1-16)"
	@./hello

# Four gates, and each can fail on its own:
#   1. the text:  cc's output must be byte-identical to the hand-written golden,
#      so no refactor can silently change the shape of what it emits
#   2. the assembly: that text must be accepted by asm1 and produce a binary
#   3. the behaviour: the binary must write exactly "Hello, World!\n" and exit 0
#   4. the refusal: anything outside the subset is exit 1 with NO output at all
# Gate 3 is what makes gate 1 mean something. A golden whose validity rests only
# on matching itself is a regression pin, not an oracle; the machine is the
# oracle, and it judges gate 3.
test-cc: cc asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; n=0; \
	$(CC) < helloworld.c > $$tmp/got.s 2>/dev/null || { echo "  cc cannot compile helloworld.c"; exit 1; }; \
	if cmp -s $$tmp/got.s tests/golden/hello.s; then \
	  printf '  cc    helloworld.c -> tests/golden/hello.s byte for byte\n'; \
	else \
	  echo "  the emitted text differs from tests/golden/hello.s:"; \
	  diff -u tests/golden/hello.s $$tmp/got.s | sed -n '3,20p'; fail=1; fi; \
	if $(ASM1) < tests/golden/hello.s > $$tmp/hello 2>/dev/null; then \
	  chmod +x $$tmp/hello; \
	  if $$tmp/hello > $$tmp/out; then got=0; else got=$$?; fi; \
	  printf 'Hello, World!\n' > $$tmp/want; \
	  if [ $$got -eq 0 ] && cmp -s $$tmp/out $$tmp/want; then \
	    printf '  cc    the binary prints "Hello, World!" and exits 0\n'; \
	  else \
	    echo "  the binary exited $$got and wrote [$$(cat $$tmp/out)]"; fail=1; fi; \
	else \
	  echo "  asm1 refuses tests/golden/hello.s"; fail=1; fi; \
	if $(CC) < tests/golden/twowrites.c > $$tmp/tw.s 2>/dev/null && cmp -s $$tmp/tw.s tests/golden/twowrites.s; then :; \
	else echo "  twowrites.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/twowrites.s > $$tmp/tw 2>/dev/null; then \
	  chmod +x $$tmp/tw; \
	  if $$tmp/tw > $$tmp/two 2>&1; then got=0; else got=$$?; fi; \
	  printf 'ABB' > $$tmp/want2; \
	  if [ $$got -eq 255 ] && cmp -s $$tmp/two $$tmp/want2; then \
	    printf '  cc    two writes and return 255: prints ABB, exits 255\n'; \
	  else echo "  twowrites exited $$got, wrote [$$(cat $$tmp/two)]"; fail=1; fi; \
	else echo "  asm1 refuses tests/golden/twowrites.s"; fail=1; fi; \
	if $(CC) < tests/golden/loop.c > $$tmp/loop.s 2>/dev/null && cmp -s $$tmp/loop.s tests/golden/loop.s; then :; \
	else echo "  loop.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/loop.s > $$tmp/loop 2>/dev/null && $(ASM1) < tests/oracle/dots.s > $$tmp/dots 2>/dev/null; then \
	  chmod +x $$tmp/loop $$tmp/dots; \
	  if $$tmp/loop > $$tmp/a; then g1=0; else g1=$$?; fi; \
	  if $$tmp/dots > $$tmp/b; then g2=0; else g2=$$?; fi; \
	  printf '..........' > $$tmp/ten; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ] && cmp -s $$tmp/a $$tmp/ten && cmp -s $$tmp/a $$tmp/b; then \
	    printf '  cc    a while loop: same output as the hand-written dialect program\n'; \
	if $(CC) < tests/golden/twovars.c > $$tmp/tv.s 2>/dev/null && cmp -s $$tmp/tv.s tests/golden/twovars.s; then :; \
	else echo "  twovars.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/twovars.s > $$tmp/tv 2>/dev/null && $(ASM1) < tests/oracle/twovars.s > $$tmp/to 2>/dev/null; then \
	  chmod +x $$tmp/tv $$tmp/to; \
	  if $$tmp/tv > $$tmp/d1; then g1=0; else g1=$$?; fi; \
	  if $$tmp/to > $$tmp/d2; then g2=0; else g2=$$?; fi; \
	  printf '...!' > $$tmp/want4; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ] && cmp -s $$tmp/d1 $$tmp/want4 && cmp -s $$tmp/d1 $$tmp/d2; then \
	    printf '  cc    two variables: same output as the hand-written dialect program\n'; \
	  else echo "  twovars: exits $$g1/$$g2, [$$(cat $$tmp/d1)] vs [$$(cat $$tmp/d2)]"; fail=1; fi; \
	else echo "  the twovars case does not assemble"; fail=1; fi; \
	if $(CC) < tests/golden/branch.c > $$tmp/br.s 2>/dev/null && cmp -s $$tmp/br.s tests/golden/branch.s; then :; \
	else echo "  branch.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/branch.s > $$tmp/bc 2>/dev/null && $(ASM1) < tests/oracle/branch.s > $$tmp/bo 2>/dev/null; then \
	if $(CC) < tests/golden/exprs.c > $$tmp/ex.s 2>/dev/null && cmp -s $$tmp/ex.s tests/golden/exprs.s; then :; \
	else echo "  exprs.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/exprs.s > $$tmp/ex 2>/dev/null; then \
	  chmod +x $$tmp/ex; \
	  if $$tmp/ex; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 18 ]; then \
	    printf '  cc    precedence: (2 + 3*4) - 10 + 14 exits 18\n'; \
	if $(CC) < tests/golden/calladd.c > $$tmp/ca.s 2>/dev/null && cmp -s $$tmp/ca.s tests/golden/calladd.s; then :; \
	else echo "  calladd.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/calladd.s > $$tmp/ca 2>/dev/null && $(ASM1) < tests/golden/callsub.s > $$tmp/cs 2>/dev/null; then \
	  chmod +x $$tmp/ca $$tmp/cs; \
	  if $$tmp/ca; then g1=0; else g1=$$?; fi; \
	  if $$tmp/cs; then g2=0; else g2=$$?; fi; \
	  if [ $$g1 -eq 5 ] && [ $$g2 -eq 1 ]; then \
	    printf '  cc    a call: add(2,3) exits 5 and sub2(3,2) exits 1 (argument order)\n'; \
	if $(CC) < tests/golden/callvar.c > $$tmp/cv.s 2>/dev/null && cmp -s $$tmp/cv.s tests/golden/callvar.s; then \
	  if $(ASM1) < tests/golden/callvar.s > $$tmp/cv 2>/dev/null; then \
	    chmod +x $$tmp/cv; \
	    if $$tmp/cv; then g1=0; else g1=$$?; fi; \
	    if [ $$g1 -eq 42 ]; then \
	      printf '  cc    a variable argument: f(x) with x=41 exits 42\n'; \
	if $(CC) < tests/golden/recursion.c > $$tmp/rc.s 2>/dev/null && cmp -s $$tmp/rc.s tests/golden/recursion.s; then \
	  if $(ASM1) < tests/golden/recursion.s > $$tmp/rc 2>/dev/null; then \
	    chmod +x $$tmp/rc; \
	    if $$tmp/rc; then g1=0; else g1=$$?; fi; \
	    if [ $$g1 -eq 10 ]; then \
	      printf '  cc    recursion: f(10,0) with an accumulator exits 10 (ten frames)\n'; \
	    else echo "  recursion exited $$g1, wanted 10 -- frames or arguments are wrong"; fail=1; fi; \
	  else echo "  asm1 refuses recursion.s"; fail=1; fi; \
	else echo "  recursion.c does not compile to its golden"; fail=1; fi; \
	if $(CC) < tests/golden/ptr.c > $$tmp/pt.s 2>/dev/null && cmp -s $$tmp/pt.s tests/golden/ptr.s; then :; \
	else echo "  ptr.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/ptr.s > $$tmp/pt 2>/dev/null; then \
	  chmod +x $$tmp/pt; \
	  if $$tmp/pt; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 40 ]; then \
	    printf '  cc    pointers: &x, *p, then *p = 33 -- x + the saved 7 exits 40\n'; \
	  else echo "  ptr exited $$g1, wanted 40 -- an address or a dereference is wrong"; fail=1; fi; \
	else echo "  asm1 refuses ptr.s"; fail=1; fi; \
	if $(CC) < tests/golden/ptrarg.c > $$tmp/pta.s 2>/dev/null && cmp -s $$tmp/pta.s tests/golden/ptrarg.s; then :; \
	else echo "  ptrarg.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/ptrarg.s > $$tmp/pta 2>/dev/null; then \
	  chmod +x $$tmp/pta; \
	  if $$tmp/pta; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 42 ]; then \
	    printf '  cc    a pointer across a call: bump(&x) writes 42 into the caller\n'; \
	  else echo "  ptrarg exited $$g1, wanted 42 -- the address did not survive the call"; fail=1; fi; \
	else echo "  asm1 refuses ptrarg.s"; fail=1; fi; \
	if $(CC) < tests/golden/array.c > $$tmp/ay.s 2>/dev/null && cmp -s $$tmp/ay.s tests/golden/array.s; then :; \
	else echo "  array.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/array.s > $$tmp/ay 2>/dev/null; then \
	  chmod +x $$tmp/ay; \
	  if $$tmp/ay; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 42 ]; then \
	    printf '  cc    arrays: a[0] and a[i] with i=2, read back and summed, exit 42\n'; \
	  else echo "  array exited $$g1, wanted 42 -- the stride or the base is wrong"; fail=1; fi; \
	else echo "  asm1 refuses array.s"; fail=1; fi; \
	if $(CC) < tests/golden/arrayarg.c > $$tmp/aa.s 2>/dev/null && cmp -s $$tmp/aa.s tests/golden/arrayarg.s; then :; \
	else echo "  arrayarg.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/arrayarg.s > $$tmp/aa 2>/dev/null; then \
	  chmod +x $$tmp/aa; \
	  if $$tmp/aa; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 42 ]; then \
	    printf '  cc    an element as an argument: f(a[i]) exits 42\n'; \
	  else echo "  arrayarg exited $$g1, wanted 42"; fail=1; fi; \
	else echo "  asm1 refuses arrayarg.s"; fail=1; fi; \
	if $(CC) < tests/golden/argmul.c > $$tmp/am.s 2>/dev/null && cmp -s $$tmp/am.s tests/golden/argmul.s; then :; \
	else echo "  argmul.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/argmul.s > $$tmp/am 2>/dev/null; then \
	  chmod +x $$tmp/am; \
	  if $$tmp/am; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 42 ]; then \
	    printf '  cc    an argument with a product: f(x * 2) exits 42\n'; \
	if $(CC) < tests/golden/fact.c > $$tmp/fc.s 2>/dev/null && cmp -s $$tmp/fc.s tests/golden/fact.s; then :; \
	else echo "  fact.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/fact.s > $$tmp/fc 2>/dev/null; then \
	  chmod +x $$tmp/fc; \
	  if $$tmp/fc; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 120 ]; then \
	    printf '  cc    non-tail recursion: fact(5) exits 120 -- the call is inside a product\n'; \
	  else echo "  fact exited $$g1, wanted 120 -- the live register was not saved across the call"; fail=1; fi; \
	else echo "  asm1 refuses fact.s"; fail=1; fi; \
	if $(CC) < tests/golden/ntsum.c > $$tmp/ns.s 2>/dev/null && cmp -s $$tmp/ns.s tests/golden/ntsum.s; then :; \
	else echo "  ntsum.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/ntsum.s > $$tmp/ns 2>/dev/null; then \
	  chmod +x $$tmp/ns; \
	  if $$tmp/ns; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 10 ]; then \
	    printf '  cc    and inside a sum: sum(4) exits 10\n'; \
	if $(CC) < tests/golden/char.c > $$tmp/cr.s 2>/dev/null && cmp -s $$tmp/cr.s tests/golden/char.s; then :; \
	else echo "  char.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/char.s > $$tmp/cr 2>/dev/null; then \
	  chmod +x $$tmp/cr; \
	  if $$tmp/cr; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 131 ]; then \
	    printf '  cc    char array: a[0]=65, a[i]=66 with i=1, byte load and store, exits 131\n'; \
	  else echo "  char exited $$g1, wanted 131 -- a byte was written with the wrong width or stride"; fail=1; fi; \
	else echo "  asm1 refuses char.s"; fail=1; fi; \
	if $(CC) < tests/golden/charpack.c > $$tmp/cp.s 2>/dev/null && cmp -s $$tmp/cp.s tests/golden/charpack.s; then :; \
	else echo "  charpack.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/charpack.s > $$tmp/cp 2>/dev/null; then \
	  chmod +x $$tmp/cp; \
	  if $$tmp/cp; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 72 ]; then \
	    printf '  cc    char a[9] takes two slots: a[8]=65 beside int b=7 exits 72\n'; \
	if $(CC) < tests/golden/longname.c > $$tmp/ln.s 2>/dev/null && cmp -s $$tmp/ln.s tests/golden/longname.s; then :; \
	else echo "  longname.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/longname.s > $$tmp/ln 2>/dev/null; then \
	  chmod +x $$tmp/ln; \
	  if $$tmp/ln; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 42 ]; then \
	    printf '  cc    names longer than seven: averylongname(xyzlongname) exits 42\n'; \
	if $(CC) < tests/golden/readsum.c > $$tmp/rs.s 2>/dev/null && cmp -s $$tmp/rs.s tests/golden/readsum.s; then :; \
	else echo "  readsum.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/readsum.s > $$tmp/rs 2>/dev/null; then \
	  chmod +x $$tmp/rs; \
	  printf 'ABC' | $$tmp/rs; if [ $$? -eq 198 ]; then g1=0; else g1=1; fi; \
	  printf 'ABCDEFGHIJ' | $$tmp/rs; if [ $$? -eq 193 ]; then g2=0; else g2=1; fi; \
	  printf '' | $$tmp/rs; if [ $$? -eq 0 ]; then g3=0; else g3=1; fi; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ] && [ $$g3 -eq 0 ]; then \
	    printf '  cc    read(): a stdin loop over a char array sums 198, then 193, then 0\n'; \
	if $(CC) < tests/golden/cmpvar.c > $$tmp/cv.s 2>/dev/null && cmp -s $$tmp/cv.s tests/golden/cmpvar.s; then :; \
	else echo "  cmpvar.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/cmpvar.s > $$tmp/cv 2>/dev/null; then \
	  chmod +x $$tmp/cv; \
	  if $$tmp/cv; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 10 ]; then \
	    printf '  cc    a variable bound: while (i < n) sums 0..4 and exits 10\n'; \
	  else echo "  cmpvar exited $$g1, wanted 10"; fail=1; fi; \
	else echo "  asm1 refuses cmpvar.s"; fail=1; fi; \
	if $(CC) < tests/golden/readloop.c > $$tmp/rl.s 2>/dev/null && cmp -s $$tmp/rl.s tests/golden/readloop.s; then :; \
	else echo "  readloop.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/readloop.s > $$tmp/rl 2>/dev/null; then \
	  chmod +x $$tmp/rl; \
	  printf 'ABC' | $$tmp/rl; if [ $$? -eq 198 ]; then g1=0; else g1=1; fi; \
	  printf 'ABCDEFGHIJ' | $$tmp/rl; if [ $$? -eq 193 ]; then g2=0; else g2=1; fi; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ]; then \
	    printf '  cc    read in a loop with i < n: 198 for ABC, 193 for ten bytes\n'; \
	if $(CC) < tests/golden/sumbuf.c > $$tmp/sb.s 2>/dev/null && cmp -s $$tmp/sb.s tests/golden/sumbuf.s; then :; \
	else echo "  sumbuf.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/sumbuf.s > $$tmp/sb 2>/dev/null; then \
	  chmod +x $$tmp/sb; \
	  if $$tmp/sb; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 198 ]; then \
	    printf '  cc    a buffer crosses a call: sumbuf(&s, 3) exits 198\n'; \
	if $(CC) < tests/golden/manyvars.c > $$tmp/mv.s 2>/dev/null && cmp -s $$tmp/mv.s tests/golden/manyvars.s; then :; \
	else echo "  manyvars.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/manyvars.s > $$tmp/mv 2>/dev/null; then \
	  chmod +x $$tmp/mv; \
	  if $$tmp/mv; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 21 ]; then \
	    printf '  cc    twenty variables in one function: v1 + v20 exits 21\n'; \
	if $(CC) < tests/golden/cmpbound.c > $$tmp/cb.s 2>/dev/null && cmp -s $$tmp/cb.s tests/golden/cmpbound.s; then :; \
	else echo "  cmpbound.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/cmpbound.s > $$tmp/cb 2>/dev/null; then \
	  chmod +x $$tmp/cb; \
	  if $$tmp/cb; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 6 ]; then \
	    printf '  cc    i <= n with a variable bound: 0..5 inclusive exits 6\n'; \
	if $(CC) < tests/golden/bigarray.c > $$tmp/ba.s 2>/dev/null && cmp -s $$tmp/ba.s tests/golden/bigarray.s; then :; \
	else echo "  bigarray.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/bigarray.s > $$tmp/ba 2>/dev/null; then \
	  chmod +x $$tmp/ba; \
	  if $$tmp/ba; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 65 ]; then \
	    printf '  cc    a 200-byte buffer, written in a loop, exits 65\n'; \
	if $(CC) < tests/golden/widearray.c > $$tmp/wa.s 2>/dev/null && cmp -s $$tmp/wa.s tests/golden/widearray.s; then :; \
	else echo "  widearray.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/widearray.s > $$tmp/wa 2>/dev/null; then \
	  chmod +x $$tmp/wa; \
	  if $$tmp/wa; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 65 ]; then \
	    printf '  cc    a 2000-byte buffer at index 1999 exits 65 (four-digit literals)\n'; \
	if $(CC) < tests/golden/catfile.c > $$tmp/cf.s 2>/dev/null && cmp -s $$tmp/cf.s tests/golden/catfile.s; then :; \
	else echo "  catfile.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/catfile.s > $$tmp/cf 2>/dev/null; then \
	  chmod +x $$tmp/cf; \
	  printf 'hello, world\n' > $$tmp/want5; \
	  $$tmp/cf < $$tmp/want5 > $$tmp/got5; g1=$$?; \
	  printf 'one\ntwo\nthree\nfour\n' > $$tmp/want6; \
	  $$tmp/cf < $$tmp/want6 > $$tmp/got6; g2=$$?; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ] && cmp -s $$tmp/got5 $$tmp/want5 && cmp -s $$tmp/got6 $$tmp/want6; then \
	    printf '  cc    cat: stdin copied to stdout byte for byte, twice\n'; \
	if $(CC) < tests/golden/upcase.c > $$tmp/uc.s 2>/dev/null && cmp -s $$tmp/uc.s tests/golden/upcase.s; then :; \
	else echo "  upcase.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/upcase.s > $$tmp/uc 2>/dev/null; then \
	  chmod +x $$tmp/uc; \
	  printf 'aabbcca\n' > $$tmp/want7; \
	  printf 'AABBccA\n' > $$tmp/want8; \
	  $$tmp/uc < $$tmp/want7 > $$tmp/got7; g1=$$?; \
	  if [ $$g1 -eq 0 ] && cmp -s $$tmp/got7 $$tmp/want8; then \
	    printf '  cc    a filter: a and b upper-cased in stdin, written to stdout\n'; \
	if $(CC) < tests/golden/cndterm.c > $$tmp/ct.s 2>/dev/null && cmp -s $$tmp/ct.s tests/golden/cndterm.s; then :; \
	else echo "  cndterm.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/cndterm.s > $$tmp/ct 2>/dev/null; then \
	  chmod +x $$tmp/ct; \
	  if $$tmp/ct; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 3 ]; then \
	    printf '  cc    a term in a condition: while (a[i] > 0) over 3,2,1,0 exits 3\n'; \
	  else echo "  cndterm exited $$g1, wanted 3"; fail=1; fi; \
	else echo "  asm1 refuses cndterm.s"; fail=1; fi; \
	  else echo "  upcase: exit $$g1, output [$$(cat $$tmp/got7)]"; fail=1; fi; \
	else echo "  asm1 refuses upcase.s"; fail=1; fi; \
	  else echo "  catfile: exits $$g1/$$g2, and its output does not match its input"; fail=1; fi; \
	else echo "  asm1 refuses catfile.s"; fail=1; fi; \
	  else echo "  widearray exited $$g1, wanted 65 -- a literal or an offset is truncated"; fail=1; fi; \
	else echo "  asm1 refuses widearray.s"; fail=1; fi; \
	  else echo "  bigarray exited $$g1, wanted 65 -- the array is outside the frame"; fail=1; fi; \
	else echo "  asm1 refuses bigarray.s"; fail=1; fi; \
	  else echo "  cmpbound exited $$g1, wanted 6 -- the bound adjustment is wrong"; fail=1; fi; \
	else echo "  asm1 refuses cmpbound.s"; fail=1; fi; \
	  else echo "  manyvars exited $$g1, wanted 21 -- the frame is too small for the slots"; fail=1; fi; \
	else echo "  asm1 refuses manyvars.s"; fail=1; fi; \
	  else echo "  sumbuf exited $$g1, wanted 198 -- the callee cannot read the caller's array"; fail=1; fi; \
	else echo "  asm1 refuses sumbuf.s"; fail=1; fi; \
	  else echo "  readloop: wanted 198/193"; fail=1; fi; \
	else echo "  asm1 refuses readloop.s"; fail=1; fi; \
	  else echo "  readsum: three inputs want 198/193/0"; fail=1; fi; \
	else echo "  asm1 refuses readsum.s"; fail=1; fi; \
	if $(CC) < tests/golden/divmod.c > $$tmp/dm.s 2>/dev/null && cmp -s $$tmp/dm.s tests/golden/divmod.s; then :; \
	else echo "  divmod.c does not compile to its golden"; fail=1; fi; \
	if $(ASM1) < tests/golden/divmod.s > $$tmp/dm 2>/dev/null; then \
	  chmod +x $$tmp/dm; \
	  if $$tmp/dm; then g1=0; else g1=$$?; fi; \
	  if [ $$g1 -eq 142 ]; then \
	    printf '  cc    division: q=100/7, r=100%%7, q*10+r exits 142\n'; \
	  else echo "  divmod exited $$g1, wanted 142 -- the quotient or the remainder is wrong"; fail=1; fi; \
	else echo "  asm1 refuses divmod.s"; fail=1; fi; \
	  else echo "  longname exited $$g1, wanted 42"; fail=1; fi; \
	else echo "  asm1 refuses longname.s -- the label limit is the compiler's limit"; fail=1; fi; \
	  else echo "  charpack exited $$g1, wanted 72 -- the char array overran its slots"; fail=1; fi; \
	else echo "  asm1 refuses charpack.s"; fail=1; fi; \
	  else echo "  ntsum exited $$g1, wanted 10"; fail=1; fi; \
	else echo "  asm1 refuses ntsum.s"; fail=1; fi; \
	  else echo "  argmul exited $$g1, wanted 42"; fail=1; fi; \
	else echo "  asm1 refuses argmul.s"; fail=1; fi; \
	    else echo "  f(x) exited $$g1, wanted 42"; fail=1; fi; \
	  else echo "  asm1 refuses callvar.s"; fail=1; fi; \
	else echo "  callvar.c does not compile to its golden"; fail=1; fi; \
	  else echo "  calls exited $$g1/$$g2, wanted 5/1 -- the convention is wrong"; fail=1; fi; \
	else echo "  the call cases do not assemble"; fail=1; fi; \
	  else echo "  exprs exited $$g1, wanted 18 (precedence is wrong)"; fail=1; fi; \
	else echo "  asm1 refuses tests/golden/exprs.s"; fail=1; fi; \
	  chmod +x $$tmp/bc $$tmp/bo; \
	  if $$tmp/bc > $$tmp/c1; then g1=0; else g1=$$?; fi; \
	  if $$tmp/bo > $$tmp/c2; then g2=0; else g2=$$?; fi; \
	  printf '..-..' > $$tmp/want3; \
	  if [ $$g1 -eq 0 ] && [ $$g2 -eq 0 ] && cmp -s $$tmp/c1 $$tmp/want3 && cmp -s $$tmp/c1 $$tmp/c2; then \
	    printf '  cc    if/else and a comparison: same output as the hand-written dialect program\n'; \
	  else echo "  branch case: exits $$g1/$$g2, [$$(cat $$tmp/c1)] vs [$$(cat $$tmp/c2)]"; fail=1; fi; \
	else echo "  the branch case does not assemble"; fail=1; fi; \
	  else \
	    echo "  loop case: exits $$g1/$$g2, [$$(cat $$tmp/a)] vs [$$(cat $$tmp/b)]"; fail=1; fi; \
	else \
	  echo "  the loop case does not assemble"; fail=1; fi; \
	refuse() { \
	  n=$$((n+1)); \
	  printf '%s' "$$1" > $$tmp/bad.c; \
	  $(CC) < $$tmp/bad.c > $$tmp/bad.s 2>/dev/null; rc=$$?; \
	  if [ $$rc -ne 0 ] && [ ! -s $$tmp/bad.s ]; then ok=$$((ok+1)); \
	  else echo "  NOT REFUSED: [$$1] -> exit $$rc, $$(wc -c < $$tmp/bad.s) bytes"; fail=1; fi; \
	}; \
	refuse 'int main() {}'; \
	refuse 'int main(void) { puts("x"); }'; \
	refuse 'int main(void) { write(x); }'; \
	refuse 'int main(void) { write("unterminated); }'; \
	refuse 'int main(void) { int x = 70000; }'; \
	refuse 'void main(void) {}'; \
	refuse 'int main(void) { write("a"); write("b"); write("c"); write("d"); write("e"); write("f"); write("g"); write("h"); write("i"); write("j"); }'; \
	refuse '/* unterminated'; \
	refuse 'int main(void) { x = 1; }'; \
	refuse 'int main(void) { while (y) { } }'; \
	refuse 'int main(void) { int x = 0; if (x = 1) { } }'; \
	refuse 'int main(void) { int x = 0; if (x) { } else if (x) { } }'; \
	refuse 'int main(void) { int x = 255; if (x <= 255) { } }'; \
	refuse 'int main(void) { y = 1; }'; \
	refuse 'int main(void) { int x = 1; int x = 2; }'; \
	refuse 'int main(void) { int abcdefghijklmnopq = 1; }'; \
	refuse 'int main(void) { int x = 1 & 1; }'; \
	refuse 'int main(void) { int x = 1; int y = read(x, 4); }'; \
	refuse 'int main(void) { char s[4]; int n = read(s); }'; \
	refuse 'int main(void) { int x = 1; if (x <= 255) { } }'; \
	refuse 'int main(void) { int x = 1; if (x >= 0) { } }'; \
	refuse 'int f(void) { return 1; } int main(void) { return f(1, 2, 3, 4, 5); }'; \
	refuse 'int main(void) { int p = &5; }'; \
	refuse 'int main(void) { int y = *q; }'; \
	refuse 'int main(void) { int p = &nope; }'; \
	refuse 'int main(void) { int a[4]; a = 1; }'; \
	refuse 'int main(void) { int a[4]; int y = a; }'; \
	refuse 'int main(void) { char s[4]; int n = read(&s, 4); }'; \
	refuse 'int main(void) { int a[4]; int b[4]; int y = a[b[0]]; }'; \
	refuse 'int main(void) { int a[1024]; }'; \
	refuse 'int main(void) { int a[2]; int a[2]; }'; \
	refuse 'int main(void) { char x = 65; }'; \
	refuse 'int main(void) { char a[4]; a = 1; }'; \
	refuse 'int f(void) { return 1; } int main(void) { return f(f()); }'; \
	refuse 'int main(void) { int v1 = 1; int v2 = 2; int v3 = 3; int v4 = 4; int v5 = 5; int v6 = 6; int v7 = 7; int v8 = 8; int v9 = 9; int v10 = 10; int v11 = 11; int v12 = 12; int v13 = 13; int v14 = 14; int v15 = 15; int v16 = 16; int v17 = 17; int v18 = 18; int v19 = 19; int v20 = 20; int v21 = 21; int v22 = 22; int v23 = 23; int v24 = 24; int v25 = 25; int v26 = 26; int v27 = 27; int v28 = 28; int v29 = 29; int v30 = 30; int v31 = 31; int v32 = 32; int v33 = 33; }'; \
	if [ $$ok -ne $$n ]; then echo "  cc: $$ok/$$n refusals"; fail=1; fi; \
	printf '  cc    %s/%s rejections outside the subset, with no output\n' $$ok $$n; \
	exit $$fail


# ---- coverage ---------------------------------------------------------------
# The claim is tests/coverage/forms.tsv: one probe per supported form. Each must
# assemble, and its normalised shape (tools/shape.awk) must appear in some test
# input. A form nobody tests is a red gate with a name on it, which is the
# difference between "we have 18 fixtures" and "we know what they reach".
test-coverage: asm1
	@./tools/coverage.sh

# ---- rejection parity -------------------------------------------------------
# A positive suite cannot see a silently truncated encoding: a wrong byte is
# still a byte. These sources must be REFUSED -- non-zero exit and NO output --
# by both assemblers. Partial output would be worse than nothing, which is why
# asm1 has a validate pass that resolves every label before it writes a byte.
REJECT := $(sort $(wildcard tests/reject/*.s))

test-reject: asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	for f in $(REJECT); do \
	  $(ASM0A) < $$f > $$tmp/o 2>/dev/null; a=$$?; as=$$(wc -c < $$tmp/o); \
	  $(ASM1) < $$f > $$tmp/o 2>/dev/null; b=$$?; bs=$$(wc -c < $$tmp/o); \
	  if [ $$a -ne 0 ] && [ $$b -ne 0 ] && [ $$as -eq 0 ] && [ $$bs -eq 0 ]; then \
	    ok=$$((ok+1)); \
	  else \
	    echo "  NOT REFUSED $$f: asm0a exit $$a ($$as bytes), asm1 exit $$b ($$bs bytes)"; \
	    fail=1; \
	  fi; \
	done; \
	printf '  reject %s/%s refused by both, with no output\n' $$ok $(words $(REJECT)); \
	exit $$fail

# ---- capability divergence --------------------------------------------------
# asm1 accepts syntax asm0a cannot parse: hex literals, character literals. That
# divergence is the whole point of Stage 1 -- it is what lets src/asm1.s outgrow
# the frozen bootstrap -- but it needs an oracle, and no reference binary exists
# for syntax nobody hand-emitted.
#
# The oracle is the old spelling of the same thing. Every *.cap.s must be rejected
# by asm0a, and asm1 must produce the SAME BYTES for it as for the equivalent
# *.ref.s written in asm0a's dialect. Two spellings, one encoding: if they ever
# differ, one of them is wrong.
CAP := $(sort $(wildcard tests/capability/*.cap.s))

test-capability: asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	for f in $(CAP); do \
	  b=$${f%.cap.s}; \
	  $(ASM0A) < $$f > $$tmp/x 2>/dev/null && { echo "  $$f: asm0a ACCEPTS the new syntax (it should not)"; fail=1; continue; }; \
	  $(ASM0A) < $$b.ref.s > $$tmp/y 2>/dev/null || { echo "  $$b.ref.s: asm0a rejects the old spelling"; fail=1; continue; }; \
	  $(ASM1) < $$f > $$tmp/c 2>/dev/null || { echo "  $$f: asm1 rejects the new syntax"; fail=1; continue; }; \
	  $(ASM1) < $$b.ref.s > $$tmp/r 2>/dev/null || { echo "  $$b.ref.s: asm1 rejects the old spelling"; fail=1; continue; }; \
	  if cmp -s $$tmp/c $$tmp/r; then ok=$$((ok+1)); \
	  else echo "  $$b: spellings disagree"; cmp -l $$tmp/c $$tmp/r | head -3; fail=1; fi; \
	done; \
	printf '  capability %s/%s pairs: asm1 accepts, asm0a refuses, bytes agree\n' $$ok $(words $(CAP)); \
	exit $$fail

# ---- triage -----------------------------------------------------------------
# A bootstrap cannot tell you whether a failed build is the source or the seed,
# because the same binary is both the tool and the subject. Two facts settle it,
# and both come from the last commit — a state that passed every gate when made.
triage:
	@./tools/triage.sh

# ---- superiority ------------------------------------------------------------
# Cases where asm1 is demonstrably RIGHT and asm0a is not: the input either
# cannot be assembled by asm0a, or asm0a emits the wrong bytes for it. Two
# kinds of case live here.
#
#   tests/superior/<name>.s     a source
#   tests/superior/<name>.hex   the body bytes, HAND-COMPUTED from the encoding
#                               (the file after the 120-byte header), not
#                               captured from asm1
#
# asm1 must reproduce <name>.hex exactly, and asm0a must NOT -- if the two ever
# agree, the case stopped discriminating and the test fails saying so.
#
# Plus two cases the hex cannot express: a 99 KB source (asm0a cannot read it)
# and the `entry` directive (asserted through e_entry and by running it).
SUP := $(sort $(wildcard tests/superior/*.s))
test-superior: asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	for s in $(SUP); do \
	  b=$${s%.s}; \
	  $(ASM1) < $$s > $$tmp/a 2>/dev/null || { echo "  asm1 cannot assemble $$s"; fail=1; continue; }; \
	  got=$$(xxd -s 120 -p $$tmp/a | tr -d ' \n'); \
	  want=$$(sed 's/#.*//' $$b.hex | tr -d ' \t\n'); \
	  if [ "$$got" != "$$want" ]; then \
	    echo "  $$b: asm1 emits [$$got], hand-computed [$$want]"; fail=1; continue; fi; \
	  if $(ASM0A) < $$s > $$tmp/z 2>/dev/null && [ "$$(xxd -s 120 -p $$tmp/z | tr -d ' \n')" = "$$want" ]; then \
	    echo "  asm0a now reproduces $$b: this case no longer discriminates"; fail=1; continue; fi; \
	  ok=$$((ok+1)); printf '  superior: %s -> %s, and asm0a does not\n' "$$b" "$$want"; \
	done; \
	if [ $$fail -eq 0 ] && [ $$ok -lt 2 ]; then echo "  only $$ok byte-level cases: the suite has been emptied"; fail=1; fi; \
	{ seq 1 9000 | sed 's/.*/mov eax, 1/'; \
	  printf 'mov eax, 60\nmov edi, 42\nsyscall\n'; } > $$tmp/big.s; \
	size=$$(wc -c < $$tmp/big.s); \
	if [ $$size -le 65536 ]; then \
	  echo "  the test source is only $$size bytes -- it must exceed asm0a's 64 KiB read"; exit 1; fi; \
	if $(ASM0A) < $$tmp/big.s > $$tmp/a 2>/dev/null; then \
	  echo "  asm0a now assembles a $$size byte source: this test no longer discriminates"; fail=1; fi; \
	if ! $(ASM1) < $$tmp/big.s > $$tmp/b 2>/dev/null; then \
	  echo "  asm1 cannot assemble a $$size byte source"; exit 1; fi; \
	chmod +x $$tmp/b; \
	if $$tmp/b; then got=0; else got=$$?; fi; \
	if [ $$got -eq 42 ]; then \
	  printf '  superior: asm1 assembles %s bytes that asm0a cannot, and it runs (exit 42)\n' $$size; \
	else \
	  echo "  the binary built from the big source exited $$got, wanted 42"; fail=1; fi; \
	printf 'db 1, 2, 3, 4\ncode:\nmov eax, 60\nmov edi, 42\nsyscall\nentry code\n' > $$tmp/e.s; \
	if $(ASM0A) < $$tmp/e.s > $$tmp/ea 2>/dev/null; then \
	  echo "  asm0a accepts 'entry': this test no longer discriminates"; fail=1; fi; \
	if $(ASM1) < $$tmp/e.s > $$tmp/eb 2>/dev/null; then \
	  chmod +x $$tmp/eb; \
	  entry=$$(od -An -tx1 -j24 -N4 $$tmp/eb | tr -d ' \n'); \
	  if $$tmp/eb; then got=0; else got=$$?; fi; \
	  if [ "$$entry" = "7c004000" ] && [ $$got -eq 42 ]; then \
	    printf '  superior: entry directive -> e_entry 0x40007c, data first, runs (exit 42)\n'; \
	  else \
	    echo "  entry case: e_entry bytes $$entry, exit $$got (wanted 7c004000 / 42)"; fail=1; fi; \
	else \
	  echo "  asm1 cannot assemble the entry case"; fail=1; fi; \
	printf 'mov r8d, 40\nmov r9d, 2\nadd r8d, r9d\nmov edi, r8d\nmov eax, 60\nsyscall\n' > $$tmp/r.s; \
	if $(ASM0A) < $$tmp/r.s > $$tmp/ra 2>/dev/null; then \
	  echo "  asm0a accepts r8d: this test no longer discriminates"; fail=1; fi; \
	if $(ASM1) < $$tmp/r.s > $$tmp/rb 2>/dev/null; then \
	  chmod +x $$tmp/rb; \
	  if $$tmp/rb; then got=0; else got=$$?; fi; \
	  if [ $$got -eq 42 ]; then \
	    printf '  superior: r8d-r15d arithmetic runs and exits 42 (asm0a cannot assemble it)\n'; \
	  else echo "  the r8d program exited $$got, wanted 42"; fail=1; fi; \
	else echo "  asm1 cannot assemble the r8d program"; fail=1; fi; \
	exit $$fail

test-reject-msg: asm1
	@fail=0; \
	for f in tests/reject/*.s; do \
	  err=$$($(ASM1) < $$f 2>&1 >/dev/null); \
	  case "$$err" in \
	    "line "*) : ;; \
	    *) echo "  $$f: no line number in the message: '$$err'"; fail=1 ;; \
	  esac; \
	done; \
	[ $$fail -eq 0 ] && echo "  messages: every rejection names its line"; exit $$fail

# The message must name the line AND the reason. Each expectation below is written
# out exactly as it must appear, so a vague message fails rather than passes.
test-msg-exact: asm1
	@tmp=$$(mktemp -d); trap 'rm -rf $$tmp' EXIT; fail=0; ok=0; \
	check() { \
	  printf '%b\n' "$$2" > $$tmp/m.s; \
	  got=$$($(ASM1) < $$tmp/m.s 2>&1 >/dev/null); \
	  if [ "$$got" = "$$1" ]; then ok=$$((ok+1)); \
	  else echo "  message for [$$2]: got '$$got', wanted '$$1'"; fail=1; fi; \
	}; \
	check "line 1: range" "mov bl, 300"; \
	check "line 1: range" "cmp bl, 200"; \
	check "line 1: label" "db nosuch"; \
	check "line 1: label" "jmp nosuch"; \
	check "line 2: rejected" "mov eax, 1\nfrobnicate 1"; \
	check "line 1: rejected" "jbe x"; \
	check "line 1: rejected" "jnb x"; \
	check "line 3: duplicate" "x:\nret\nx:"; \
	printf '  messages %s/8 exact: line number and reason\n' $$ok; \
	exit $$fail
