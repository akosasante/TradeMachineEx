defmodule TradeMachine.Discord.EmbedBuilder do
  @moduledoc """
  Builds Discord embed structures for trade announcements.

  Implements the "Condensed" format (Option 2) where all trade information
  is placed in the embed description without separate fields.
  """

  alias TradeMachine.Discord.Formatter

  @embed_color 0x3498DB
  @uphold_hour 23
  @seconds_in_day 86_400

  @typedoc "Structured trade data ready for embed building"
  @type trade_data :: %{
          trade_id: String.t(),
          date_created: DateTime.t(),
          creator: %{owners: [map()]},
          recipient_owners: [map()],
          participants: [Formatter.participant()]
        }

  @doc """
  Builds a Discord embed map for a trade announcement.

  Returns a map compatible with `Nostrum.Api.create_message/2` embed format.
  """
  @spec build_trade_embed(trade_data()) :: map()
  def build_trade_embed(trade_data) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: build_description(trade_data),
      color: @embed_color,
      footer: %{
        text: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET"
      }
    }
  end

  @doc """
  Calculates the Unix timestamp for when a trade will be upheld.

  Trades are upheld at 11:00 PM Eastern with a minimum 24 hours from submission.
  During DST transitions, calendar day arithmetic is used rather than raw seconds.
  """
  @spec calculate_uphold_timestamp() :: integer()
  def calculate_uphold_timestamp do
    calculate_uphold_timestamp(DateTime.utc_now())
  end

  @doc """
  Calculates the uphold timestamp from a given UTC time (testable variant).
  """
  @spec calculate_uphold_timestamp(DateTime.t()) :: integer()
  def calculate_uphold_timestamp(now_utc) do
    now_eastern = DateTime.shift_zone!(now_utc, "America/New_York")
    minimum_uphold_time = DateTime.add(now_eastern, @seconds_in_day, :second)

    today_11pm_eastern = %{
      now_eastern
      | hour: @uphold_hour,
        minute: 0,
        second: 0,
        microsecond: {0, 6}
    }

    next_11pm_eastern =
      if DateTime.compare(today_11pm_eastern, now_eastern) == :gt do
        today_11pm_eastern
      else
        tomorrow_date = Date.add(DateTime.to_date(now_eastern), 1)

        {:ok, tomorrow_11pm} =
          DateTime.new(tomorrow_date, ~T[23:00:00.000000], "America/New_York")

        tomorrow_11pm
      end

    uphold_time_eastern =
      case DateTime.compare(next_11pm_eastern, minimum_uphold_time) do
        :lt ->
          next_date = Date.add(DateTime.to_date(next_11pm_eastern), 1)
          {:ok, next_day_11pm} = DateTime.new(next_date, ~T[23:00:00.000000], "America/New_York")
          next_day_11pm

        _gt_or_eq ->
          next_11pm_eastern
      end

    uphold_time_utc = DateTime.shift_zone!(uphold_time_eastern, "Etc/UTC")
    DateTime.to_unix(uphold_time_utc)
  end

  defp build_description(trade_data) do
    date_text = format_date(trade_data.date_created)
    creator_mentions = Formatter.format_mentions(trade_data.creator.owners)
    recipient_mentions = Formatter.format_mentions(trade_data.recipient_owners)
    uphold_timestamp = calculate_uphold_timestamp()

    participants_text = build_participants_text(trade_data.participants)

    """
    **#{date_text}** | Trade requested by #{creator_mentions}
    Trading with: #{recipient_mentions}
    Trade will be upheld after: <t:#{uphold_timestamp}:F>

    #{participants_text}\
    """
  end

  defp build_participants_text(participants) do
    participants
    |> Enum.map(fn participant ->
      items_text = Formatter.format_items(participant.items)
      "**#{participant.display_name}** receives:\n#{items_text}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_date(datetime) do
    timestamp = DateTime.to_unix(datetime)
    "<t:#{timestamp}:D>"
  end
end
