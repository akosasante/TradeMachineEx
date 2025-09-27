defmodule TradeMachine.SchemaValidationTest do
  use TradeMachine.DataCase, async: false

  @moduledoc """
  Schema Validation Test

  This test ensures that Ecto schema fields correspond to actual database columns.
  Since Prisma (TypeScript) manages all database migrations, this test validates
  that our Elixir schemas don't reference columns that no longer exist.

  Note: Ecto schemas only need to map the columns they use - not every column
  in the database table. This allows selective field mapping.

  If this test fails, it means:
  1. A database migration was run by Prisma that changed/removed a column
  2. The corresponding Ecto schema field needs to be updated or removed
  3. DO NOT create Ecto migrations - update the schema file instead
  """

  # List all schema modules to validate
  @schemas [
    TradeMachine.Data.Trade,
    TradeMachine.Data.TradeItem,
    TradeMachine.Data.TradeParticipant,
    TradeMachine.Data.User,
    TradeMachine.Data.Team,
    TradeMachine.Data.HydratedTrade
    # Add more schemas as they're created
  ]

  describe "schema validation" do
    test "all schemas have corresponding database tables" do
      for schema <- @schemas do
        table_name = schema.__schema__(:source)

        # Check if table exists in database
        query = """
        SELECT EXISTS (
          SELECT FROM information_schema.tables
          WHERE table_schema = 'test'
          AND table_name = $1
        )
        """

        result = Ecto.Adapters.SQL.query!(Repo, query, [table_name])
        table_exists = result.rows |> hd() |> hd()

        assert table_exists,
               """
               Table '#{table_name}' for schema #{inspect(schema)} does not exist in database.

               This likely means:
               1. A Prisma migration removed this table
               2. The table name was changed in Prisma
               3. The Ecto schema source is incorrect

               Action required: Update the Ecto schema or remove it if no longer needed.
               """
      end
    end

    test "schema fields exist in database and have compatible types" do
      for schema <- @schemas do
        table_name = schema.__schema__(:source)
        schema_fields = get_schema_fields(schema)
        db_columns = get_database_columns(table_name)

        # Check that all schema fields exist as database columns
        for {field_name, field_info} <- schema_fields do
          db_column_name = get_db_column_name(field_name, schema)

          assert Map.has_key?(db_columns, db_column_name),
                 """
                 Schema field '#{field_name}' (maps to column '#{db_column_name}')
                 in #{inspect(schema)} does not exist in database table '#{table_name}'.

                 Available database columns: #{inspect(Map.keys(db_columns))}

                 This likely means:
                 1. The column was renamed/removed in a Prisma migration
                 2. The field source mapping is incorrect

                 Action required:
                 1. Check recent Prisma migrations for changes to this column
                 2. Update the Ecto schema field name or remove the field
                 3. Check field source mapping in TradeMachine.Schema if needed
                 """

          # Validate field type compatibility (basic check)
          db_column = db_columns[db_column_name]
          validate_field_type_compatibility(field_name, field_info, db_column, schema)
        end
      end
    end
  end

  # Helper functions

  defp get_schema_fields(schema) do
    # Get only actual database fields, exclude associations
    schema.__schema__(:fields)
    |> Enum.filter(fn field ->
      case schema.__schema__(:type, field) do
        %Ecto.Association.BelongsTo{} -> false
        %Ecto.Association.Has{} -> false
        %Ecto.Association.ManyToMany{} -> false
        _ -> true
      end
    end)
    |> Enum.map(fn field ->
      {field, %{type: schema.__schema__(:type, field)}}
    end)
    |> Map.new()
  end

  defp get_database_columns(table_name) do
    query = """
    SELECT column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'test' AND table_name = $1
    ORDER BY ordinal_position
    """

    result = Ecto.Adapters.SQL.query!(Repo, query, [table_name])

    result.rows
    |> Enum.map(fn [name, type, nullable, default] ->
      {name, %{type: type, nullable: nullable, default: default}}
    end)
    |> Map.new()
  end

  defp get_db_column_name(field_name, schema) do
    # Use the schema's field source mapper if available
    case schema.__schema__(:field_source, field_name) do
      nil ->
        # Apply the field source mapper from TradeMachine.Schema
        TradeMachine.Schema.convert_field_name_to_database_name(field_name) |> Atom.to_string()

      source ->
        source |> Atom.to_string()
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp validate_field_type_compatibility(field_name, field_info, db_column, schema) do
    # Basic type compatibility checks
    # This is a simplified check - could be expanded for more thorough validation

    case {field_info.type, db_column.type} do
      # UUID fields
      {Ecto.UUID, "uuid"} ->
        :ok

      # String fields
      {:string, db_type} when db_type in ["character varying", "varchar", "text"] ->
        :ok

      # Integer fields
      {:integer, db_type} when db_type in ["integer", "bigint", "smallint"] ->
        :ok

      # Boolean fields
      {:boolean, "boolean"} ->
        :ok

      # DateTime fields
      {:naive_datetime, db_type} when db_type in ["timestamp without time zone", "timestamp"] ->
        :ok

      {:utc_datetime, db_type} when db_type in ["timestamp with time zone", "timestamptz"] ->
        :ok

      # Enum fields (stored as strings/varchar in database)
      {{:parameterized, {Ecto.Enum, _}}, db_type}
      when db_type in ["character varying", "varchar", "text"] ->
        :ok

      # Enum fields (stored as PostgreSQL custom enums)
      {{:parameterized, {Ecto.Enum, _}}, "USER-DEFINED"} ->
        :ok

      # Map fields (stored as JSON/JSONB)
      {:map, db_type} when db_type in ["json", "jsonb"] ->
        :ok

      # Array fields
      {{:array, _}, db_type} when db_type in ["ARRAY", "json", "jsonb"] ->
        :ok

      {{:array, _}, db_type} ->
        if String.contains?(db_type, "[]") do
          :ok
        else
          IO.warn("""
          Type compatibility check skipped for #{inspect(schema)}.#{field_name}:
          Ecto type: {:array, _}
          Database type: #{db_type}

          Consider adding validation for this type combination if needed.
          """)
        end

      # Unknown type combination - warn but don't fail
      {ecto_type, db_type} ->
        IO.warn("""
        Type compatibility check skipped for #{inspect(schema)}.#{field_name}:
        Ecto type: #{inspect(ecto_type)}
        Database type: #{db_type}

        Consider adding validation for this type combination if needed.
        """)
    end
  end
end
