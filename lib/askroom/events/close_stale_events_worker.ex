defmodule Askroom.Events.CloseStaleEventsWorker do
  @moduledoc """
  Nightly cron job (via `Oban.Plugins.Cron`) that closes any event still
  open more than 24 hours after it started — a presenter who forgot to
  close a talk shouldn't leave it silently accepting questions and votes
  from anyone who still has the link, indefinitely.
  """

  use Oban.Worker, queue: :maintenance

  alias Askroom.Events

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Events.close_stale_events()
    :ok
  end
end
