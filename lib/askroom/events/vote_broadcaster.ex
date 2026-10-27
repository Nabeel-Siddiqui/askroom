defmodule Askroom.Events.VoteBroadcaster do
  @moduledoc """
  Coalesces vote broadcasts for an event. Before this existed, every
  single `toggle_vote/2` call broadcast immediately — fine for one
  talk's audience, but a crowd hammering the upvote button in the
  same few seconds meant one broadcast (and one full requery on every
  subscriber: the audience page, the presenter's dashboard, and the
  projector) per tap. See [ADR 4](../../../docs/decisions/0004-coalesce-vote-broadcasts.md).

  `Events.toggle_vote/2` calls `notify/2` on every vote instead of
  broadcasting directly. This process is the only thing that actually
  calls `Phoenix.PubSub.broadcast/3` for `:question_voted`: the first
  vote for an event opens a window (`:vote_broadcast_coalesce_ms`,
  200ms by default); every other vote for that same event arriving
  before the window closes is absorbed into the one broadcast that
  fires when it does.
  """

  use GenServer

  alias Askroom.Events

  @coalesce_window_ms Application.compile_env(:askroom, :vote_broadcast_coalesce_ms, 200)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Registers a vote on `event_id`. Schedules exactly one broadcast
  within the coalescing window if one isn't already pending for this
  event — a cheap, fire-and-forget cast, so a vote is never slowed
  down waiting on this process.
  """
  @spec notify(GenServer.server(), pos_integer()) :: :ok
  def notify(server \\ __MODULE__, event_id) do
    GenServer.cast(server, {:vote, event_id})
  end

  @doc """
  A no-op round trip, for a test that needs to wait out an
  already-enqueued `notify/2` cast before asserting on its effect —
  the same trick used elsewhere in this series for a GenServer whose
  work happens via message passing.
  """
  @spec sync(GenServer.server()) :: :ok
  def sync(server \\ __MODULE__), do: GenServer.call(server, :sync)

  @impl true
  def init(:ok), do: {:ok, %{pending: MapSet.new()}}

  @impl true
  def handle_cast({:vote, event_id}, %{pending: pending} = state) do
    if MapSet.member?(pending, event_id) do
      {:noreply, state}
    else
      Process.send_after(self(), {:flush, event_id}, @coalesce_window_ms)
      {:noreply, %{state | pending: MapSet.put(pending, event_id)}}
    end
  end

  @impl true
  def handle_info({:flush, event_id}, %{pending: pending} = state) do
    Events.broadcast_question_voted(event_id)
    {:noreply, %{state | pending: MapSet.delete(pending, event_id)}}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}
end
