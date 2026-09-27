defmodule Askroom.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating entities via the
  `Askroom.Events` context.
  """

  alias Askroom.Events

  import Askroom.AccountsFixtures

  def valid_event_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{title: "A great talk"})
  end

  @doc "Creates an event, defaulting to a fresh presenter if one isn't given."
  def event_fixture(attrs \\ %{}, presenter \\ nil) do
    presenter = presenter || presenter_fixture()

    {:ok, event} = Events.create_event(presenter, valid_event_attributes(attrs))
    event
  end

  def participant_fixture(event, attrs \\ %{}) do
    {:ok, participant} = Events.create_participant(event, attrs)
    participant
  end

  def valid_question_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{body: "What's the roadmap for this?"})
  end

  def question_fixture(event, participant, attrs \\ %{}) do
    {:ok, question} = Events.create_question(event, participant, valid_question_attributes(attrs))
    question
  end

  def valid_poll_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{question_text: "Which feature next?", options: ["Search", "Exports"]})
  end

  def poll_fixture(presenter, event, attrs \\ %{}) do
    {:ok, poll} = Events.create_poll(presenter, event, valid_poll_attributes(attrs))
    poll
  end
end
