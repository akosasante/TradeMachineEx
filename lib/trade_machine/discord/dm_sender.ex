defmodule TradeMachine.Discord.DmSender do
  @moduledoc """
  Behaviour for sending Discord DM embeds.

  The default implementation delegates to `TradeMachine.Discord.Client`.
  In test, a stub is registered via `Application.put_env/3` in `test_helper.exs`.
  """

  @callback send_dm_embed(String.t(), map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the configured implementation module.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :trade_machine,
      :discord_dm_sender,
      TradeMachine.Discord.DmSender.Default
    )
  end
end

defmodule TradeMachine.Discord.DmSender.Default do
  @moduledoc false
  @behaviour TradeMachine.Discord.DmSender

  @impl true
  defdelegate send_dm_embed(discord_user_id, embed), to: TradeMachine.Discord.Client
end
