defmodule Askroom.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    # A UUID primary key, not a sequential integer, is what actually gets
    # stored in the audience member's browser session — see
    # Askroom.Events.Participant's moduledoc for why that matters.
    create table(:participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string
      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:participants, [:event_id])
  end
end
