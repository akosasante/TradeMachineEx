# Typed Ecto composite fields in hydrated_trade reference embedded types that
# Dialyzer does not resolve from typed_schema; safe to ignore until types are
# exported or the schema is refactored.
[
  {"lib/trade_machine/data/hydrated_trade.ex",
   "Unknown type: TradeMachine.Data.Types.TradedMajor.t/0."},
  {"lib/trade_machine/data/hydrated_trade.ex",
   "Unknown type: TradeMachine.Data.Types.TradedMinor.t/0."},
  {"lib/trade_machine/data/hydrated_trade.ex",
   "Unknown type: TradeMachine.Data.Types.TradedPick.t/0."}
]
