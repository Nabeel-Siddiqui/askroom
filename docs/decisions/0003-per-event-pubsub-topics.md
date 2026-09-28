# 3. One PubSub topic per event, and every screen — including the actor's own — reacts through it

## Status

Accepted (Phase 2–3).

## Context

A question submitted, a vote cast, a poll launched, an event closed —
each of these has to reach every relevant screen live: every other
participant's phone, the presenter's dashboard, a projector on the
wall. The question is how broadcasts are scoped (so Event A's audience
never sees Event B's traffic) and, less obviously, whose screen updates
from which code path — does the person who *took* the action update
their own screen differently than everyone who's just watching?

## Decision

Every event gets exactly one `Phoenix.PubSub` topic, `"event:<id>"`,
built by one private function (`Askroom.Events.topic/1`) that every
broadcast and every subscription goes through — `Events.subscribe/1`
for LiveViews, `Events.presence_topic/1` (the *same* string) for
`Phoenix.Presence` tracking, so a presenter's dashboard gets Presence's
own `"presence_diff"` broadcasts on the subscription it already has,
with no second topic to track separately.

The more consequential half of the decision: `handle_event/3` in every
LiveView (`AudienceLive`, `PresenterLive.Show`) only ever calls into
`Askroom.Events` — it never touches a stream or another assign
directly. The one place `:questions`, `:current_poll`,
`:voted_question_ids`, and friends actually change is `handle_info/2`,
reacting to the broadcast that action itself triggered. A participant
who casts a vote sees their own screen update *because they're
subscribed to the same topic as everyone else*, not because
`handle_event/3` updated their assigns as a special case for "it was me
this time."

## Consequences

- "What does this participant see" is defined exactly once, in the
  `handle_info/2` clauses, regardless of whether the underlying change
  came from this browser tab or someone else's. There's no second,
  parallel "optimistic local update" code path to keep in sync with the
  broadcast-driven one, and no risk of the two disagreeing.
- The real, sharp edge this creates: `render_click/1` and
  `render_submit/1` in tests only return the HTML from their own
  `handle_event/3`'s synchronous reply — they do not wait for that same
  process's own subsequently-queued `handle_info/2` to run. Tests that
  assert on a click's own return value miss the update; a following,
  separate `render/1` call catches it, because by the time it reaches
  the process's mailbox, the self-sent broadcast is already ahead of it
  in the queue. This isn't a testing quirk to work around so much as an
  accurate reflection of the real architecture — worth understanding
  once, not a trap to keep re-discovering.
- Draft polls and brand-new events are the deliberate exceptions:
  nothing else can see them yet, so there's nothing to broadcast, and
  their `handle_event/3` clauses update assigns directly — the one
  place this app's LiveViews *do* touch their own state outside
  `handle_info/2`, and it's consistent precisely because "does anyone
  else need to know" is the rule being applied, not an inconsistency.
- Topic scoping by event id means Event A's broadcasts are structurally
  invisible to Event B's subscribers — there's no filtering-by-event-id
  logic to get right or forget inside a handler, because the messages
  never arrive in the first place.
