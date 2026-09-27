defmodule Askroom.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Askroom.Accounts` context.
  """

  def unique_presenter_email, do: "presenter#{System.unique_integer()}@example.com"
  def valid_presenter_password, do: "hello world!"

  def valid_presenter_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_presenter_email(),
      password: valid_presenter_password()
    })
  end

  def presenter_fixture(attrs \\ %{}) do
    {:ok, presenter} =
      attrs
      |> valid_presenter_attributes()
      |> Askroom.Accounts.register_presenter()

    presenter
  end

  def extract_presenter_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
