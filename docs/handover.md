# Handover gate: when may `asm0a` build `asm0b`?

The question this file answers: **what must be true before the next assembler is built by the
current one?**

It matters more than it looks, because the handover is the moment when one artifact's
behaviour is frozen into another's bytes. `asm0b` is not compiled from a specification — it is
*emitted* by `asm0a`. Every encoding choice `asm0a` makes becomes an encoding choice baked into
`asm0b` at birth, with no chance to differ. A bug in `asm0a` does not fail loudly at the
handover; it becomes `asm0b`'s starting condition.

## Necessary conditions — all six, no exceptions

| # | Condition | Why |
|---|---|---|
| 1 | **No red oracles.** Every wave `asm0a` claims is byte-identical on its fixture, and the runtime assertion passes. | A red wave means at least one encoding path is wrong. Handing over now bakes it in. |
| 2 | **Dialect closure.** `asm0b.s` uses only forms `asm0a` implements — established by `asm0a` assembling `asm0b.s` with exit 0. | An unimplemented form must fail, not be approximated. |
| 3 | **Per-form verification.** Every form `asm0b.s` uses has (a) a hand-emitted reference fixture it reproduces byte-identically, (b) a behavioural assertion whose value differs when the form is wrong, (c) a row in `docs/encodings.md` traced to the reference XML. | This is the only independent check on the encoding that `asm0b` will inherit. |
| 4 | **Loud failure.** Anything `asm0a` cannot encode exits non-zero. Never a plausible wrong binary. | A silent approximation in `asm0a` is a silent approximation in `asm0b`. |
| 5 | **Resource limits honoured by `asm0b.s`**: source < 64 KiB, ≤ 32 labels, names ≤ 7 chars, body < 0xF000, rel8 displacements within ±127, `83 /7`-style immediates within −128..127. | These are hard limits in `asm0a` today. Exceeding one is not an error the assembler detects — it is corruption. |
| 6 | **Reproducibility.** The exact `asm0a` (sha in `docs/SHAS`) and the exact command used are recorded. | Otherwise "asm0b was built by asm0a" is a claim with no object behind it. |

## Sufficient combination — handover is *complete* when

| # | Condition |
|---|---|
| 7 | `asm0b`, as built by `asm0a`, passes the **whole inherited corpus** byte-identically: `exit42`, `hello_num`, `jmp`. |
| 8 | **Fixpoint**: `asm0b` assembling `asm0b.s` produces bytes identical to what `asm0a` produced for `asm0b.s` (`stage2 == stage3`). |
| 9 | **Superset demonstrated**: `asm0b` assembles at least one fixture `asm0a` cannot. Otherwise the wave had no purpose. |

Note what condition 8 does **not** do: the fixpoint detects *inconsistency between the two
assemblers*, not *incorrectness*. If `asm0a` emits a valid but non-canonical encoding, `asm0b`
inherits the same choice and the fixpoint passes — both agree, both non-canonical. Only
condition 3 (the reference table) catches that. This is why 3 is a precondition and 8 is not
sufficient on its own.

## Refusal criteria — reasons to *not* proceed

- **Any required fix to `asm0a` that is not a single same-size rel32 patch.** More than that
  means the layout is past hand-verification; re-emit instead. (This rule was adopted after
  wave 2a, where patching failed three times and a clean re-emission passed immediately.)
- **A form with no independent check.** No reference row, no decode check, no behavioural
  fixture → the encoding is a guess, and a guess is what gets frozen into `asm0b`.
- **"asm0a produced it" as the only evidence for `asm0b`.** That is the shared-authorship hole
  from `docs/oracles.md`: the same hands wrote the encoder and chose the source.

## Verdict today: BLOCKED

| # | Condition | State |
|---|---|---|
| 1 | No red oracles | **RED** — wave 2b fails: `jmp label` segfaults, forward and backward. Comments, labels and the two-pass flip work; the jump does not. |
| 2 | Dialect closure | Unknown — `asm0b.s` does not exist yet. Foreseeable needs: `entry` directive (not implemented), more than 32 labels, names > 7 chars. |
| 3 | Per-form verification | 4 forms verified end to end (`mov r32,imm`, `xor r32,r32`, `syscall`, `db`). 25 more are documented in `docs/encodings.md` but not exercised by any fixture. |
| 4 | Loud failure | Partial. Unknown mnemonic and unknown register exit 1. But `mov eax,` with no operand assembles as `mov eax, 0` and exits 0, and the `83 /7` immediate range is unenforced. |
| 5 | Resource limits | 32 labels, 7-char names, body < 0xF000, rel8 ±127 — all real limits, none currently enforced by a diagnostic except rel8. |
| 6 | Reproducibility | Yes: `asm0a` sha in `docs/SHAS`, build command recorded in `docs/waves/`. |
| 7–9 | Corpus, fixpoint, superset | Not applicable — no `asm0b` exists. |

**`asm0a` cannot build `asm0b` yet.** It is blocked at condition 1, and conditions 2–5 would
each block it independently once 1 is green.

## The 2b failure, and what it says about the method

Six defects were found and fixed in the 441-byte appended block, and each fix revealed the
next. Every one was displacement or REX arithmetic:

1. `mov r11,rcx` written `4c 89 cb` — REX.B set for `rcx`, so it was `mov r9,rbx`.
2. `add rbx,3` assumed 3 bytes; with REX it is 4, shifting three displacements.
3. `mov rdx,[rsp+disp32]` assumed 9 bytes; it is 8, shifting nine displacements.
4. Four branch targets recomputed for the pre-shift layout, landing one byte off.
5. `jmp notfound` written one byte late, clobbering the `8b` of `mov eax,[rdi]`.
6. `sub rdx,r14` written `4d 29 f2` — REX.B for `rdx`, so `sub rdx,r10`.

The pattern is not "six mistakes", it is **one mistake repeated**: hand-computing byte offsets
across a 441-byte region with variable-length instructions. `objdump` caught every one, and
caught nothing before it was emitted — which is the general lesson: hand-laid code is verified
by decoding it and executing it, never by re-reading the arithmetic.

Consequence: 2b gets **re-emitted from one coherent layout**, smallest-possible blocks, sizes
asserted at every boundary, and every branch target checked against the label it should reach
before the next block is appended. The existing attempt is preserved on branch `wip/2b` so the
diagnosis is not lost; `main` keeps the green 2a artifact.
