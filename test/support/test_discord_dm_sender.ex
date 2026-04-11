defmodule TradeMachine.TestDiscordDmSender do
  @moduledoc false
  @behaviour TradeMachine.Discord.DmSender

  @doc """
  Test double for `DmSender`. Records last payload on the caller process for assertions:

  * `Process.get(:test_last_dm_embed)`
  * `Process.get(:test_last_dm_components)`
  """
  @impl true
  def send_dm_embed(discord_user_id, embed, components) do
    Process.put(:test_last_dm_discord_user_id, discord_user_id)
    Process.put(:test_last_dm_embed, embed)
    Process.put(:test_last_dm_components, components)
    {:ok, %{id: "stub-dm-message-id"}}
  end
end
