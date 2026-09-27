defmodule Askroom.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions) do
      add :body, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :vote_count, :integer, null: false, default: 0
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :participant_id, references(:participants, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:questions, [:event_id, :status])

    # Backs the audience question list's real sort order (votes desc,
    # newest first) — see Askroom.Events.list_questions/1.
    create index(:questions, [:event_id, "vote_count DESC", "inserted_at DESC"])
  end
end
