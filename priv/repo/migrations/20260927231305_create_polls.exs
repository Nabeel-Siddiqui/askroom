defmodule Askroom.Repo.Migrations.CreatePolls do
  use Ecto.Migration

  def change do
    create table(:polls) do
      add :question_text, :string, null: false
      add :options, {:array, :string}, null: false
      add :status, :string, null: false, default: "draft"
      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:polls, [:event_id])
  end
end
