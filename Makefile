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

# src/<name>.s assembles to ref/<name>
PAIRS := addr32 callret cmp32 cmp8 count10 dbnum inc8 jmp jz load loop movrr \
         r8 rel32 stack store

# src/hello_num.s assembles to the hand-written ref/hello
HELLO := hello_num

# no oracle: the program's exit status is the assertion
BEHAVE := exit42:42

TOTAL := $(words $(PAIRS) $(HELLO) $(BEHAVE))

.PHONY: all bootstrap asm1 test test-asm0a test-asm1 fixpoint demo check clean help

help:
	@echo 'make            build asm1 from the hand-emitted asm0a'
	@echo 'make test       assemble every fixture with both assemblers, compare to ref/'
	@echo 'make fixpoint   asm1(asm1.s) must equal asm0a(asm1.s), byte for byte'
	@echo 'make demo       build count10 and run it'
	@echo 'make check      pinned shas and branch decodes'
	@echo 'make clean      remove generated binaries'

all: asm1

bootstrap:
	@printf '  asm0a %s bytes  sha %s  (hand-written machine code; nothing to build)\n' \
	  "$$(wc -c < $(ASM0A))" "$$(sha256sum $(ASM0A) | cut -c1-16)"

asm1: src/asm1.s $(ASM0A)
	@$(ASM0A) < src/asm1.s > $@
	@chmod +x $@
	@printf '  asm1  %s bytes  sha %s  (built by asm0a from src/asm1.s)\n' \
	  "$$(wc -c < $@)" "$$(sha256sum $@ | cut -c1-16)"

# ---- the fixtures, assembled by each assembler ------------------------------
test: test-asm0a asm1 test-asm1

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
	  printf '  fixpoint holds: asm0a(asm1.s) == asm1(asm1.s), %s bytes\n' "$$(wc -c < asm1)"; \
	else \
	  echo '  FIXPOINT BROKEN: the second generation differs'; cmp -l asm1 asm1b | head -5; exit 1; \
	fi

demo: asm1
	@$(ASM0A) < src/count10.s > count10
	@chmod +x count10
	@printf '  count10 (built by asm0a): '; ./count10 | tr '\n' ' '; echo
	@$(ASM1) < src/count10.s > count10
	@printf '  count10 (built by asm1):  '; ./count10 | tr '\n' ' '; echo

check:
	@sha256sum -c docs/SHAS > /dev/null && echo "  docs/SHAS: all pinned artifacts match"
	@./tools/check-branches.sh > /dev/null && echo "  branches: all pinned sites decode as recorded"
	@./tools/check-branches.sh --selftest > /dev/null && echo "  branches: the checker rejects known-bad sites"

clean:
	@rm -f asm1 asm1b count10
	@echo '  removed asm1, asm1b, count10'
