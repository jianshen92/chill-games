defmodule Doudizhu.Protocol.SchemaTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Domain.Card
  alias ExJsonSchema.{Schema, Validator}

  test "published command example validates against protocol v1 schema" do
    schema = resolved_schema("command.schema.json")
    example = read_json("examples/play_cards.command.json")
    assert Validator.validate(schema, example) == :ok
  end

  test "published message example validates against protocol v1 schema" do
    schema = resolved_schema("message.schema.json")
    example = read_json("examples/accepted.message.json")
    assert Validator.validate(schema, example) == :ok
  end

  test "all canonical physical card IDs satisfy the command schema" do
    schema = resolved_schema("command.schema.json")

    for card <- Card.standard_deck() do
      command = %{
        "protocol_version" => 1,
        "kind" => "command",
        "game_id" => "game",
        "command_id" => "command",
        "expected_version" => 0,
        "action" => %{"type" => "play_cards", "cards" => [Card.to_id(card)]}
      }

      assert Validator.validate(schema, command) == :ok
    end
  end

  defp resolved_schema(path), do: path |> read_json() |> Schema.resolve()

  defp read_json(path) do
    :doudizhu
    |> :code.priv_dir()
    |> Path.join("protocol/v1/#{path}")
    |> File.read!()
    |> Jason.decode!()
  end
end
