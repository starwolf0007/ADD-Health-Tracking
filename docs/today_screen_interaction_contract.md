# Today Screen — Interaction Contract

**Status:** Locked. Passed physical-device testing.
**Reference implementation:** `lib/screens/prototypes/today_screen_interaction_reference.dart`
**Do not modify these behaviors during production integration.** Changing
any of them is a deliberate future amendment — propose it, get a review
pass, get sign-off — not something that happens as a side effect of
wiring real data.

Two lines below are corrected from the draft version of this contract to
match what was actually tested, not what was originally described. See
the notes under each.

## Locked behaviors

- **Accept Day** accepts all selectable proposals in one action.
- **Review Plan** enters granular per-block selection.
- **Done Reviewing**, when at least one block was selected, keeps the
  accepted blocks and **removes every other selectable block from the
  displayed timeline** — locked/non-selectable blocks are unaffected.
  *(Corrected from "preserves selected blocks" — that's true but
  incomplete: unselected ones don't just sit there unmarked, they're
  dropped from what's shown.)*
- **Done Reviewing** with zero selections rejects the proposal and
  restores the base plan.
- **Keep Original** restores the base scenario and the original timeline.
- **Not Now** dismisses the proposal, returns to ambient state, **and
  restores the base scenario and original timeline** — the same block
  restoration as Keep Original, distinguished only by the resulting state
  (ambient vs. rejected) and label. *(This was raised as an open design
  question during review — should Not Now leave the proposed blocks
  untouched instead, as a pure defer-without-discarding? — and this is
  the behavior that was actually tested and passed. Locking it as tested.
  If the alternative is wanted later, that's an amendment, not a
  reinterpretation of this contract.)*
- **Undo** restores the complete previous state — blocks, status, and
  active scenario — from immediately before the last action.
- **Keep Day Open** (from the unavailable state only) returns to ambient
  with the base scenario restored. No undo point is created — there is
  nothing meaningful to undo back to from an unavailable state.
- Locked anchors cannot be selected or rejected during review.
- Open Space blocks are informational and non-selectable during review.
- `isNow` is derived from comparing block start/end against the current
  clock — never stored on the block itself.
- Lexi communicates state but never owns or mutates schedule state.
- Commute and recovery timing are resolver-controlled in production —
  the mock hardcodes them per scenario only because no resolver exists
  at prototype stage.
- Partial acceptance is a distinct outcome from full acceptance, with its
  own status and its own Lexi briefing.

## Block types (visual treatment, no additional hues)

| Type | Treatment |
|---|---|
| `anchor` | Solid fill |
| `flex` | Outline only |
| `runway` | Left accent edge + faint top/bottom borders |
| `recoveryBuffer` | Left accent edge + very faint fill tint |
| `openSpace` | Faint outline only |

## Explicitly still open

- **Lexi's accent-color governance** — whether informational states
  (loading, attention, unavailable) get their own color family, or
  whether only action controls use the single locked accent while
  everything else relies on icon/weight/opacity. Not decided. Not
  locked by this contract.
