defmodule LogFormatter do
  @moduledoc """
  Custom log formatter for structured JSON logging in production.
  This enables better log parsing by Loki and other log aggregation systems.
  """

  def format(level, message, timestamp, metadata) do
    %{
      "@timestamp": format_timestamp(timestamp),
      level: level,
      message: to_string(message),
      service: "trade_machine_ex",
      environment: System.get_env("MIX_ENV", "production")
    }
    |> add_metadata(metadata)
    |> Jason.encode!()
    |> Kernel.<>("\n")
  rescue
    # Fallback to simple format if JSON encoding fails
    _ ->
      "#{format_timestamp(timestamp)} [#{level}] #{message}\n"
  end

  defp format_timestamp({{year, month, day}, {hour, minute, second, millisecond}}) do
    "#{year}-#{pad(month)}-#{pad(day)}T#{pad(hour)}:#{pad(minute)}:#{pad(second)}.#{pad(millisecond, 3)}Z"
  end

  defp add_metadata(log_entry, metadata) when is_list(metadata) do
    Enum.reduce(metadata, log_entry, fn {key, value}, acc ->
      case key do
        :request_id when is_binary(value) ->
          Map.put(acc, :request_id, value)

        :user_id when is_binary(value) or is_integer(value) ->
          Map.put(acc, :user_id, value)

        :mfa when is_tuple(value) ->
          {module, function, arity} = value
          Map.put(acc, :mfa, "#{module}.#{function}/#{arity}")

        :file when is_binary(value) ->
          Map.put(acc, :file, value)

        :line when is_integer(value) ->
          Map.put(acc, :line, value)

        :pid when is_pid(value) ->
          Map.put(acc, :pid, inspect(value))

        :oban_job ->
          case value do
            %{worker: worker, queue: queue, id: id} ->
              Map.merge(acc, %{
                oban_worker: to_string(worker),
                oban_queue: queue,
                oban_job_id: id
              })
            _ ->
              acc
          end

        _ ->
          # Skip other metadata to keep logs clean
          acc
      end
    end)
  end

  defp add_metadata(log_entry, _), do: log_entry

  defp pad(int, count \\ 2) do
    int
    |> Integer.to_string()
    |> String.pad_leading(count, "0")
  end
end