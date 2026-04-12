defmodule TradeMachine.Data.UserSettingsTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.UserSettings

  describe "normalize/1" do
    test "nil returns defaults (email on, discord off)" do
      result = UserSettings.normalize(nil)
      assert result.notifications.trade_action_email == true
      assert result.notifications.trade_action_discord_dm == false
      assert result.settings_updated_at == nil
      assert result.schema_version == 1
    end

    test "empty map returns defaults" do
      result = UserSettings.normalize(%{})
      assert result.notifications.trade_action_email == true
      assert result.notifications.trade_action_discord_dm == false
    end

    test "empty notifications returns defaults" do
      result = UserSettings.normalize(%{"notifications" => %{}})
      assert result.notifications.trade_action_email == true
      assert result.notifications.trade_action_discord_dm == false
    end

    test "respects explicit false for email" do
      result = UserSettings.normalize(%{"notifications" => %{"tradeActionEmail" => false}})
      assert result.notifications.trade_action_email == false
    end

    test "respects explicit true for discord dm" do
      result = UserSettings.normalize(%{"notifications" => %{"tradeActionDiscordDm" => true}})
      assert result.notifications.trade_action_discord_dm == true
    end

    test "null JSON values use defaults" do
      result =
        UserSettings.normalize(%{
          "notifications" => %{
            "tradeActionDiscordDm" => nil,
            "tradeActionEmail" => nil
          }
        })

      assert result.notifications.trade_action_email == true
      assert result.notifications.trade_action_discord_dm == false
    end

    test "preserves settingsUpdatedAt" do
      ts = "2026-04-12T01:00:00.000Z"
      result = UserSettings.normalize(%{"settingsUpdatedAt" => ts})
      assert result.settings_updated_at == ts
    end

    test "preserves schemaVersion" do
      result = UserSettings.normalize(%{"schemaVersion" => 2})
      assert result.schema_version == 2
    end

    test "non-map input returns defaults" do
      result = UserSettings.normalize("garbage")
      assert result.notifications.trade_action_email == true
      assert result.notifications.trade_action_discord_dm == false
    end
  end

  describe "discord_dm_enabled?/1" do
    test "false for nil" do
      refute UserSettings.discord_dm_enabled?(nil)
    end

    test "true when explicitly set" do
      assert UserSettings.discord_dm_enabled?(%{
               "notifications" => %{"tradeActionDiscordDm" => true}
             })
    end
  end

  describe "email_enabled?/1" do
    test "true for nil (default)" do
      assert UserSettings.email_enabled?(nil)
    end

    test "false when explicitly set" do
      refute UserSettings.email_enabled?(%{
               "notifications" => %{"tradeActionEmail" => false}
             })
    end
  end
end
