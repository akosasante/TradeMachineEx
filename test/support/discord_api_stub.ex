defmodule TradeMachine.TestDiscordInteractionApi do
  @moduledoc false

  def create_response(_interaction, _response), do: {:ok}
end

defmodule TradeMachine.TestDiscordApplicationCommandApi do
  @moduledoc false

  def create_guild_command(_guild_id, _command), do: {:ok, %{}}
end
