defmodule Askroom.Events.Poll do
  @moduledoc """
  A single live poll with a fixed set of options, belonging to an event.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "polls" do
    field :question_text, :string
    field :options, {:array, :string}
    field :status, Ecto.Enum, values: [:draft, :live, :closed], default: :draft

    belongs_to :event, Askroom.Events.Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:question_text])
    # Ecto's cast/4 trims each array element by default and silently
    # drops any that come out empty (its `:empty_values` handling isn't
    # just for the field as a whole — it filters list elements too).
    # That would swallow a blank option before validate_options/1 ever
    # saw it, surfacing only as a confusing "too few items" error
    # instead of the specific "blank option" message below. Casting
    # `:options` with empty_values: [] keeps blanks in the list so our
    # own validation is the one that catches them.
    |> cast(attrs, [:options], empty_values: [])
    |> validate_required([:question_text, :options])
    |> validate_length(:question_text, min: 1, max: 280)
    |> validate_length(:options, min: 2, max: 8)
    |> validate_options()
  end

  @doc false
  def status_changeset(poll, status) when status in [:draft, :live, :closed] do
    change(poll, status: status)
  end

  defp validate_options(changeset) do
    validate_change(changeset, :options, fn :options, options ->
      trimmed = Enum.map(options, &String.trim/1)

      cond do
        Enum.any?(trimmed, &(&1 == "")) ->
          [options: "can't include a blank option"]

        length(Enum.uniq(trimmed)) != length(trimmed) ->
          [options: "can't include duplicate options"]

        true ->
          []
      end
    end)
  end
end
