defmodule TradeMachine.Mailer.LayoutView do
  use Phoenix.View,
    root: "lib/trade_machine/mailer/templates",
    namespace: TradeMachine.Mailer

  # Import Phoenix.HTML functions for basic HTML helpers
  import Phoenix.HTML
  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  # Import any other helpers you might need
  import TradeMachineWeb.Gettext
end
