defmodule TradeMachine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
#      TradeMachine.Repo,
      # Start the Telemetry supervisor
      TradeMachineWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: TradeMachine.PubSub},
      # Start the Endpoint (http/https)
      TradeMachineWeb.Endpoint
      # Start a worker by calling: TradeMachine.Worker.start_link(arg)
      # {TradeMachine.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradeMachine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TradeMachineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
