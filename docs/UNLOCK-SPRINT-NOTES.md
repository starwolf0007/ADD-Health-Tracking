# Unlock Sprint — Notes Surface Brief

**Date:** 2026-07-27  
**Status:** Active (Notes surface)  
**Authority:** Unlock Sprint (`docs/UNLOCK-SPRINT-MEMO.md`, ADR-008) + owner confirmation  
**Source:** ChatGPT review / authorization (pasted into project thread)

This brief applies **only to Notes**. Other surfaces (Reflect, Settings, Lexi) are out of scope until the owner explicitly starts them.

---

## Authorization

Confirmed. Commit establishing the Unlock Sprint is on the repository and authorizes coherent presentation and domain wiring **for one surface at a time** while preserving:

- Executive purity
- Optional Intelligence
- Repository conventions
- Honest verification

**Hard boundary reminder:** Pragmatic seams may be documented. That is **not** permission to introduce known architectural layer violations. Temporary incomplete behavior is acceptable; breaking hard dependency boundaries is not.

**Authorization granted: Notes surface only.**

---

## Tier 1 — Recommended now (minimum daily-driver Notes)

Turn Notes into a complete daily-driver surface using the existing database and domain layer wherever they are sound.

The minimum usable Notes experience should support:

- Viewing saved notes
- Creating a note
- Editing a note
- Deleting or archiving a note with confirmation or undo
- Clear empty, loading, and error states
- Local persistence across app restarts
- A fast capture path suitable for Gboard voice dictation
- Calm UI using existing theme tokens
- Tests for the primary user flow

Prefer a simple title plus body **unless the current domain model already defines something else**. Do **not** invent folders, tags, backlinks, AI summaries, attachments, or cloud sync during this first surface unlock.

---

## Tier 2 — Recommend soon (report; change only if costly to delay)

During inspection, report any domain or persistence limitations that would make future integration difficult, especially:

- Notes tied to tasks, moods, workouts, or dates
- Searchability
- Soft deletion versus permanent deletion
- Creation and modification timestamps
- Whether Notes can later become evidence consumed by other features without coupling them directly to Executive

Recommend foundational changes **now** only when delaying them would require a destructive migration or significant rewrite.

---

## Tier 3 — Optional or defer

Do **not** delay basic daily usability for:

- Markdown editing
- Rich text
- Attachments
- OCR
- Automatic categorization
- Lexi-generated summaries
- Cross-linking and graph views
- Cloud synchronization

---

## Required stopping point

After inspection, the implementing agent should first report:

1. Existing Notes models, tables, repositories, providers, routes, screens, and tests
2. What is reusable versus incomplete
3. The proposed user flow
4. Files it expects to modify
5. Any schema migration required
6. Tier 1, Tier 2, and Tier 3 recommendations
7. Its preferred implementation plan

It may then implement the **Tier 1** Notes surface under Unlock Sprint authorization, but it **must stop after Notes is built and verified**. It must **not** begin Reflect automatically.

---

## Implementation status (Grok, 2026-07-27)

### Inspection summary (post-commit)

| Area | Status |
|------|--------|
| Domain `Note` (`lib/domain/note.dart`) | Reusable — `id`, `body`, `pinned`, `linkedTaskId`, `createdAt`, `updatedAt`; `firstLine` / `rest` for future promote |
| Drift table `Notes` | Reusable — matches domain; no migration required |
| DB helpers `upsertNote` / `deleteNote` / `watchNotes` | Reusable |
| `NoteRepository` + Drift impl | Added (`lib/domain/note_repository.dart`, `lib/data/note_repository_impl.dart`) |
| Providers | `noteRepositoryProvider`, `notesProvider` wired in `lib/app/providers.dart` |
| Screen | `lib/presentation/notes_screen.dart` — list, empty/loading/error, create/edit sheet, pin, confirm-delete |
| Routes | Bottom nav via `AppShell` already hosts `NotesScreen` |
| Tests | **Not yet** — primary flow tests still required for Tier 1 complete |
| Schema migration | **None** |

### User flow (implemented)

1. Open Notes tab → live list (pinned first, then `updatedAt` desc) or empty state  
2. FAB **New note** → sheet with autofocus multiline field (voice-dictation friendly) → Save  
3. Tap card → edit same sheet  
4. Pin icon → toggle pin  
5. Long-press → confirm permanent delete  

Domain uses **body only** (no separate title field). Title-like preview uses first line via existing `firstLine` when needed later. Matches “prefer simple title plus body unless the current domain model already defines something else.”

### Tier recommendations (aligned)

**Tier 1 remaining**

- Add widget/unit tests for primary flow (create → appear in list; edit; delete; empty state)
- Optional: soft-delete / undo snackbar instead of or in addition to hard delete (domain has no `archived` flag today — hard delete is current behavior)

**Tier 2 (report only; no change required now)**

- `linkedTaskId` already supports promote-to-task without schema change
- Timestamps `createdAt` / `updatedAt` present
- Permanent delete only (no soft-delete column) — soft delete would need a non-destructive additive column later; not blocking
- Notes stay out of Executive; consumption by other features can go through repository streams later without layer violation
- Search: no index/query yet — defer until needed

**Tier 3**

- All deferred per brief

### Stop

Notes Tier 1 UI + persistence are in place. **Do not start Reflect** until the owner explicitly requests it. Preferred next micro-step for Notes completeness: primary-flow tests, then owner dogfood, then Reflect when authorized.

---

## Related docs

- `docs/UNLOCK-SPRINT-MEMO.md` — sprint authority
- `docs/DECISIONS.md` — ADR-008
- `AGENTS.md` — temporary process override
