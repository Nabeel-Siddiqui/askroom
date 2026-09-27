defmodule Askroom.Repo.Migrations.AddLastQuestionSubmittedAtToParticipants do
  use Ecto.Migration

  def change do
    alter table(:participants) do
      add :last_question_submitted_at, :utc_datetime
    end
  end
end
