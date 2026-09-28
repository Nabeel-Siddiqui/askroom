defmodule AskroomWeb.Presence do
  @moduledoc """
  Tracks which participants are currently on an event's live page, for
  the presenter's "people in the room" count.

  Only audience participants are tracked (`AskroomWeb.AudienceLive`) —
  the presenter's own dashboard just reads the count via
  `Phoenix.Presence.list/1`, it doesn't add itself to it. "How many
  people have joined my event" is the question this answers; a
  presenter looking at their own dashboard isn't part of that audience.
  """

  use Phoenix.Presence,
    otp_app: :askroom,
    pubsub_server: Askroom.PubSub
end
