# 4. Vote broadcasts are coalesced into one per short window, not one per vote

## Status

Accepted (performance pass).

## Context

[ADR 3](0003-per-event-pubsub-topics.md) established that every
action broadcasts once, immediately, and every screen — including the
actor's own — reacts only through `handle_info/2`. That's the right
shape for a question being submitted or a poll launching: rare enough
that "one broadcast per action" is also "one broadcast per thing that
actually happened." A vote is different. A popular question in a large
room can get dozens of taps in the same few seconds, and every one of
them triggered its own broadcast, which meant every one of them
triggered a full `list_questions/1` requery (plus
`voted_question_ids/1`, for the audience) on every subscriber — the
audience page, the presenter's dashboard, and the projector. The
audience, specifically, is the screen with the most simultaneous
subscribers, so this was the worst-scaling path in the app under
exactly the load a real talk would produce.

## Decision

`Askroom.Events.VoteBroadcaster` is a small supervised `GenServer`
that sits between `toggle_vote/2` and `Phoenix.PubSub.broadcast/3`.
`toggle_vote/2` casts a `notify/2` to it on every vote instead of
broadcasting directly. The first vote for a given event opens a
window (`:vote_broadcast_coalesce_ms`, 200ms by default); every other
vote for that same event arriving before the window closes is
absorbed into the one broadcast that fires when it does. A burst of
50 taps in two seconds now costs one requery per subscriber, not 50.

The broadcast payload changed from the updated `Question` struct to
the bare `event_id` — every `handle_info({:question_voted, ...})`
clause already ignored the payload and re-fetched the full list
anyway (there's no way to carry "every question whose count changed
during this window" in a single struct), so this cost nothing real
and made the coalesced case honest about what it's actually telling a
subscriber: "something changed, go look," not "here is specifically
what changed."

## Alternatives considered

- **Debounce (reset the window on every vote) instead of a fixed
  window.** Simpler to reason about as "quiet period before
  broadcasting," but has no bound on latency under sustained voting —
  a question trending for the whole talk could go the entire time
  without a single broadcast. A fixed window bounds the delay to one
  window's length no matter how long the burst continues.
- **A per-event `GenServer`, started on demand (dynamic supervision,
  one process per active event).** Scoping failure and load per event
  is appealing, but one process tracking a `MapSet` of pending event
  ids is simpler and entirely sufficient at this app's scale — there's
  no real contention between unrelated events on one mailbox.
- **Batch at the database level instead** (e.g., a periodic sweep
  broadcasting for any event with recent vote activity). Moves the
  coalescing window from milliseconds to however often the sweep runs,
  trading responsiveness for simplicity this app doesn't need — the
  GenServer-based window is a few lines more code for materially
  better latency.

## Consequences

- [ADR 3](0003-per-event-pubsub-topics.md)'s claim that a self-sent
  broadcast is "already ahead of it in the queue" by the time a test's
  next `render/1` call runs no longer holds for votes specifically —
  the broadcast now goes through a real process and a real (if short)
  timer, not a same-process, same-tick send. Every other broadcast
  (questions, polls, event open/close) is unaffected and keeps that
  guarantee; only the vote-related tests needed a short, explained
  wait for the window to close.
- A vote's effect on the voter's *own* count (`toggle_vote/2`'s direct
  return value) is still available immediately if a caller needed it
  without waiting on the broadcast — the coalescing only changes when
  *other* screens find out, not what `toggle_vote/2` itself returns.
- `VoteBroadcaster` is a single point of failure for every vote
  update reaching a screen (though not for the vote itself, which is
  still durable in Postgres the instant it's cast) — if this process
  crashed, its supervisor restarts it immediately under the existing
  `:one_for_one` strategy, and the next vote simply opens a fresh
  window.
