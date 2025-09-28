alias Elixir.TradeMachine.Data.DraftPick
alias Elixir.TradeMachine.Data.Email
alias Elixir.TradeMachine.Data.HydratedMajor
alias Elixir.TradeMachine.Data.HydratedMinor
alias Elixir.TradeMachine.Data.HydratedPick
alias Elixir.TradeMachine.Data.HydratedTrade
alias Elixir.TradeMachine.Data.Player
alias Elixir.TradeMachine.Data.Settings
alias Elixir.TradeMachine.Data.Team
alias Elixir.TradeMachine.Data.Trade
alias Elixir.TradeMachine.Data.TradeItem
alias Elixir.TradeMachine.Data.TradeParticipant
alias Elixir.TradeMachine.Data.User

alias TradeMachine.Repo

require Ecto.Query

# defmodule StartupModule do
#  require Kernel.SpecialForms
#
#  def get_all_schema_modules() do
#    get_all_modules()
#    |> filter_and_return_schema_modules()
#    |> Enum.each(fn module ->
#      IO.inspect(module)
#      #      alias module
#    end)
#  end
#
#  defp get_all_modules() do
#    {:ok, all_modules} = :application.get_key(:trade_machine, :modules)
#
#    all_modules
#  end
#
#  defp filter_and_return_schema_modules(list_of_modules) do
#    list_of_modules
#    |> Enum.flat_map(fn module ->
#      case is_schema_module(Module.split(module)) do
#        true -> [module]
#        false -> []
#      end
#    end)
#  end
#
#  defp is_schema_module(["TradeMachine", "Data", _]), do: true
#  defp is_schema_module(_), do: false
# end
#
# StartupModule.get_all_schema_modules()
