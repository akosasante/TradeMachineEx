defmodule TradeMachine.Mailer.EmailView do
  use Phoenix.View,
    root: "lib/trade_machine/mailer/templates",
    namespace: TradeMachine.Mailer

  use PhoenixHTMLHelpers
end
