defmodule Askroom.Events.Event do
  @moduledoc """
  A single talk or meeting. Owned by exactly one presenter; joined by
  anonymous participants via `join_code`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "events" do
    field :title, :string
    field :join_code, :string
    field :status, Ecto.Enum, values: [:open, :closed], default: :open
    field :moderation_enabled, :boolean, default: false

    belongs_to :presenter, Askroom.Accounts.Presenter

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :moderation_enabled])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 200)
  end

  @doc false
  def status_changeset(event, status) when status in [:open, :closed] do
    change(event, status: status)
  end

  @doc """
  Assigns a fresh join code to the changeset. `Askroom.Events.create_event/2`
  retries this (a handful of times, on the rare unique-index collision)
  rather than checking the code's uniqueness up front — a
  check-then-insert would itself be racy against a concurrent request
  generating the same code.
  """
  @spec put_join_code(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def put_join_code(changeset) do
    changeset
    |> put_change(:join_code, generate_join_code())
    |> unique_constraint(:join_code)
  end

  # Excludes 0/O and 1/I — the character pairs people mishear or
  # miswrite most often when a code is read aloud across a room.
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  @doc false
  @spec generate_join_code() :: String.t()
  def generate_join_code do
    for _ <- 1..@code_length, into: "", do: <<Enum.random(@alphabet)>>
  end
end
