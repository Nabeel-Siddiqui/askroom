defmodule Askroom.AccountsTest do
  use Askroom.DataCase

  alias Askroom.Accounts

  import Askroom.AccountsFixtures
  alias Askroom.Accounts.{Presenter, PresenterToken}

  describe "get_presenter_by_email/1" do
    test "does not return the presenter if the email does not exist" do
      refute Accounts.get_presenter_by_email("unknown@example.com")
    end

    test "returns the presenter if the email exists" do
      %{id: id} = presenter = presenter_fixture()
      assert %Presenter{id: ^id} = Accounts.get_presenter_by_email(presenter.email)
    end
  end

  describe "get_presenter_by_email_and_password/2" do
    test "does not return the presenter if the email does not exist" do
      refute Accounts.get_presenter_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the presenter if the password is not valid" do
      presenter = presenter_fixture()
      refute Accounts.get_presenter_by_email_and_password(presenter.email, "invalid")
    end

    test "returns the presenter if the email and password are valid" do
      %{id: id} = presenter = presenter_fixture()

      assert %Presenter{id: ^id} =
               Accounts.get_presenter_by_email_and_password(
                 presenter.email,
                 valid_presenter_password()
               )
    end
  end

  describe "get_presenter!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_presenter!(-1)
      end
    end

    test "returns the presenter with the given id" do
      %{id: id} = presenter = presenter_fixture()
      assert %Presenter{id: ^id} = Accounts.get_presenter!(presenter.id)
    end
  end

  describe "register_presenter/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_presenter(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} =
        Accounts.register_presenter(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_presenter(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = presenter_fixture()
      {:error, changeset} = Accounts.register_presenter(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_presenter(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers presenters with a hashed password" do
      email = unique_presenter_email()
      {:ok, presenter} = Accounts.register_presenter(valid_presenter_attributes(email: email))
      assert presenter.email == email
      assert is_binary(presenter.hashed_password)
      assert is_nil(presenter.confirmed_at)
      assert is_nil(presenter.password)
    end
  end

  describe "change_presenter_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_presenter_registration(%Presenter{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_presenter_email()
      password = valid_presenter_password()

      changeset =
        Accounts.change_presenter_registration(
          %Presenter{},
          valid_presenter_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_presenter_email/2" do
    test "returns a presenter changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_presenter_email(%Presenter{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_presenter_email/3" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "requires email to change", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.apply_presenter_email(presenter, valid_presenter_password(), %{})

      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.apply_presenter_email(presenter, valid_presenter_password(), %{
          email: "not valid"
        })

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{presenter: presenter} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_presenter_email(presenter, valid_presenter_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{presenter: presenter} do
      %{email: email} = presenter_fixture()
      password = valid_presenter_password()

      {:error, changeset} = Accounts.apply_presenter_email(presenter, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.apply_presenter_email(presenter, "invalid", %{email: unique_presenter_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{presenter: presenter} do
      email = unique_presenter_email()

      {:ok, presenter} =
        Accounts.apply_presenter_email(presenter, valid_presenter_password(), %{email: email})

      assert presenter.email == email
      assert Accounts.get_presenter!(presenter.id).email != email
    end
  end

  describe "deliver_presenter_update_email_instructions/3" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "sends token through notification", %{presenter: presenter} do
      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_update_email_instructions(
            presenter,
            "current@example.com",
            url
          )
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert presenter_token = Repo.get_by(PresenterToken, token: :crypto.hash(:sha256, token))
      assert presenter_token.presenter_id == presenter.id
      assert presenter_token.sent_to == presenter.email
      assert presenter_token.context == "change:current@example.com"
    end
  end

  describe "update_presenter_email/2" do
    setup do
      presenter = presenter_fixture()
      email = unique_presenter_email()

      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_update_email_instructions(
            %{presenter | email: email},
            presenter.email,
            url
          )
        end)

      %{presenter: presenter, token: token, email: email}
    end

    test "updates the email with a valid token", %{
      presenter: presenter,
      token: token,
      email: email
    } do
      assert Accounts.update_presenter_email(presenter, token) == :ok
      changed_presenter = Repo.get!(Presenter, presenter.id)
      assert changed_presenter.email != presenter.email
      assert changed_presenter.email == email
      assert changed_presenter.confirmed_at
      assert changed_presenter.confirmed_at != presenter.confirmed_at
      refute Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not update email with invalid token", %{presenter: presenter} do
      assert Accounts.update_presenter_email(presenter, "oops") == :error
      assert Repo.get!(Presenter, presenter.id).email == presenter.email
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not update email if presenter email changed", %{presenter: presenter, token: token} do
      assert Accounts.update_presenter_email(%{presenter | email: "current@example.com"}, token) ==
               :error

      assert Repo.get!(Presenter, presenter.id).email == presenter.email
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not update email if token expired", %{presenter: presenter, token: token} do
      {1, nil} = Repo.update_all(PresenterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_presenter_email(presenter, token) == :error
      assert Repo.get!(Presenter, presenter.id).email == presenter.email
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end
  end

  describe "change_presenter_password/2" do
    test "returns a presenter changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_presenter_password(%Presenter{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_presenter_password(%Presenter{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_presenter_password/3" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "validates password", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.update_presenter_password(presenter, valid_presenter_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{presenter: presenter} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_presenter_password(presenter, valid_presenter_password(), %{
          password: too_long
        })

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.update_presenter_password(presenter, "invalid", %{
          password: valid_presenter_password()
        })

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{presenter: presenter} do
      {:ok, presenter} =
        Accounts.update_presenter_password(presenter, valid_presenter_password(), %{
          password: "new valid password"
        })

      assert is_nil(presenter.password)
      assert Accounts.get_presenter_by_email_and_password(presenter.email, "new valid password")
    end

    test "deletes all tokens for the given presenter", %{presenter: presenter} do
      _ = Accounts.generate_presenter_session_token(presenter)

      {:ok, _} =
        Accounts.update_presenter_password(presenter, valid_presenter_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end
  end

  describe "generate_presenter_session_token/1" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "generates a token", %{presenter: presenter} do
      token = Accounts.generate_presenter_session_token(presenter)
      assert presenter_token = Repo.get_by(PresenterToken, token: token)
      assert presenter_token.context == "session"

      # Creating the same token for another presenter should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%PresenterToken{
          token: presenter_token.token,
          presenter_id: presenter_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_presenter_by_session_token/1" do
    setup do
      presenter = presenter_fixture()
      token = Accounts.generate_presenter_session_token(presenter)
      %{presenter: presenter, token: token}
    end

    test "returns presenter by token", %{presenter: presenter, token: token} do
      assert session_presenter = Accounts.get_presenter_by_session_token(token)
      assert session_presenter.id == presenter.id
    end

    test "does not return presenter for invalid token" do
      refute Accounts.get_presenter_by_session_token("oops")
    end

    test "does not return presenter for expired token", %{token: token} do
      {1, nil} = Repo.update_all(PresenterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_presenter_by_session_token(token)
    end
  end

  describe "delete_presenter_session_token/1" do
    test "deletes the token" do
      presenter = presenter_fixture()
      token = Accounts.generate_presenter_session_token(presenter)
      assert Accounts.delete_presenter_session_token(token) == :ok
      refute Accounts.get_presenter_by_session_token(token)
    end
  end

  describe "deliver_presenter_confirmation_instructions/2" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "sends token through notification", %{presenter: presenter} do
      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_confirmation_instructions(presenter, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert presenter_token = Repo.get_by(PresenterToken, token: :crypto.hash(:sha256, token))
      assert presenter_token.presenter_id == presenter.id
      assert presenter_token.sent_to == presenter.email
      assert presenter_token.context == "confirm"
    end
  end

  describe "confirm_presenter/1" do
    setup do
      presenter = presenter_fixture()

      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_confirmation_instructions(presenter, url)
        end)

      %{presenter: presenter, token: token}
    end

    test "confirms the email with a valid token", %{presenter: presenter, token: token} do
      assert {:ok, confirmed_presenter} = Accounts.confirm_presenter(token)
      assert confirmed_presenter.confirmed_at
      assert confirmed_presenter.confirmed_at != presenter.confirmed_at
      assert Repo.get!(Presenter, presenter.id).confirmed_at
      refute Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not confirm with invalid token", %{presenter: presenter} do
      assert Accounts.confirm_presenter("oops") == :error
      refute Repo.get!(Presenter, presenter.id).confirmed_at
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not confirm email if token expired", %{presenter: presenter, token: token} do
      {1, nil} = Repo.update_all(PresenterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_presenter(token) == :error
      refute Repo.get!(Presenter, presenter.id).confirmed_at
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end
  end

  describe "deliver_presenter_reset_password_instructions/2" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "sends token through notification", %{presenter: presenter} do
      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_reset_password_instructions(presenter, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert presenter_token = Repo.get_by(PresenterToken, token: :crypto.hash(:sha256, token))
      assert presenter_token.presenter_id == presenter.id
      assert presenter_token.sent_to == presenter.email
      assert presenter_token.context == "reset_password"
    end
  end

  describe "get_presenter_by_reset_password_token/1" do
    setup do
      presenter = presenter_fixture()

      token =
        extract_presenter_token(fn url ->
          Accounts.deliver_presenter_reset_password_instructions(presenter, url)
        end)

      %{presenter: presenter, token: token}
    end

    test "returns the presenter with valid token", %{presenter: %{id: id}, token: token} do
      assert %Presenter{id: ^id} = Accounts.get_presenter_by_reset_password_token(token)
      assert Repo.get_by(PresenterToken, presenter_id: id)
    end

    test "does not return the presenter with invalid token", %{presenter: presenter} do
      refute Accounts.get_presenter_by_reset_password_token("oops")
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end

    test "does not return the presenter if token expired", %{presenter: presenter, token: token} do
      {1, nil} = Repo.update_all(PresenterToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_presenter_by_reset_password_token(token)
      assert Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end
  end

  describe "reset_presenter_password/2" do
    setup do
      %{presenter: presenter_fixture()}
    end

    test "validates password", %{presenter: presenter} do
      {:error, changeset} =
        Accounts.reset_presenter_password(presenter, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{presenter: presenter} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_presenter_password(presenter, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{presenter: presenter} do
      {:ok, updated_presenter} =
        Accounts.reset_presenter_password(presenter, %{password: "new valid password"})

      assert is_nil(updated_presenter.password)
      assert Accounts.get_presenter_by_email_and_password(presenter.email, "new valid password")
    end

    test "deletes all tokens for the given presenter", %{presenter: presenter} do
      _ = Accounts.generate_presenter_session_token(presenter)
      {:ok, _} = Accounts.reset_presenter_password(presenter, %{password: "new valid password"})
      refute Repo.get_by(PresenterToken, presenter_id: presenter.id)
    end
  end

  describe "inspect/2 for the Presenter module" do
    test "does not include password" do
      refute inspect(%Presenter{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
