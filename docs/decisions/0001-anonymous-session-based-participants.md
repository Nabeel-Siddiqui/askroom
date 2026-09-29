# 1. Anonymous, session-based participants — no accounts for the audience

## Status

Accepted (Phase 1–2).

## Context

An audience member needs *some* identity. Something has to own their
questions and votes, and something has to stop them from voting twice
on the same question. But making them register an account before they
can ask a question at a talk would kill the entire point of a tool like
this. The audience should be typing a 6-character code and asking a
question within seconds of opening their phone, not filling in an email
and a password first.

## Decision

`Participant` is a real row in the database (`belongs_to :event`,
optional `display_name`), but it's never tied to a login. Its primary
key is a UUID rather than the schema's default sequential integer, and
that UUID is the literal value written into the visitor's browser
session, namespaced per event since a participant only ever belongs to
one (`participant_id_for_event_<id>`). `AskroomWeb.JoinController` mints
one on first visit and reuses it on every later one. Refreshing the
page, or coming back after closing the tab, resumes the same identity,
because it's the session cookie that carries it, not anything typed in.

## Consequences

- Zero-friction joining: entering a code (or opening a `/join/:code`
  link, the kind a QR code on a projector points at) is the entire
  signup flow.
- A UUID instead of a sequential integer means a participant's id can't
  be enumerated by incrementing a number. That's a minor but free
  hardening, since it costs nothing extra to generate one over the
  other.
- The identity is exactly as durable as the browser's cookie jar and
  nothing more. Clear cookies, switch browsers, or borrow someone else's
  phone, and it's a new participant with no memory of previous votes.
  For this app's actual use case, one talk in one sitting, that's
  correct behavior rather than a limitation. Nobody expects their
  upvotes from a conference talk to follow them to a different device
  weeks later.
- Because there's no login, there's no way to prove "this participant
  is the same person as that one" after the fact. A determined person
  could open the join link in a second browser and vote again as a
  second participant. This app accepts that tradeoff deliberately. The
  fairness guarantee (see [ADR 2](0002-database-enforced-voting.md)) is
  "one vote per participant," not "one vote per human," because
  enforcing the latter would mean asking for the accounts this whole
  design exists to avoid.
