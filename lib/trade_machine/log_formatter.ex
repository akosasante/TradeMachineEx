defmodule Formatter.Log do
  @moduledoc """
   This is a good resource to learn about formatters
   https://timber.io/blog/the-ultimate-guide-to-logging-in-elixir/
  """

  def format(level, message, timestamp, metadata) do
    message
    |> Jason.decode()
    |> case do
         {:ok, msg} -> msg
         {:error, _} -> %{msg: message}
       end
    |> json_msg_format(level, timestamp, metadata)
    |> new_line()
  end

  def json_msg_format(message, level, timestamp, metadata) do
    %{
      timestamp: fmt_timestamp(timestamp),
      level: level,
      message: message,
      module: metadata[:module],
      function: metadata[:function],
      line: metadata[:line]
    }
    |> Jason.encode()
    |> case do
         {:ok, msg} -> msg
         {:error, reason} -> %{error: reason} |> Jason.encode()
       end
  end

  def new_line(msg), do: "#{msg}\n"

  defp fmt_timestamp({date, {hh, mm, ss, ms}}) do
    with {:ok, timestamp} <- NaiveDateTime.from_erl({date, {hh, mm, ss}}, {ms * 1000, 3}),
         result <- NaiveDateTime.to_iso8601(timestamp) do
      "#{result}Z"
    end
  end
end