import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :askroom, Askroom.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "askroom_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :askroom, AskroomWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gKI9okLb2aluMI/GV3Bu8YQKe4k28qZbZEdrhWycGnwDAB2djJOtrEftScEFMNHg",
  server: false

# In test we don't send emails
config :askroom, Askroom.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Oban.Testing's :manual mode — jobs are inserted into the database (so
# uniqueness/argument assertions still work) but never picked up by a
# real queue. Tests trigger perform/1 explicitly via Oban.Testing.
config :askroom, Oban, testing: :manual
