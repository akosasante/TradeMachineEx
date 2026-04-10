defmodule TradeMachine.Discord.Runtime do
  @moduledoc false

  @doc """
  Returns the module used for Discord interaction HTTP responses.

  In tests, `test/test_helper.exs` may point this to a stub so handlers can run
  without a live Nostrum stack.
  """
  def interaction_api do
    Application.get_env(:trade_machine, :discord_interaction_api, Nostrum.Api.Interaction)
  end

  @doc """
  Returns the module used for registering application (slash) commands.
  """
  def application_command_api do
    Application.get_env(
      :trade_machine,
      :discord_application_command_api,
      Nostrum.Api.ApplicationCommand
    )
  end
end
