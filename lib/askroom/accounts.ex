defmodule Askroom.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Askroom.Repo

  alias Askroom.Accounts.{Presenter, PresenterNotifier, PresenterToken}

  ## Database getters

  @doc """
  Gets a presenter by email.

  ## Examples

      iex> get_presenter_by_email("foo@example.com")
      %Presenter{}

      iex> get_presenter_by_email("unknown@example.com")
      nil

  """
  @spec get_presenter_by_email(String.t()) :: Presenter.t() | nil
  def get_presenter_by_email(email) when is_binary(email) do
    Repo.get_by(Presenter, email: email)
  end

  @doc """
  Gets a presenter by email and password.

  ## Examples

      iex> get_presenter_by_email_and_password("foo@example.com", "correct_password")
      %Presenter{}

      iex> get_presenter_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_presenter_by_email_and_password(String.t(), String.t()) :: Presenter.t() | nil
  def get_presenter_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    presenter = Repo.get_by(Presenter, email: email)
    if Presenter.valid_password?(presenter, password), do: presenter
  end

  @doc """
  Gets a single presenter.

  Raises `Ecto.NoResultsError` if the Presenter does not exist.

  ## Examples

      iex> get_presenter!(123)
      %Presenter{}

      iex> get_presenter!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_presenter!(term()) :: Presenter.t()
  def get_presenter!(id), do: Repo.get!(Presenter, id)

  ## Presenter registration

  @doc """
  Registers a presenter.

  ## Examples

      iex> register_presenter(%{field: value})
      {:ok, %Presenter{}}

      iex> register_presenter(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_presenter(map()) :: {:ok, Presenter.t()} | {:error, Ecto.Changeset.t()}
  def register_presenter(attrs) do
    %Presenter{}
    |> Presenter.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking presenter changes.

  ## Examples

      iex> change_presenter_registration(presenter)
      %Ecto.Changeset{data: %Presenter{}}

  """
  @spec change_presenter_registration(Presenter.t(), map()) :: Ecto.Changeset.t()
  def change_presenter_registration(%Presenter{} = presenter, attrs \\ %{}) do
    Presenter.registration_changeset(presenter, attrs,
      hash_password: false,
      validate_email: false
    )
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the presenter email.

  ## Examples

      iex> change_presenter_email(presenter)
      %Ecto.Changeset{data: %Presenter{}}

  """
  @spec change_presenter_email(Presenter.t(), map()) :: Ecto.Changeset.t()
  def change_presenter_email(presenter, attrs \\ %{}) do
    Presenter.email_changeset(presenter, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_presenter_email(presenter, "valid password", %{email: ...})
      {:ok, %Presenter{}}

      iex> apply_presenter_email(presenter, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  @spec apply_presenter_email(Presenter.t(), String.t(), map()) ::
          {:ok, Presenter.t()} | {:error, Ecto.Changeset.t()}
  def apply_presenter_email(presenter, password, attrs) do
    presenter
    |> Presenter.email_changeset(attrs)
    |> Presenter.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the presenter email using the given token.

  If the token matches, the presenter email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  @spec update_presenter_email(Presenter.t(), String.t()) :: :ok | :error
  def update_presenter_email(presenter, token) do
    context = "change:#{presenter.email}"

    with {:ok, query} <- PresenterToken.verify_change_email_token_query(token, context),
         %PresenterToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(presenter_email_multi(presenter, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp presenter_email_multi(presenter, email, context) do
    changeset =
      presenter
      |> Presenter.email_changeset(%{email: email})
      |> Presenter.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:presenter, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      PresenterToken.by_presenter_and_contexts_query(presenter, [context])
    )
  end

  @doc ~S"""
  Delivers the update email instructions to the given presenter.

  ## Examples

      iex> deliver_presenter_update_email_instructions(presenter, current_email, &url(~p"/presenters/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_presenter_update_email_instructions(
          Presenter.t(),
          String.t(),
          (String.t() -> String.t())
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_presenter_update_email_instructions(
        %Presenter{} = presenter,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, presenter_token} =
      PresenterToken.build_email_token(presenter, "change:#{current_email}")

    Repo.insert!(presenter_token)

    PresenterNotifier.deliver_update_email_instructions(
      presenter,
      update_email_url_fun.(encoded_token)
    )
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the presenter password.

  ## Examples

      iex> change_presenter_password(presenter)
      %Ecto.Changeset{data: %Presenter{}}

  """
  @spec change_presenter_password(Presenter.t(), map()) :: Ecto.Changeset.t()
  def change_presenter_password(presenter, attrs \\ %{}) do
    Presenter.password_changeset(presenter, attrs, hash_password: false)
  end

  @doc """
  Updates the presenter password.

  ## Examples

      iex> update_presenter_password(presenter, "valid password", %{password: ...})
      {:ok, %Presenter{}}

      iex> update_presenter_password(presenter, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_presenter_password(Presenter.t(), String.t(), map()) ::
          {:ok, Presenter.t()} | {:error, Ecto.Changeset.t()}
  def update_presenter_password(presenter, password, attrs) do
    changeset =
      presenter
      |> Presenter.password_changeset(attrs)
      |> Presenter.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:presenter, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      PresenterToken.by_presenter_and_contexts_query(presenter, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{presenter: presenter}} -> {:ok, presenter}
      {:error, :presenter, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_presenter_session_token(Presenter.t()) :: binary()
  def generate_presenter_session_token(presenter) do
    {token, presenter_token} = PresenterToken.build_session_token(presenter)
    Repo.insert!(presenter_token)
    token
  end

  @doc """
  Gets the presenter with the given signed token.
  """
  @spec get_presenter_by_session_token(binary()) :: Presenter.t() | nil
  def get_presenter_by_session_token(token) do
    {:ok, query} = PresenterToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_presenter_session_token(binary()) :: :ok
  def delete_presenter_session_token(token) do
    Repo.delete_all(PresenterToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given presenter.

  ## Examples

      iex> deliver_presenter_confirmation_instructions(presenter, &url(~p"/presenters/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_presenter_confirmation_instructions(confirmed_presenter, &url(~p"/presenters/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  @spec deliver_presenter_confirmation_instructions(Presenter.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()} | {:error, :already_confirmed}
  def deliver_presenter_confirmation_instructions(%Presenter{} = presenter, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if presenter.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, presenter_token} = PresenterToken.build_email_token(presenter, "confirm")
      Repo.insert!(presenter_token)

      PresenterNotifier.deliver_confirmation_instructions(
        presenter,
        confirmation_url_fun.(encoded_token)
      )
    end
  end

  @doc """
  Confirms a presenter by the given token.

  If the token matches, the presenter account is marked as confirmed
  and the token is deleted.
  """
  @spec confirm_presenter(binary()) :: {:ok, Presenter.t()} | :error
  def confirm_presenter(token) do
    with {:ok, query} <- PresenterToken.verify_email_token_query(token, "confirm"),
         %Presenter{} = presenter <- Repo.one(query),
         {:ok, %{presenter: presenter}} <- Repo.transaction(confirm_presenter_multi(presenter)) do
      {:ok, presenter}
    else
      _ -> :error
    end
  end

  defp confirm_presenter_multi(presenter) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:presenter, Presenter.confirm_changeset(presenter))
    |> Ecto.Multi.delete_all(
      :tokens,
      PresenterToken.by_presenter_and_contexts_query(presenter, ["confirm"])
    )
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given presenter.

  ## Examples

      iex> deliver_presenter_reset_password_instructions(presenter, &url(~p"/presenters/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_presenter_reset_password_instructions(Presenter.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_presenter_reset_password_instructions(
        %Presenter{} = presenter,
        reset_password_url_fun
      )
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, presenter_token} =
      PresenterToken.build_email_token(presenter, "reset_password")

    Repo.insert!(presenter_token)

    PresenterNotifier.deliver_reset_password_instructions(
      presenter,
      reset_password_url_fun.(encoded_token)
    )
  end

  @doc """
  Gets the presenter by reset password token.

  ## Examples

      iex> get_presenter_by_reset_password_token("validtoken")
      %Presenter{}

      iex> get_presenter_by_reset_password_token("invalidtoken")
      nil

  """
  @spec get_presenter_by_reset_password_token(binary()) :: Presenter.t() | nil
  def get_presenter_by_reset_password_token(token) do
    with {:ok, query} <- PresenterToken.verify_email_token_query(token, "reset_password"),
         %Presenter{} = presenter <- Repo.one(query) do
      presenter
    else
      _ -> nil
    end
  end

  @doc """
  Resets the presenter password.

  ## Examples

      iex> reset_presenter_password(presenter, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %Presenter{}}

      iex> reset_presenter_password(presenter, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  @spec reset_presenter_password(Presenter.t(), map()) ::
          {:ok, Presenter.t()} | {:error, Ecto.Changeset.t()}
  def reset_presenter_password(presenter, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:presenter, Presenter.password_changeset(presenter, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      PresenterToken.by_presenter_and_contexts_query(presenter, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{presenter: presenter}} -> {:ok, presenter}
      {:error, :presenter, changeset, _} -> {:error, changeset}
    end
  end
end
