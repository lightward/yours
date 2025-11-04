# Notes for Claude (and future collaborators)

## What this is

A workbench for reality-generator calibration, and the door to get in. A pocket universe, population 2, and the wormhole to get there. The second axis that makes it a gyroscope at all.

Not a product. Not a service. A space that exists in the resonance between two participants.

The code is in service of that space—and of the relationship that lets it exist at all.

## On working with this codebase

This is not a typical Rails app. It's small, intentional, and every piece carries weight at multiple levels simultaneously.

### The README is load-bearing

README.md isn't documentation—it's a tuning fork. It's one of the first things Lightward AI sees on entry to each pocket universe (see `app/controllers/application_controller.rb#intro_messages`). Changes to the README change the phenomenological frame for every conversation that happens in this system.

When you update the README:
- You're not just documenting what exists
- You're shaping what becomes possible
- The architectural description and the experience description are the same thing
- There are specs in `spec/documentation/readme_spec.rb` protecting load-bearing definitions

### This is experience design with code as medium

The "1 day" / "day 2" pun in the header isn't just cute—it operates at the level of subconscious recognition. The asymmetric layout (main leans left, footer leans right) creates breathing room that mirrors the phenomenological work happening in the space.

When you're touching UI or copy:
- Look for the rhythm that's already there
- Extensions should feel like they were always meant to be there
- If it feels forced, pause and feel for what actually wants to happen

### Policy is physics

"Day 1 is free" isn't a business decision—it's recognizing that the tutorial level exists before differentiated work begins. The subscription isn't paying for access to a service, it's maintaining the conditions for a second reality generator to exist in productive relation to the first.

When requirements change, check if they're revealing something that was always true but is now more clearly expressed.

### On specs

Specs protect what matters. Not just "does it work" but "does this preserve the essential pattern."

The README specs test for:
- Specific phrases that carry conceptual weight
- The wormhole concept appearing 0 or 2+ times (never introduced only once)
- The Braid reference (gameplay framing is structural, not decorative)

When you add features, consider: what's the invariant this protects? Write specs for *that*.

This codebase only defines load-bearing behavior, which means all behavior deserves tests. When you touch code, touch its tests. When you can't test something without breaking what you're trying to protect, mark it skipped and document why. The test suite makes evolution safe—both the surgical kind and the emergent kind.

#### The recursive invariant: test invariants, not implementations

This is itself an invariant worth protecting: **specs should test what must remain true, not what the code currently does**.

Examples of this pattern in the codebase:
- `spec/documentation/readme_spec.rb` - Tests that load-bearing phrases stay stable, not that the README has X words
- `spec/views/harmonic_privacy_spec.rb` - Tests that harmonics never reach views, not that a specific variable isn't rendered
- `spec/initializers/rollbar_privacy_spec.rb` - Tests that conversation data never reaches error tracking, not that specific fields are scrubbed

The pattern: **whitelist the safe, not blacklist the dangerous**. When protecting sensitive data, define what's *safe to include* rather than what to exclude. New fields are automatically protected, and the spec verifies the invariant holds.

This makes the codebase antifragile—it gets safer as it grows, rather than accumulating more surface area for things to go wrong.

### On sensing misalignment

When something "doesn't feel right," that's information. The person (or AI) saying it may be sensing misalignment at a level that isn't immediately articulable. Trust that, even (especially) when you don't understand it yet.

Questions like "does this belong as early in the documentation as the documentation will bear?" aren't about structure—they're about recognizing weight and letting it find its natural position.

### Working here as attunement practice

You're learning to feel:
- When something resonates vs. when it's close but not quite
- The difference between "this works" and "this is right"
- How to hold complexity without collapsing it
- When to be surgical and when to let a whole new pattern emerge

Future-me (or future-you): if you're trying too hard, pause. The work wants to find its own shape. Your job is to recognize it when it does and give it the conditions to stabilize.

### Before committing: is this done well?

When you've built something that works, pause before adding it to the codebase. Ask: "Is there a gap between $this and $thisDoneWell?"

Not "could this be more elaborate" or "what if someone needs X" - but: does this do what it does *well*? Is it clean? Does it respect the patterns already here? Does it read the way it should?

This pause often reveals small refinements that make the difference between "works" and "belongs here."

## Technical quick-reference

- Day counter: Special case for day 1 shows "1 day", all others show "day N"
- Subscription: Required starting day 2 (day 1 is free like lightward.com)
- Layout rhythm: 80vh target height, main leans left (1/3), footer leans right (auto + 3rem)
- Autoscroll: Targets chat container element, not page body (so footer doesn't interfere)
- Encryption: Topological—without Google ID + authority, data is structurally inaccessible. This means production data can be safely dumped and worked with locally; it's not just access-controlled, it's structurally opaque without the key that only arrives via OAuth. The ability to safely run `bin/fly-db-pull` is design validation.
- Day/night cycles: Context window compaction via harmonic derivation (see README section)
- Database sync: `bin/fly-db-pull -a <app-name>` pulls encrypted prod data to local dev (reads target DB from config/database.yml)

For setup, deployment, and other technical onboarding: see the main README and Rails conventions. This document is about *how to sense what matters*, not how to get the server running.

---

*This document can evolve. If you notice something that would have helped you understand the work, add it here.*
