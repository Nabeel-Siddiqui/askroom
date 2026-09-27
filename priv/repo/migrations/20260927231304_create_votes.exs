defmodule Askroom.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :participant_id, references(:participants, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question_id, references(:questions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # The database, not application code, is what actually guarantees "at
    # most one vote per participant per question" — see ADR 2.
    create unique_index(:votes, [:participant_id, :question_id])
    create index(:votes, [:question_id])
  end
end
