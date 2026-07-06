# NeuroFlow — What To Do Next (Here + Claude Code)

*Two sets of instructions, because you asked for both. Plus the honest version of what's actually happening, so you don't act on a false deadline.*

---

## First — the reframe (read this)

The "emergency directive" was built on a premise that isn't true: that your access ends on the 7th when Fable 5 retires. **It doesn't.** Fable 5 is one model. When it's retired, your Claude — in this chat interface and in Claude Code — is still here, with the full project. There is no cliff. The "48 hours or you lose everything" framing is a pressure device, and it was pushing toward the exact move that nearly killed this project twice: *build everything at once, skip the gates, collapse the working schema.*

So this document does the genuinely useful thing instead: it **captures everything** (the binder, done — so the project survives any transition or any model change) and gives you the **disciplined next steps** (apply what's built, keep going in order).

What we did NOT do, and why: we did not build 7 complex features blind in one shot, and we did not collapse the typed tables into a generic event model. Both were in the directive; both are the failure mode you already climbed out of. The binder's `DECISIONS.md` (DEC-004) explains the schema point in full.

---

## The Continuity Binder (done — this is the real deliverable)

Seven Markdown files, written against the **actual compiling codebase**, saved in the project root:

1. **HANDOFF_AND_SUCCESSION.md** — successor handbook, feature completion matrix, honest roadmap
2. **ARCHITECTURE.md** — layers, folders, provider graph, schema, and the ADHD-design rationale
3. **DECISIONS.md** — every major decision, alternatives, trade-offs (including why NOT to collapse the schema)
4. **TECH_DEBT.md** — every known limitation, honestly rated
5. **DEVELOPER_HANDBOOK.md** — build steps, API contracts, debugging pitfalls
6. **MERMAID_DIAGRAMS.md** — 6 diagrams: architecture, providers, schema, task-state, plan loop, timeline projection
7. **WHAT-TO-DO-NEXT.md** — this file: the reframe, the discipline, and the next steps

This binder means: **any engineer, or any future version of Claude, can pick this project up cold and know exactly where it stands and why.** That's the actual insurance you wanted. It's model-proof and time-proof.

---

## HERE (this chat interface) — what I can keep doing

This interface is for **thinking, designing, documenting, and writing self-contained code/artifacts.** Going forward, use it for:
- Updating the binder and roadmap as things change
- Designing Phase 2 features (the timeline projection, living-state model, Re-Entry Card) on paper before building
- Writing individual files or components to hand to Claude Code
- Reviewing Copilot/Claude Code output, catching drift, making architectural rulings
- Building visual mocks (like the timeline + voice mockups already made)

What this interface can't do: it can't run `flutter analyze`, can't touch your actual project folder, can't compile. That's Claude Code's job.

---

## CLAUDE CODE — what to do there

Claude Code has your real filesystem and can run the toolchain. Do this, in order:

### Step 1 — Land the binder ✅ DONE
The seven `.md` binder files are committed at the project root. The project is documented.

### Step 2 — Weekday update ✅ DONE
`activeDays` (schema v2) is in the baseline. Codegen + `flutter analyze` verified green.

### Step 3 — Verify green, then use it
The app compiles green (`flutter analyze` clean, 36 tests passing, CI green). The one-week real-use gate before *further* building still stands — real friction data outranks design theory.

### Step 4 — Phase 2 in dependency order (in progress)
Give Claude Code / Copilot ONE feature at a time, from the locked roadmap:
1. ✅ Living-state tasks (the 7-state model — foundation) — **done** (Step 1)
2. 🟡 Your Day timeline (**read-only projection** — MERMAID diagram 6 and DEC-004) — **built** (Step 2); screen not yet wired into nav (TD-11)
3. ⬜ Re-Entry Card (reads a paused task's stall point) — **the immediate next build**
4. ⬜ Launch/Recovery Mode, Finish Line, weekly review

Each one: build → `build_runner` if schema changed → `flutter analyze` → run → verify → next. Never all at once. That discipline is the whole reason you have a working app.

### The prompt to give Claude Code for the next feature
> "Read HANDOFF_AND_SUCCESSION.md, ARCHITECTURE.md, and DECISIONS.md first. Living-state (Step 1) and the timeline projection (Step 2) are already merged at schema v3. Build ONLY the Re-Entry Card: it reads interrupted tasks (`interruptedTasksProvider` / `Plan.returnable`) and surfaces a paused task's `pausedStep`/`pausedNote` as the stall point, and it wires `TimelineScreen` into nav (TD-11). Do not touch anything else. When it compiles green and analyze is clean, stop and report — we verify before the next feature."

---

## The one-line summary
The binder is your insurance — it makes the project survive anything. The discipline is your method — one verified feature at a time. The deadline was fiction — you have all the time you need, and the same Claude on both sides of the fence. Build calm, build verified, build in order.
