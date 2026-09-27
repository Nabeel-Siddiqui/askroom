# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :askroom,
  ecto_repos: [Askroom.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :askroom, AskroomWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AskroomWeb.ErrorHTML, json: AskroomWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Askroom.PubSub,
  live_view: [signing_salt: "tIZWDhhy"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :askroom, Askroom.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  askroom: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  askroom: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# The "maintenance" queue is for the nightly stale-event cleanup job
# (Phase 4) — kept separate from any future user-triggered queue so a
# burst of one never delays the other.
config :askroom, Oban,
  engine: Oban.Engines.Basic,
  repo: Askroom.Repo,
  queues: [maintenance: 1],
  plugins: [
    # Prunes Oban's own completed/cancelled job rows so oban_jobs doesn't
    # grow forever.
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
