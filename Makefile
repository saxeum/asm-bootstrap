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
	refuse 'int main(void) { return 300; }'; \
	refuse 'void main(void) {}'; \
	refuse 'int main(void) { write("a"); write("b"); write("c"); write("d"); write("e"); write("f"); write("g"); write("h"); write("i"); write("j"); }'; \
	refuse '/* unterminated'; \
	refuse 'int main(void) { x = 1; }'; \
	refuse 'int main(void) { while (y) { } }'; \
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
