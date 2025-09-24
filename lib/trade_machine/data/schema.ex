defmodule TradeMachine.Schema do
  def convert_field_name_to_database_name(field_name_atom) do
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

  defmacro __using__(_) do
    quote do
      use TypedEctoSchema
      import Ecto.Changeset

      @primary_key {:id, Ecto.UUID, autogenerate: true}
      @foreign_key_type Ecto.UUID
      @timestamps_opts inserted_at_source: :dateCreated,
                       updated_at_source: :dateModified
      @field_source_mapper &TradeMachine.Schema.convert_field_name_to_database_name/1
    end
  end
end
