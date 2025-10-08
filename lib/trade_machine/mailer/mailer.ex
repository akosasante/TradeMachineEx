defmodule TradeMachine.Mailer do
  use Swoosh.Mailer, otp_app: :trade_machine
  require Logger

  def send_password_reset_email(user_id, frontend_environment) do
    Logger.info("Sending password reset email",
      user_id: user_id,
      frontend_env: frontend_environment
    )

    case TradeMachine.Data.User.get_by_id_with_password_reset_token(user_id) do
      nil ->
        Logger.error("User not found for ID", user_id: user_id)
        {:error, :user_not_found}

      user ->
        TradeMachine.Mailer.PasswordResetEmail.send(user, frontend_environment)
    end
  end

  def send_registration_email(user_id, frontend_environment) do
    Logger.info("Sending registration email",
      user_id: user_id,
      frontend_env: frontend_environment
    )

    case TradeMachine.Data.User.get_by_id(user_id) do
      nil ->
        Logger.error("User not found for ID", user_id: user_id)
        {:error, :user_not_found}

      user ->
        TradeMachine.Mailer.RegistrationEmail.send(user, frontend_environment)
    end
  end

  def send_test_email(user_id, frontend_environment) do
    Logger.info("Sending test email", user_id: user_id, frontend_env: frontend_environment)

    case TradeMachine.Data.User.get_by_id(user_id) do
      nil ->
        Logger.error("User not found for ID", user_id: user_id)
        {:error, :user_not_found}

      user ->
        TradeMachine.Mailer.TestEmail.send(user, frontend_environment)
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Swoosh.Email

      use Phoenix.Swoosh,
        view: TradeMachine.Mailer.EmailView,
        layout: {TradeMachine.Mailer.LayoutView, :email}

      defp frontend_url(frontend_env = "production"),
        do: Application.get_env(:trade_machine, :frontend_url_production)

      defp frontend_url(frontend_env = "development"),
        do: "http://localhost:3031"

      defp frontend_url(_), do: Application.get_env(:trade_machine, :frontend_url_staging)

      defp process_html(email = %Swoosh.Email{}) do
        email.html_body
        |> Premailex.to_inline_css()
        |> then(&Swoosh.Email.html_body(email, &1))
      end

      defp do_deliver(email = %Swoosh.Email{}),
        do: email |> process_html |> TradeMachine.Mailer.deliver()

      defp do_deliver!(email = %Swoosh.Email{}),
        do: email |> process_html |> TradeMachine.Mailer.deliver!()

      defp from_email do
        Application.get_env(:trade_machine, unquote(__MODULE__))[:from_email]
      end

      defp from_name do
        Application.get_env(:trade_machine, unquote(__MODULE__))[:from_name]
      end

      defp from_tuple do
        {from_name(), from_email()}
      end
    end
  end
end
