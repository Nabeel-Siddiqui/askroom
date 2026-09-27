defmodule Askroom.Repo.Migrations.CreatePollAnswers do
  use Ecto.Migration

  def change do
    create table(:poll_answers) do
      add :option, :string, null: false

      add :participant_id, references(:participants, type: :binary_id, on_delete: :delete_all),
        null: false

      add :poll_id, references(:polls, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # One answer per participant per poll — database-enforced, same
    # reasoning as votes (ADR 2).
    create unique_index(:poll_answers, [:participant_id, :poll_id])
    create index(:poll_answers, [:poll_id])
  end
end
