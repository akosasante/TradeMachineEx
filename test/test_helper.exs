Application.put_env(
  :trade_machine,
  :discord_interaction_api,
  TradeMachine.TestDiscordInteractionApi
)

Application.put_env(
  :trade_machine,
  :discord_application_command_api,
  TradeMachine.TestDiscordApplicationCommandApi
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, :manual)
Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, :manual)
