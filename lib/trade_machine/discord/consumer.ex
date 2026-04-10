defmodule TradeMachine.Discord.Consumer do
  @moduledoc """
  Nostrum gateway consumer for handling Discord events.

  Listens for READY (to register slash commands) and INTERACTION_CREATE
  (to dispatch slash command invocations to handlers).

  Uses `Nostrum.Consumer` which auto-joins the `ConsumerGroup` on init,
  receiving all gateway events dispatched by the Nostrum OTP application.
  """

  use Nostrum.Consumer

  alias TradeMachine.Discord.CommandRouter

  @impl Nostrum.Consumer
  def handle_event({:READY, %{application: %{id: app_id}} = _event, _ws_state}) do
    Logger.info("Discord bot connected — registering slash commands (app_id: #{app_id})")
    CommandRouter.register_commands(app_id)
  end

  @impl Nostrum.Consumer
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    CommandRouter.handle(interaction)
  end
end
