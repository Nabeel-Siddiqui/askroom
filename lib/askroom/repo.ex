defmodule Askroom.Repo do
  use Ecto.Repo,
    otp_app: :askroom,
    adapter: Ecto.Adapters.Postgres
end
