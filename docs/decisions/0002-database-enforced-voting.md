# 2. Database-enforced voting rules, with atomic counters

## Status

Accepted (Phase 2).

## Context

Two things have to be true about voting no matter how many participants
are doing it at the same moment: a participant can upvote a given
question at most once, and `Question.vote_count` has to be the true
count, not an approximation that drifts under concurrent load. Once
there's a `MonitorWorker`-style thing per browser tab — many independent
LiveView processes, each able to write at any moment — "check, then
write" in application code is a race condition waiting to happen, not a
hypothetical one.

## Decision

Two mechanisms, one each for the two guarantees:

1. A **unique index** on `votes(participant_id, question_id)`. Casting
   a vote is a plain insert; if a participant already has one, the
   insert fails the constraint. The database rejects the duplicate, not
   a `Repo.get_by` check in `Events.toggle_vote/2` racing against
   another process's insert.
2. `vote_count` is adjusted with `Repo.update_all/2`'s `inc:` option — a
   single `UPDATE questions SET vote_count = vote_count + 1 WHERE id =
   ...` statement. There's no read step in Elixir at all: the increment
   happens inside one SQL statement that Postgres itself executes
   atomically. The `Vote` row change and the counter adjustment run
   inside the same `Repo.transaction/1`, so a crash between the two can
   never leave the count and the actual number of `Vote` rows
   disagreeing.

`toggle_vote/2` decides which direction to go (cast or retract) by
checking, *inside that same transaction*, whether a `Vote` row already
exists — not from anything the caller believes the state to be. That's
what makes it safe to call from a plain toggle button with no separate
"am I already voted" round-trip first.

## Consequences

- The property is testable, and tested, exactly as strongly as it's
  claimed: 25 concurrent `Task`s voting on the same question converge on
  `vote_count == 25`, every time, not "usually." A read-modify-write
  version of the same test (`count = get(); update(count + 1)`) would
  have been flaky under exactly this load — the bug this design
  prevents is a real one, not a defensive-programming reflex.
- Both guarantees hold regardless of which process, which node, or how
  many of either are involved — they're properties of the data, not of
  any particular code path that happens to touch it carefully. Someone
  extending this app later can't accidentally reintroduce the race by
  writing a new function that inserts a `Vote` a different way; the
  unique index defends the invariant no matter what the caller does.
- The cost is real but small: an `UPDATE ... WHERE` and a unique
  constraint check on the hot path of every vote, instead of a cheaper
  (but wrong) in-memory increment. At this app's actual scale — one
  talk's audience voting on a handful of questions — that cost is
  immaterial; the ["what I'd do next"](../../README.md#what-id-do-next)
  section is where a much larger audience's implications get discussed.
