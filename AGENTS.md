# AGENTS.md

Guidance for agents working in this repository. See `README.md` for project
structure, verification, and formatting commands.

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
