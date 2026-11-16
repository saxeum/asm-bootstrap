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
# src/<name>.s assembles to ref/<name>
PAIRS := addr32 callret cmp32 cmp8 count10 dbnum inc8 jmp jz load loop movrr \
         r8 rel32 stack store
# src/hello_num.s assembles to the hand-written ref/hello
HELLO := hello_num
# no oracle: the program's exit status is the assertion
BEHAVE := exit42:42
TOTAL := $(words $(PAIRS) $(HELLO) $(BEHAVE))
.PHONY: all bootstrap asm1 test test-asm0a test-asm1 test-reject fixpoint bootstrap-check promote demo record verify-provenance which check clean help
help:
	@echo 'make            build asm1 from seed/asm1 (the promoted previous stage)'
	@echo 'make test       assemble every fixture with both assemblers, compare to ref/'
	@echo 'make test-reject  sources that must be refused, with no output'
	@echo 'make fixpoint   the built asm1 must reproduce itself, byte for byte'
	@echo 'make bootstrap-check  asm0a and seed/asm1 must agree on src/asm1.s'
	@echo 'make promote    replace seed/asm1 with the built asm1 (deliberate)'
	@echo 'make demo       build count10 and run it'
	@echo 'make record     rebuild and write the provenance ledger (a deliberate act)'
	@echo 'make which FILE=f which assembler produced f (by content sha)'
	@echo 'make check      bootstrap, shas, branch decodes, provenance'
	@echo 'make clean      remove generated binaries'
all: asm1
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
test: test-asm0a asm1 test-asm1 test-reject
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
record: asm1
	@./tools/provenance.sh record
verify-provenance: asm1
	@./tools/provenance.sh verify
which: asm1
	@[ -n "$(FILE)" ] || { echo 'usage: make which FILE=<artifact>' >&2; exit 2; }
	@./tools/provenance.sh which $(FILE)
check: asm1 fixpoint bootstrap-check test-reject verify-provenance
	@sha256sum -c docs/SHAS > /dev/null && echo "  docs/SHAS: pinned artifacts match"
	@sha256sum -c docs/asm1.sha > /dev/null 2>&1 \
	  && echo "  docs/asm1.sha: this asm1 is the recorded one" \
	  || { echo "  asm1 DOES NOT MATCH docs/asm1.sha -- the assembler changed"; \
	       echo "  if that is intended: make record"; exit 1; }
	@./tools/check-branches.sh > /dev/null && echo "  branches: pinned sites decode as recorded"
	@./tools/check-branches.sh --selftest > /dev/null && echo "  branches: checker rejects known-bad sites"
clean:
	@rm -f asm1 asm1b count10
	@echo '  removed asm1, asm1b, count10'

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
