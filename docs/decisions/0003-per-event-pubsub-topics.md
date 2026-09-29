# 3. One PubSub topic per event, and every screen — including the actor's own — reacts through it

## Status

Accepted (Phase 2–3).

## Context

A question submitted, a vote cast, a poll launched, an event closed:
each of these has to reach every relevant screen live, meaning every
other participant's phone, the presenter's dashboard, and a projector
on the wall. Two things need deciding. First, how broadcasts are
scoped, so Event A's audience never sees Event B's traffic. Second, and
less obviously, whose screen updates from which code path. Does the
person who *took* the action update their own screen differently than
everyone who's just watching?

## Decision

Every event gets exactly one `Phoenix.PubSub` topic, `"event:<id>"`,
built by one private function (`Askroom.Events.topic/1`) that every
broadcast and every subscription goes through: `Events.subscribe/1` for
LiveViews, and `Events.presence_topic/1` (the *same* string) for
`Phoenix.Presence` tracking, so a presenter's dashboard gets Presence's
own `"presence_diff"` broadcasts on the subscription it already has,
with no second topic to track separately.

The more consequential half of the decision is what `handle_event/3`
does *not* do. In every LiveView (`AudienceLive`, `PresenterLive.Show`)
it only ever calls into `Askroom.Events`; it never touches a stream or
another assign directly. The one place `:questions`, `:current_poll`,
`:voted_question_ids`, and friends actually change is `handle_info/2`,
reacting to the broadcast that action itself triggered. A participant
who casts a vote sees their own screen update because they're
subscribed to the same topic as everyone else, not because
`handle_event/3` special-cased "it was me this time."

## Consequences

- "What does this participant see" is defined exactly once, in the
  `handle_info/2` clauses, regardless of whether the underlying change
  came from this browser tab or someone else's. There's no second,
  parallel "optimistic local update" code path to keep in sync with the
  broadcast-driven one, and no risk of the two disagreeing.
- There's a real, sharp edge this creates in tests: `render_click/1` and
  `render_submit/1` only return the HTML from their own
  `handle_event/3`'s synchronous reply. They don't wait for that same
  process's own subsequently-queued `handle_info/2` to run. A test that
  asserts on a click's own return value will miss the update; a
  following, separate `render/1` call catches it, because by the time
  it reaches the process's mailbox, the self-sent broadcast is already
  ahead of it in the queue. It's worth understanding this once as an
  accurate reflection of the real architecture, rather than treating it
  as a trap to keep re-discovering.
- Draft polls and brand-new events are the deliberate exceptions.
  Nothing else can see them yet, so there's nothing to broadcast, and
  their `handle_event/3` clauses update assigns directly. It's the one
  place this app's LiveViews touch their own state outside
  `handle_info/2`, and it stays consistent because the same rule is
  being applied both times: broadcast only when someone else needs to
  know.
- Topic scoping by event id means Event A's broadcasts are structurally
  invisible to Event B's subscribers. There's no filtering-by-event-id
  logic to get right or forget inside a handler, because the messages
  never arrive in the first place.
