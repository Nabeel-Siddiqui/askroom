defmodule Askroom.Repo.Migrations.CreatePresentersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:presenters) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:presenters, [:email])

    create table(:presenters_tokens) do
      add :presenter_id, references(:presenters, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:presenters_tokens, [:presenter_id])
    create unique_index(:presenters_tokens, [:context, :token])
  end
end
