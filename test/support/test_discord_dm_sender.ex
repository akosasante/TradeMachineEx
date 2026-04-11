defmodule TradeMachine.TestDiscordDmSender do
  @moduledoc false
  @behaviour TradeMachine.Discord.DmSender

  @impl true
  def send_dm_embed(_discord_user_id, _embed) do
    {:ok, %{id: "stub-dm-message-id"}}
  end
end
