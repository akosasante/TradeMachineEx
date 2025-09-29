defmodule TradeMachine.Mailer.Assets do
  @moduledoc """
  Compile-time embedded assets for email templates.

  This module embeds assets at compile time to ensure they're available
  in production releases without requiring file system access.
  """

  @titlebg_base64 File.read!("priv/static/images/titlebg.jpg") |> Base.encode64()

  @doc """
  Returns the base64-encoded title background image for email headers.
  """
  def titlebg_base64, do: @titlebg_base64
end
