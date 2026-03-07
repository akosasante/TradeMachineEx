defmodule TradeMachine.Discord.EmbedTester do
  @moduledoc """
  Test different Discord embed formats for trade announcements.

  This module is for testing purposes only and will be removed once
  the actual Discord trade announcer is implemented.

  ## Usage

      # Test all formats at once (uses team names by default)
      TradeMachine.Discord.EmbedTester.test_all_formats()

      # Test with owner display names instead of team names
      TradeMachine.Discord.EmbedTester.test_all_formats(name_style: :owner_names)

      # Test with CSV names instead of team names
      TradeMachine.Discord.EmbedTester.test_all_formats(name_style: :csv_names)

      # Test individual format
      TradeMachine.Discord.EmbedTester.test_format_1()
      TradeMachine.Discord.EmbedTester.test_format_1(name_style: :owner_names)

      # Test against a specific channel
      TradeMachine.Discord.EmbedTester.test_all_formats(channel_id: 123456789)

  ## Name Style Options

  - `:team_names` (default) - "The Mad King" & "Birchmount Boyz"
  - `:owner_names` - "Ryan Neeson" & "Mikey"
  - `:csv_names` - Uses the csvName field from User table (one per team)
  """

  alias Nostrum.Api
  require Logger

  # Default test channel ID - override with channel_id: option
  @default_channel_id 993_941_280_184_864_928

  # ============================================================================
  # Public API
  # ============================================================================

  def test_all_formats(opts \\ []) do
    trade = build_sample_trade()

    Logger.info("Testing all Discord embed formats...")

    test_format("Option 1: Compact (Slack-like)", build_compact_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 2: Condensed (All in description)", build_inline_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 3: Multiple Embeds (One per team)", build_multi_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 4: Emoji Style (Scannable)", build_emoji_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 5: Detailed (Polished)", build_detailed_embed(trade, opts), opts)

    Logger.info("All formats tested!")
  end

  def test_format_1(opts \\ []),
    do: test_single("Option 1: Compact", &build_compact_embed/2, opts)

  def test_format_2(opts \\ []),
    do: test_single("Option 2: Condensed", &build_inline_embed/2, opts)

  def test_format_3(opts \\ []),
    do: test_single("Option 3: Multiple Embeds", &build_multi_embed/2, opts)

  def test_format_4(opts \\ []),
    do: test_single("Option 4: Emoji Style", &build_emoji_embed/2, opts)

  def test_format_5(opts \\ []),
    do: test_single("Option 5: Detailed", &build_detailed_embed/2, opts)

  # Test different missing data strategies
  def test_missing_data_strategies(opts \\ []) do
    Logger.info("Testing missing data strategies...")

    base_opts =
      Keyword.merge(opts, channel_id: Keyword.get(opts, :channel_id, @default_channel_id))

    # Test with :show_unknown (default)
    test_single(
      "Missing Data: Show 'Unknown'",
      &build_compact_embed/2,
      Keyword.put(base_opts, :missing_data_strategy, :show_unknown)
    )

    :timer.sleep(2000)

    # Test with :skip_missing
    test_single(
      "Missing Data: Skip Missing Fields",
      &build_compact_embed/2,
      Keyword.put(base_opts, :missing_data_strategy, :skip_missing)
    )

    :timer.sleep(2000)

    # Test with :show_undefined
    test_single(
      "Missing Data: Show 'undefined'",
      &build_compact_embed/2,
      Keyword.put(base_opts, :missing_data_strategy, :show_undefined)
    )

    Logger.info("Missing data strategy tests complete!")
  end

  # ============================================================================
  # Option 1: Compact Embed (Most Slack-like)
  # ============================================================================

  defp build_compact_embed(trade, opts) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      **#{format_date()}** | Trade requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Trade will be upheld after: <t:#{calculate_uphold_timestamp()}:F>
      """,
      color: 0x3498DB,
      fields: build_participant_fields(trade, opts),
      footer: %{
        text: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET"
      }
    }
  end

  # ============================================================================
  # Option 2: Condensed Format (All info in description, no fields)
  # ============================================================================

  defp build_inline_embed(trade, opts) do
    participants_text =
      trade.participants
      |> Enum.map(fn participant ->
        items_text = format_received_items(trade, participant, opts)
        "**#{format_participant_name(participant, opts)}** receives:\n#{items_text}"
      end)
      |> Enum.join("\n\n")

    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      **#{format_date()}** | Trade requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Trade will be upheld after: <t:#{calculate_uphold_timestamp()}:F>

      #{participants_text}
      """,
      color: 0x3498DB,
      footer: %{
        text: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET"
      }
    }
  end

  # ============================================================================
  # Option 3: Multiple Embeds (One per team)
  # ============================================================================

  defp build_multi_embed(trade, opts) do
    header_embed = %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      **#{format_date()}** | Trade requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Trade will be upheld after: <t:#{calculate_uphold_timestamp()}:F>
      """,
      color: 0x3498DB,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    participant_embeds =
      Enum.map(trade.participants, fn participant ->
        %{
          title: "#{format_participant_name(participant, opts)} receives:",
          description: format_received_items(trade, participant, opts),
          color: get_team_color(participant.team)
        }
      end)

    footer_embed = %{
      description: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET",
      color: 0x95A5A6
    }

    [header_embed] ++ participant_embeds ++ [footer_embed]
  end

  # ============================================================================
  # Option 4: Emoji Style (More scannable)
  # ============================================================================

  defp build_emoji_embed(trade, opts) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      color: 0x3498DB,
      fields:
        [
          %{
            name: "📅 Date & Time",
            value: """
            **#{format_date()}**
            Uphold time: <t:#{calculate_uphold_timestamp()}:F>
            """,
            inline: false
          },
          %{
            name: "👥 Participants",
            value: """
            **Requested by:** #{format_mentions(trade.creator.owners)}
            **Trading with:** #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
            """,
            inline: false
          }
        ] ++
          build_participant_fields_with_emoji(trade, opts) ++
          [
            %{
              name: "🔗 Submit Your Trades",
              value: "Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET",
              inline: false
            }
          ],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_participant_fields_with_emoji(trade, opts) do
    Enum.map(trade.participants, fn participant ->
      %{
        name: "🎁 #{format_participant_name(participant, opts)} receives:",
        value: format_received_items_with_emoji(trade, participant, opts),
        inline: false
      }
    end)
  end

  # ============================================================================
  # Option 5: Detailed with Author and Thumbnail
  # ============================================================================

  defp build_detailed_embed(trade, opts) do
    %{
      author: %{
        name: "FlexFoxFantasy TradeMachine",
        url: "https://trades.flexfoxfantasy.com"
        # icon_url: "https://your-logo-url.com/logo.png"  # Uncomment if you have a logo
      },
      title: "🔊  A Trade Has Been Submitted  🔊",
      # url: "https://trades.flexfoxfantasy.com/trades/#{trade.id}",  # Uncomment for deep linking
      description: """
      Trade submitted between **#{format_participant_name(trade.creator, opts)}** & **#{format_recipients(trade.recipients, opts)}**
      """,
      color: 0x3498DB,
      fields:
        [
          %{
            name: "📋 Trade Details",
            value: """
            **Requested by:** #{format_mentions(trade.creator.owners)}
            **Trading with:** #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
            **Date:** #{format_date()}
            **Uphold after:** <t:#{calculate_uphold_timestamp()}:F>
            """,
            inline: false
          }
        ] ++ build_participant_fields(trade, opts),
      footer: %{
        text: "Submit trades by 11:00PM ET"
        # icon_url: "https://your-icon-url.com/clock.png"  # Optional
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # ============================================================================
  # Helper Functions - Field Builders
  # ============================================================================

  defp build_participant_fields(trade, opts) do
    Enum.map(trade.participants, fn participant ->
      %{
        name: "#{format_participant_name(participant, opts)} receives:",
        value: format_received_items(trade, participant, opts),
        inline: false
      }
    end)
  end

  # ============================================================================
  # Helper Functions - Name Formatting
  # ============================================================================

  defp format_participant_name(participant, opts) do
    name_style = Keyword.get(opts, :name_style, :team_names)

    case name_style do
      :team_names ->
        participant.team.name

      :owner_names ->
        participant.team.owners
        |> Enum.map(& &1.display_name)
        |> Enum.join(" & ")

      :csv_names ->
        # Find the first owner with a csvName (should only be one per team)
        participant.team.owners
        |> Enum.find_value(fn owner -> owner.csv_name end)
        |> case do
          # Fallback to team name
          nil -> participant.team.name
          csv_name -> csv_name
        end
    end
  end

  defp format_pick_owner_name(trade, team_name, opts) do
    name_style = Keyword.get(opts, :name_style, :team_names)

    case name_style do
      :team_names ->
        team_name

      :owner_names ->
        find_participant_and_format(trade, team_name, &format_owner_display_names/1)

      :csv_names ->
        find_participant_and_format(trade, team_name, &format_csv_name/1)
    end
  end

  defp find_participant_and_format(trade, team_name, formatter) do
    # Check both creator/recipients (which have owners directly) and participants (which have team.owners)
    all_participants = [trade.creator | trade.recipients]

    all_participants
    |> Enum.find(fn p -> p.team.name == team_name end)
    |> case do
      nil -> team_name
      participant -> formatter.(participant)
    end
  end

  defp format_owner_display_names(participant) do
    # Handle both structures: participant.owners and participant.team.owners
    owners = Map.get(participant, :owners) || participant.team.owners

    owners
    |> Enum.map(& &1.display_name)
    |> Enum.join(" & ")
  end

  defp format_csv_name(participant) do
    # Handle both structures: participant.owners and participant.team.owners
    owners = Map.get(participant, :owners) || participant.team.owners
    team_name = Map.get(participant, :name) || participant.team.name

    owners
    |> Enum.find_value(fn owner -> owner.csv_name end)
    |> case do
      nil -> team_name
      csv_name -> csv_name
    end
  end

  defp format_minor_player(item, opts) do
    strategy = Keyword.get(opts, :missing_data_strategy, :show_unknown)

    position = format_field(item.position, strategy, :position)
    league_level = format_field(item.league_level, strategy, :league_level)
    team = format_field(item.team, strategy, :team)

    case strategy do
      :skip_missing ->
        # Build string with only non-nil fields
        parts =
          [position, league_level && "#{league_level} Minors", team]
          |> Enum.reject(&is_nil/1)

        if Enum.empty?(parts) do
          "• **#{item.name}**"
        else
          "• **#{item.name}** (#{Enum.join(parts, " - ")})"
        end

      _ ->
        # Show all fields with fallback values
        "• **#{item.name}** (#{position} - #{league_level} Minors - #{team})"
    end
  end

  defp format_field(value, strategy, field_type) do
    cond do
      # If value exists and is not "undefined" string, use it
      value not in [nil, "undefined"] ->
        value

      # Handle missing data based on strategy
      strategy == :show_unknown ->
        case field_type do
          :position -> "Unknown Position"
          :league_level -> "Unknown Level"
          :team -> "Unknown Team"
        end

      strategy == :skip_missing ->
        nil

      strategy == :show_undefined ->
        "undefined"

      # Default fallback (same as :show_unknown)
      true ->
        case field_type do
          :position -> "Unknown Position"
          :league_level -> "Unknown Level"
          :team -> "Unknown Team"
        end
    end
  end

  defp format_recipients(recipients, opts) do
    Enum.map_join(recipients, " & ", &format_participant_name(&1, opts))
  end

  # ============================================================================
  # Helper Functions - Item Formatting
  # ============================================================================

  defp format_received_items(trade, participant, opts \\ []) do
    items = participant.received_items

    # Separate majors and minors
    {majors, minors} =
      Enum.split_with(items, fn item ->
        item.type == :player && item.league == "Majors"
      end)

    # Format majors
    majors_text =
      majors
      |> Enum.map(fn item ->
        case item.type do
          :player ->
            "• **#{item.name}** (#{item.position} - Majors - #{item.team})"

          :pick ->
            owner_name = format_pick_owner_name(trade, item.original_owner, opts)
            "• **#{owner_name}'s** #{item.round} round #{item.league} pick"
        end
      end)
      |> Enum.join("\n")

    # Format minors/picks
    minors_text =
      minors
      |> Enum.map(fn item ->
        case item.type do
          :player ->
            format_minor_player(item, opts)

          :pick ->
            owner_name = format_pick_owner_name(trade, item.original_owner, opts)
            "• **#{owner_name}'s** #{item.round} round #{item.league} pick"
        end
      end)
      |> Enum.join("\n")

    # Combine with spacing (single newline, not double)
    [majors_text, minors_text]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> case do
      "" -> "_No items_"
      text -> text
    end
  end

  defp format_received_items_with_emoji(trade, participant, opts \\ []) do
    items = participant.received_items

    items
    |> Enum.map(fn item ->
      emoji =
        case item.type do
          :player when item.league == "Majors" -> "⚾"
          :player -> "🌱"
          :pick -> "🎟️"
        end

      case item.type do
        :player when item.league == "Majors" ->
          "#{emoji} **#{item.name}** (#{item.position} - Majors - #{item.team})"

        :player ->
          formatted = format_minor_player(item, opts)
          # Replace the bullet with emoji
          String.replace_prefix(formatted, "•", emoji)

        :pick ->
          owner_name = format_pick_owner_name(trade, item.original_owner, opts)
          "#{emoji} **#{owner_name}'s** #{item.round} round #{item.league} pick"
      end
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "_No items_"
      text -> text
    end
  end

  defp format_date do
    now = DateTime.utc_now()
    timestamp = DateTime.to_unix(now)
    "<t:#{timestamp}:D>"
  end

  defp format_mentions(owners) do
    mentions =
      owners
      |> Enum.filter(& &1.discord_user_id)
      |> Enum.map(&"<@#{&1.discord_user_id}>")
      |> Enum.join(", ")

    case mentions do
      "" ->
        # Fallback to display names if no Discord IDs
        owners
        |> Enum.map(&"@#{&1.display_name}")
        |> Enum.join(", ")

      mentions ->
        mentions
    end
  end

  defp calculate_uphold_timestamp do
    # Trades are upheld at 11:00 PM Eastern, with minimum 24 hours from submission
    # Example: Trade submitted March 6 at 11:10 PM ET -> upheld March 8 at 11:00 PM ET
    #          Trade submitted March 6 at 10:55 PM ET -> upheld March 7 at 11:00 PM ET
    # Note: During DST transitions, we prioritize the next calendar day at 11 PM
    # rather than exactly 24 hours of elapsed time

    now_utc = DateTime.utc_now()

    # Convert to Eastern Time (handles EST/EDT automatically)
    now_eastern = DateTime.shift_zone!(now_utc, "America/New_York")

    # Calculate minimum uphold time (24 hours from now in Eastern)
    minimum_uphold_time = DateTime.add(now_eastern, 86_400, :second)

    # Get today at 11:00 PM Eastern
    today_11pm_eastern = %{now_eastern | hour: 23, minute: 0, second: 0, microsecond: {0, 6}}

    # Start from today's 11pm, but if it's already passed, start from tomorrow's 11pm
    # Use Date.add to handle DST transitions properly (adds calendar days, not seconds)
    next_11pm_eastern =
      if DateTime.compare(today_11pm_eastern, now_eastern) == :gt do
        today_11pm_eastern
      else
        # Today's 11pm has passed, start from tomorrow's 11pm
        tomorrow_date = Date.add(DateTime.to_date(now_eastern), 1)

        {:ok, tomorrow_11pm} =
          DateTime.new(tomorrow_date, ~T[23:00:00.000000], "America/New_York")

        tomorrow_11pm
      end

    # Find the next 11:00 PM Eastern that's at least 24 hours away from now
    # Use Date.add to move to next day's 11pm if needed (handles DST)
    uphold_time_eastern =
      case DateTime.compare(next_11pm_eastern, minimum_uphold_time) do
        :gt ->
          next_11pm_eastern

        :eq ->
          next_11pm_eastern

        :lt ->
          # Move to next calendar day's 11pm
          next_date = Date.add(DateTime.to_date(next_11pm_eastern), 1)
          {:ok, next_day_11pm} = DateTime.new(next_date, ~T[23:00:00.000000], "America/New_York")
          next_day_11pm
      end

    # Convert back to UTC for the timestamp
    uphold_time_utc = DateTime.shift_zone!(uphold_time_eastern, "Etc/UTC")
    DateTime.to_unix(uphold_time_utc)
  end

  defp get_team_color(team) do
    # Assign different colors to different teams
    # You could store these in your database or use a hash function
    colors = [
      # Red
      0xE74C3C,
      # Blue
      0x3498DB,
      # Green
      0x2ECC71,
      # Orange
      0xF39C12,
      # Purple
      0x9B59B6,
      # Turquoise
      0x1ABC9C,
      # Carrot
      0xE67E22,
      # Dark gray
      0x34495E
    ]

    # Simple hash based on team name
    index = :erlang.phash2(team.name, length(colors))
    Enum.at(colors, index)
  end

  # ============================================================================
  # Sample Data
  # ============================================================================

  defp build_sample_trade do
    # Based on your screenshot, enhanced with draft picks of each level
    %{
      id: "test-trade-id",
      creator: %{
        name: "The Mad King",
        team: %{name: "The Mad King"},
        owners: [
          %{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}
        ]
      },
      recipients: [
        %{
          name: "Birchmount Boyz",
          team: %{name: "Birchmount Boyz"},
          owners: [%{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"}]
        },
        %{
          name: "Team James",
          team: %{name: "Team James"},
          owners: [
            %{display_name: "James", discord_user_id: nil, csv_name: "James"},
            %{display_name: "Sarah", discord_user_id: nil, csv_name: nil}
          ]
        }
      ],
      participants: [
        %{
          team: %{
            name: "The Mad King",
            owners: [%{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}]
          },
          received_items: [
            %{
              type: :player,
              name: "Ketel Marte",
              position: "2B",
              league: "Majors",
              team: "ARI"
            },
            %{
              type: :pick,
              original_owner: "Birchmount Boyz",
              round: "2nd",
              league: "Major League",
              season: 2026
            },
            %{
              type: :pick,
              original_owner: "Team James",
              round: "3rd",
              league: "High Minors",
              season: 2026
            }
          ]
        },
        %{
          team: %{
            name: "Birchmount Boyz",
            owners: [%{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"}]
          },
          received_items: [
            %{
              type: :player,
              name: "George Kirby",
              position: "SP",
              league: "Majors",
              team: "SEA"
            },
            %{
              type: :player,
              name: "Patrick Forbes",
              position: nil,
              league: "Minors",
              league_level: "undefined",
              team: nil
            },
            %{
              type: :pick,
              original_owner: "The Mad King",
              round: "1st",
              league: "Low Minors",
              season: 2026
            }
          ]
        },
        %{
          team: %{
            name: "Team James",
            owners: [
              %{display_name: "James", discord_user_id: nil, csv_name: "James"},
              %{display_name: "Sarah", discord_user_id: nil, csv_name: nil}
            ]
          },
          received_items: [
            %{
              type: :player,
              name: "Zachary Root",
              position: nil,
              league: "Minors",
              league_level: "undefined",
              team: nil
            },
            %{
              type: :pick,
              original_owner: "Birchmount Boyz",
              round: "4th",
              league: "Major League",
              season: 2027
            }
          ]
        }
      ]
    }
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp test_format(name, embed_or_embeds, opts) do
    embeds = if is_list(embed_or_embeds), do: embed_or_embeds, else: [embed_or_embeds]
    channel_id = Keyword.get(opts, :channel_id, @default_channel_id)

    Logger.info("Sending: #{name}")

    case Api.create_message(channel_id,
           content: "**#{name}**",
           embeds: embeds
         ) do
      {:ok, _message} ->
        Logger.info("✓ #{name} sent successfully")
        :ok

      {:error, reason} ->
        Logger.error("✗ #{name} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_single(name, builder_fn, opts) do
    trade = build_sample_trade()
    embed_or_embeds = builder_fn.(trade, opts)
    test_format(name, embed_or_embeds, opts)
  end
end
