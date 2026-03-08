defmodule LogFormatterTest do
  use ExUnit.Case, async: true

  @timestamp {{2026, 3, 7}, {14, 30, 45, 123}}

  describe "format/4 in production mode" do
    setup do
      original = System.get_env("MIX_ENV")
      System.put_env("MIX_ENV", "production")

      on_exit(fn ->
        if original, do: System.put_env("MIX_ENV", original), else: System.delete_env("MIX_ENV")
      end)

      :ok
    end

    test "returns valid JSON with required fields" do
      result = LogFormatter.format(:info, "test message", @timestamp, [])
      decoded = Jason.decode!(String.trim(result))

      assert decoded["level"] == "info"
      assert decoded["message"] == "test message"
      assert decoded["service"] == "trade_machine_ex"
      assert decoded["@timestamp"] == "2026-03-07T14:30:45.123Z"
    end

    test "includes request_id metadata" do
      metadata = [request_id: "abc-123"]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["request_id"] == "abc-123"
    end

    test "includes user_id metadata" do
      metadata = [user_id: "user-42"]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["user_id"] == "user-42"
    end

    test "formats mfa metadata" do
      metadata = [mfa: {MyModule, :my_func, 2}]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["mfa"] == "Elixir.MyModule.my_func/2"
    end

    test "includes file and line metadata" do
      metadata = [file: "lib/my_module.ex", line: 42]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["file"] == "lib/my_module.ex"
      assert decoded["line"] == 42
    end

    test "formats pid metadata" do
      metadata = [pid: self()]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert is_binary(decoded["pid"])
      assert String.starts_with?(decoded["pid"], "#PID<")
    end

    test "includes oban_job metadata" do
      metadata = [oban_job: %{worker: "EmailWorker", queue: "emails", id: 123}]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["oban_worker"] == "EmailWorker"
      assert decoded["oban_queue"] == "emails"
      assert decoded["oban_job_id"] == 123
    end

    test "skips unrecognized oban_job format" do
      metadata = [oban_job: "not a map"]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      refute Map.has_key?(decoded, "oban_worker")
    end

    test "skips unknown metadata keys" do
      metadata = [custom_key: "value"]
      result = LogFormatter.format(:info, "msg", @timestamp, metadata)
      decoded = Jason.decode!(String.trim(result))

      refute Map.has_key?(decoded, "custom_key")
    end

    test "handles non-list metadata" do
      result = LogFormatter.format(:info, "msg", @timestamp, nil)
      decoded = Jason.decode!(String.trim(result))

      assert decoded["message"] == "msg"
    end

    test "output ends with newline" do
      result = LogFormatter.format(:info, "msg", @timestamp, [])
      assert String.ends_with?(result, "\n")
    end
  end

  describe "format/4 in development mode" do
    setup do
      original = System.get_env("MIX_ENV")
      System.put_env("MIX_ENV", "dev")

      on_exit(fn ->
        if original, do: System.put_env("MIX_ENV", original), else: System.delete_env("MIX_ENV")
      end)

      :ok
    end

    test "returns human-readable format" do
      result = LogFormatter.format(:info, "hello world", @timestamp, [])

      assert result =~ "[info]"
      assert result =~ "hello world"
      assert result =~ "2026-03-07T14:30:45.123Z"
      assert String.ends_with?(result, "\n")
    end

    test "includes request_id in dev format" do
      result = LogFormatter.format(:info, "msg", @timestamp, request_id: "req-1")
      assert result =~ "request_id=req-1"
    end

    test "includes mfa in dev format" do
      result = LogFormatter.format(:debug, "msg", @timestamp, mfa: {MyApp.Worker, :run, 1})
      assert result =~ "Elixir.MyApp.Worker.run/1"
    end

    test "includes file basename and line in dev format" do
      result =
        LogFormatter.format(:warn, "msg", @timestamp, file: "lib/deep/nested/module.ex", line: 99)

      assert result =~ "module.ex"
      assert result =~ ":99"
    end

    test "includes user_id in dev format" do
      result = LogFormatter.format(:info, "msg", @timestamp, user_id: "user-456")
      assert result =~ "user_id=user-456"
    end

    test "includes pid in dev format" do
      result = LogFormatter.format(:info, "msg", @timestamp, pid: self())
      assert result =~ "pid="
    end

    test "handles non-list metadata in dev mode" do
      result = LogFormatter.format(:info, "msg", @timestamp, nil)
      assert result =~ "[info]"
      assert result =~ "msg"
    end

    test "falls through to catch-all for known key with non-matching value type" do
      result = LogFormatter.format(:info, "msg", @timestamp, mfa: "not-a-tuple")
      assert result =~ "[info]"
      assert result =~ "msg"
    end
  end

  describe "format/4 rescue fallback" do
    test "falls back to simple format when formatting raises" do
      result =
        LogFormatter.format(:error, "crash msg", @timestamp, [{:user_id, <<0xFF, 0xFE>>}])

      assert is_binary(result)
      assert result =~ "crash msg"
    end
  end

  describe "timestamp formatting" do
    test "pads single-digit values" do
      timestamp = {{2026, 1, 5}, {3, 7, 9, 1}}
      System.put_env("MIX_ENV", "production")
      result = LogFormatter.format(:info, "msg", timestamp, [])
      System.delete_env("MIX_ENV")
      decoded = Jason.decode!(String.trim(result))

      assert decoded["@timestamp"] == "2026-01-05T03:07:09.001Z"
    end
  end
end
