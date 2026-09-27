defmodule Askroom.Events.Question do
  @moduledoc """
  A question submitted by a participant, upvoted by others.

  `vote_count` is a denormalized counter cache, not something derived by
  counting `Vote` rows on every read — the whole point is that the
  audience list query (sorted by votes) never has to join or aggregate
  over `votes` to render. See `Askroom.Events.vote/2` for how it's kept
  correct under concurrent upvotes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "questions" do
    field :body, :string
    field :status, Ecto.Enum, values: [:pending, :visible, :answered, :hidden], default: :pending
    field :vote_count, :integer, default: 0

    belongs_to :event, Askroom.Events.Event
    belongs_to :participant, Askroom.Events.Participant, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 280)
  end

  @doc false
  def status_changeset(question, status)
      when status in [:pending, :visible, :answered, :hidden] do
    change(question, status: status)
  end
end
