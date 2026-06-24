# AGENTS.md

Guidance for agents working in this repository. See `README.md` for project
structure, verification, and formatting commands.

## Comment Conventions

Comments capture what the code cannot say for itself — intent and rationale, not
a restatement of the code. They split by audience.

### Doc comments (`///`): the contract

Document every type and public API with a doc comment describing *what* it
guarantees and *why* it exists — never *how* it is implemented. A caller should
be able to use it without reading the body.

- On a type: the design role it plays. e.g. `Day` keys daily data so that two
  timestamps on the same local day compare and hash as equal.
- On a method: the behavioral contract — inclusive/exclusive bounds, the meaning
  of `nil`, the `precondition`s, and how edge cases resolve. A short bullet list
  is preferred over prose when there are several rules.
- This is where rules from the design doc become the code's contract. State the
  rule, not the design-doc vocabulary (no "Phase 1", "section 6", etc.).

### Inline comments (`//`): the non-obvious *why*

Inside a body, comment only what is not evident from the code itself. Do not
paraphrase *what* a line does. Three things are worth a line:

1. **Design intent / trade-offs** — a choice the code cannot reveal. e.g. why
   `RelativeScaler` ranks against distinct values (tier, not frequency); why
   `Day.adding` re-normalizes with `startOfDay` (avoids DST drift).
2. **Non-obvious edges** — the reason behind a guard or expression, e.g.
   `max(count - 1, 1)`, the level clamp, or a `firstAvailableDay == nil` branch.
3. **Invariants** — the `precondition` message declares the programmer-error
   contract.

Leave obvious code uncommented: trivial assignments, getters, anything the
signature already says.

### Above all: preserve design intent

If a decision is not readable from the code — a formula chosen over an
alternative, a defensive guard, a boundary convention — leave the rationale in a
comment. This is the highest-value comment to write.

## Testing Conventions

These conventions apply to the `StepMossaicDomain` package tests (Swift Testing).
Existing tests are migrated opportunistically, when next touched — not in bulk.

### Structure: Arrange / Act / Assert

Write each test in AAA order with explicit section comments:

```swift
@Test("Normalizes any timestamp to the start of its local day")
func dayNormalizesToStartOfLocalDay() {
  // Arrange
  let calendar = TestCalendar.utc
  let components = DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 59)
  let date = calendar.date(from: components)!

  // Act
  let day = Day(containing: date, calendar: calendar)

  // Assert
  #expect(day.start == calendar.startOfDay(for: date))
}
```

- When a phase is a single self-evident line, collapse it into a combined
  `// Act & Assert` rather than padding empty sections.
- Prefer AAA (input → output) over Given/When/Then: the domain is mostly pure
  functions with no stateful preconditions to set up.

### Intent: `@Test` display name

Give every test a `@Test("...")` display name stating the behavior it
guarantees (the *what*). It surfaces in test output as a readable spec, separate
from the function name. Keep the function name behavior-oriented too.

### Verification points: `why` comments

Add a one-line comment only where an edge case is non-obvious, explaining *what
the case proves*, not restating the code. Examples:

- Using a 23:59 input proves the time-of-day is dropped, not merely preserved.
- Deriving month length from the next month is what makes leap February 29 days.
- A `.japanese` calendar would read `2026` as an era year if year/month were not
  forced to Gregorian.

Do not annotate every assertion; obvious checks stay uncommented.

### Grouping and helpers

- Keep tests as free `@Test` functions (no `@Suite` structs for now).
- Share deterministic fixtures via `Tests/.../Support` — e.g. `TestCalendar` for
  fixed calendars and `makeDay(_:_:_:)` for building `Day` values. Reuse these
  instead of re-deriving dates inline.
- Domain logic is deterministic: inject `Calendar` and dates explicitly; never
  rely on `Date()` or `Calendar.current` in tests.
