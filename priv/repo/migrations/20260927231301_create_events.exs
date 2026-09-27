defmodule Askroom.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :join_code, :string, null: false
      add :status, :string, null: false, default: "open"
      add :moderation_enabled, :boolean, null: false, default: false
      add :presenter_id, references(:presenters, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:join_code])
    create index(:events, [:presenter_id])
  end
end
