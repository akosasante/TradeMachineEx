defmodule TradeMachine.Data.UserSettings do
  @moduledoc """
  Pure normalization for the `userSettings` JSONB column on the `user` table.

  Mirrors the TypeScript `normalizeUserSettings()` in `src/utils/userSettings.ts`.
  See `docs/adr/0001-user-settings-jsonb-on-user.md`.
  """

  @current_schema_version 1

  @default_trade_action_email true
  @default_trade_action_discord_dm false

  @type resolved_notifications :: %{
          trade_action_discord_dm: boolean(),
          trade_action_email: boolean()
        }

  @type t :: %{
          schema_version: pos_integer(),
          settings_updated_at: String.t() | nil,
          notifications: resolved_notifications()
        }

  @doc """
  Normalize a raw `user_settings` map (from Ecto/Postgres JSONB) into resolved values.

  Handles nil, empty maps, missing keys, and JSON null values.
  """
  @spec normalize(map() | nil) :: t()
  def normalize(nil), do: defaults()
  def normalize(raw) when raw == %{}, do: defaults()

  def normalize(raw) when is_map(raw) do
    notifications = raw["notifications"] || %{}

    %{
      schema_version: raw["schemaVersion"] || @current_schema_version,
      settings_updated_at: raw["settingsUpdatedAt"],
      notifications: %{
        trade_action_discord_dm:
          resolve_bool(notifications["tradeActionDiscordDm"], @default_trade_action_discord_dm),
        trade_action_email:
          resolve_bool(notifications["tradeActionEmail"], @default_trade_action_email)
      }
    }
  end

  def normalize(_), do: defaults()

  @doc """
  Returns true if the user has trade action Discord DMs enabled (after normalization).
  """
  @spec discord_dm_enabled?(map() | nil) :: boolean()
  def discord_dm_enabled?(raw_settings) do
    normalize(raw_settings).notifications.trade_action_discord_dm
  end

  @doc """
  Returns true if the user has trade action emails enabled (after normalization).
  """
  @spec email_enabled?(map() | nil) :: boolean()
  def email_enabled?(raw_settings) do
    normalize(raw_settings).notifications.trade_action_email
  end

  defp defaults do
    %{
      schema_version: @current_schema_version,
      settings_updated_at: nil,
      notifications: %{
        trade_action_discord_dm: @default_trade_action_discord_dm,
        trade_action_email: @default_trade_action_email
      }
    }
  end

  defp resolve_bool(value, _default) when is_boolean(value), do: value
  defp resolve_bool(_, default), do: default
end
