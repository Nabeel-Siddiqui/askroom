defmodule Askroom.Events.CloseStaleEventsWorkerTest do
  use Askroom.DataCase, async: true
  use Oban.Testing, repo: Askroom.Repo

  import Askroom.EventsFixtures

  alias Askroom.Events.{CloseStaleEventsWorker, Event}
  alias Askroom.Repo

  test "closes stale events when performed" do
    event = event_fixture()

    timestamp =
      DateTime.utc_now() |> DateTime.add(-25 * 3600, :second) |> DateTime.truncate(:second)

    Event |> where([e], e.id == ^event.id) |> Repo.update_all(set: [inserted_at: timestamp])

    assert :ok = perform_job(CloseStaleEventsWorker, %{})
    assert Repo.reload!(event).status == :closed
  end

  test "is scheduled nightly via Oban.Plugins.Cron" do
    plugins = Application.fetch_env!(:askroom, Oban)[:plugins]
    cron_plugin = Enum.find(plugins, fn {plugin, _opts} -> plugin == Oban.Plugins.Cron end)

    assert {Oban.Plugins.Cron, opts} = cron_plugin
    assert {"0 3 * * *", CloseStaleEventsWorker} in opts[:crontab]
  end
end
