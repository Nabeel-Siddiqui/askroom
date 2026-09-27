defmodule Askroom.Events.PollAnswer do
  @moduledoc """
  Records a participant's chosen option for a poll. Same
  database-enforced one-per-participant guarantee as `Askroom.Events.Vote`,
  via the unique index on `(participant_id, poll_id)`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "poll_answers" do
    field :option, :string

    belongs_to :participant, Askroom.Events.Participant, type: :binary_id
    belongs_to :poll, Askroom.Events.Poll

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(poll_answer, attrs) do
    poll_answer
    |> cast(attrs, [:option, :participant_id, :poll_id])
    |> validate_required([:option, :participant_id, :poll_id])
    |> unique_constraint([:participant_id, :poll_id])
  end
end
