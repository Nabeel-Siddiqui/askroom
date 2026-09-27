defmodule Askroom.Events.Participant do
  @moduledoc """
  An anonymous member of an event's audience.

  A participant never has an account — no email, no password, nothing
  `Askroom.Accounts` knows about. The only thing that identifies them
  across page loads is this row's id, which is why it's minted as a
  UUID rather than the default sequential integer: it's the exact value
  stored in the audience member's browser session (see
  `AskroomWeb.ParticipantAuth`), so refreshing the page — or coming back
  the next day — resumes the same identity and the same votes. A
  sequential integer would work as a session value too, but a random
  UUID means a participant's id can't be predicted or enumerated by
  incrementing it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "participants" do
    field :display_name, :string

    belongs_to :event, Askroom.Events.Event

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: 50)
  end
end
