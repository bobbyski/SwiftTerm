# SwiftTerm embedding qualification

## Dashboard

**Engineering progress:** `█████████████████████████` **100%** (6 / 6 checks verified)

| # | Phase | Progress | % | Status |
| ---: | --- | --- | ---: | --- |
| 1 | Repeated PTY child lifecycle for BBCBasicStudio Phase6 | `█████████████████████████` | 100% | ✅ Verified |
| 2 | Explicit shader packaging for the embedding app | `█████████████████████████` | 100% | ✅ Verified |

2026-10-10: Actual BBCBasicStudio exposed a repeated child-exit race: the worker exited but the terminal stayed running and destination choices stayed disabled. Reads, deferred output and monitor callbacks now capture a session generation; monitors capture their own PID, register before activation, and PTY EOF keeps the macOS child running until real exit is reaped. Preserve Linux's existing EOF state behavior. Four focused framework tests pass, including30 immediate replacements, final output ordering and POSIX exit-status decoding. Actual Studio now repeats eZOS Stop, restores menu selection and boots MOS in the same terminal. [UI receipt](/Users/bobby/AIResearch/BBCBasic/Documents/Evidence/Phase6/ui.json). [Test log](/Users/bobby/AIResearch/BBCBasic/.build/terminal-reuse-tests.log). This is a consumer qualification, not a claim about all SwiftTerm product coverage. No real JIRA issue has been filed; the pending local prefix is BBC.

- [x] S1.1: Thirty immediate replacement children plus existing PTY output-order/exit-status regressions pass. [Test](Tests/SwiftTermTests/LocalProcessReuseTests.swift).
- [x] S1.2: Actual Studio repeats Agon Stop/Boot and switches destinations without stale running state. [Consumer dashboard](/Users/bobby/AIResearch/BBCBasic/Documents/PLAN.md).

The existing LocalProcess class exceeds500 lines; this change scopes its current lifecycle machinery. Future decomposition should extract generation-scoped output delivery and child/PTY ownership into separate types; a cosmetic extension split would not reduce ownership complexity.

2026-10-10 shader follow-up: Swift Build emits a mutated-node warning for the Metal-only resource bundle. Native-engine, graph reset and intermediate-signing attempts did not solve it. Added opt-in SWIFTTERM_COPY_SHADER_SOURCE resource copying; default consumers retain their existing process behavior. BBC packaging compiles a default.metallib explicitly with Apple's Metal tools, and the existing renderer loader consumes it. The opt-in Studio build emits no warnings, and explicit Metal compilation produces the27486-byte library. Final packaged Studio now renders native rectangle/disc/triangle/border with exit0 and the exact current eZOS256×256 chip bitmap in the retained terminal. Temporary UI automation loss resolved by rebinding the bundle ID; app sampling showed its main loop idle, with no crash. The separate guest palette-byte leak is owned by the VDP protocol peer. [Current UI receipt](/Users/bobby/AIResearch/BBCBasic/Documents/Evidence/Phase6/ui.json). [Build log](/Users/bobby/AIResearch/BBCBasic/.build/agon-studio-clean-build.log).

- [x] S2.1: Opt-in embedding build and explicit Metal compilation produce no resource-graph or source warnings.
- [x] S2.2: The packaged Studio renders native VTG shapes and the exact guest bitmap with the explicit Metal library.

2026-10-10 packaged-image follow-up: Actual Studio Stop left a defunct child and stale controls despite the worker exiting. Added a generation-scoped nonblocking reap after ordered PTY EOF, with retries while the child is genuinely live. It complements the kqueue monitor and never treats EOF as a successful exit. Next: focused regressions and actual packaged Studio Stop/restart. No real issue key exists.

- [x] S1.3: Early EOF without a process monitor waits for the real exit, returns its code, and preserves repeated-child/output-order regressions.
- [x] S1.4: Actual packaged default-image Studio Stop reaps its child and restores destination/Boot controls.

Five focused tests pass, including early EOF with a cancelled monitor and a still-live child (actual exit7),30 successive children, output ordering and exit-status decoding. [Log](/Users/bobby/AIResearch/BBCBasic/.build/terminal-eof-reap-tests.log). Actual Studio recheck is next.

Actual final packaged Studio now repeats MOS Boot/Stop twice, restores disabled Pause/Reset/Stop and enabled Boot, and selects Native Mac again. [Consumer evidence](/Users/bobby/AIResearch/BBCBasic/Documents/Evidence/Phase6/default-image.json). EOF backstop requalification is complete.
