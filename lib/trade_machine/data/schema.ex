defmodule TradeMachine.Schema do
  def convertFieldNameToDatabaseName(field_name_atom) do
    case field_name_atom do
      :uuid ->
        :uuid

      ecto_field ->
        ecto_field
        |> Atom.to_string()
        |> camelize()
        |> String.to_atom()
    end
  end

  defp camelize(""), do: ""

  defp camelize(string) when is_binary(string) do
    string
    |> String.split("_")
    |> then(fn [first_word | rest] ->
      [String.downcase(first_word) | Enum.map(rest, &String.capitalize/1)]
    end)
    |> Enum.join()
  end

  defp camelize(anything_else), do: anything_else

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, Ecto.UUID, autogenerate: true}
      @foreign_key_type Ecto.UUID
      @timestamps_opts inserted_at_source: :dateCreated,
                       updated_at_source: :dateModified,
                       autogenerate: true
      @field_source_mapper &TradeMachine.Schema.convertFieldNameToDatabaseName/1
      @schema_prefix System.get_env("SCHEMA", "dev")
    end
  end
end
