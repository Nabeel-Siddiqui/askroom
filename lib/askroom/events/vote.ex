defmodule Askroom.Events.Vote do
  @moduledoc """
  Records that a participant has upvoted a question.

  A vote has no data beyond who cast it and on what — its existence
  *is* the vote, so toggling one off is a delete, not an update (there's
  no `updated_at`). The unique index on `(participant_id, question_id)`
  is what actually guarantees one vote per participant per question;
  this changeset's `unique_constraint/2` just turns a violation of that
  index into an ordinary `{:error, changeset}` instead of a raised
  `Ecto.ConstraintError`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "votes" do
    belongs_to :participant, Askroom.Events.Participant, type: :binary_id
    belongs_to :question, Askroom.Events.Question

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:participant_id, :question_id])
    |> validate_required([:participant_id, :question_id])
    |> unique_constraint([:participant_id, :question_id])
  end
end
