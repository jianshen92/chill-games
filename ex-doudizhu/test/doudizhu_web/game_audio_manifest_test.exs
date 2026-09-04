defmodule DoudizhuWeb.GameAudioManifestTest do
  use ExUnit.Case, async: true

  @combination_types ~w(
    single
    pair
    triple
    triple_with_single
    triple_with_pair
    straight
    consecutive_pairs
    airplane
    airplane_with_singles
    airplane_with_pairs
    four_with_singles
    four_with_pairs
    bomb
    rocket
  )
  @standard_ranks ~w(3 4 5 6 7 8 9 10 J Q K A 2)
  @single_ranks @standard_ranks ++ ~w(small_joker big_joker)

  setup_all do
    directory = Application.app_dir(:doudizhu, "priv/static/audio/gameplay")
    manifest = directory |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    %{directory: directory, manifest: manifest}
  end

  test "manifest assigns one swappable persona to each table seat", %{manifest: manifest} do
    assert manifest["schema_version"] == 2
    assert manifest["pack"]["language"] == "zh-Hans"
    assert manifest["pack"]["playback_rate"] == 1.3

    assignment = manifest["player_voice_assignment"]
    assert assignment["strategy"] == "table_order"
    assert assignment["personas"] == ~w(serena ethan xiaowan)
    assert assignment["fallback"] in assignment["personas"]

    personas = manifest["personas"]
    assert personas |> Map.keys() |> Enum.sort() == assignment["personas"] |> Enum.sort()
    assert personas |> Map.values() |> Enum.map(& &1["base_path"]) |> Enum.uniq() |> length() == 3

    assert personas["serena"]["generation"]["speaker"] == "Serena"
    assert personas["ethan"]["generation"]["speaker"] == "Ethan"
    assert personas["xiaowan"]["display_name"] == "Xiaowan"
    assert personas["xiaowan"]["generation"]["speaker"] == "Seren"

    refute Enum.any?(personas, fn {id, persona} ->
             String.contains?(id, "/") or
               String.contains?(persona["generation"]["speaker"], "/")
           end)
  end

  test "manifest covers every projected combination and gameplay action", %{manifest: manifest} do
    events = manifest["events"]
    assert Map.has_key?(events, "auction_passed")
    assert Map.has_key?(events, "turn_passed")
    assert events["bid_placed"]["variants"] |> Map.keys() |> Enum.sort() == ~w(1 2 3)

    combinations = events["cards_played"]["variants"]
    assert combinations |> Map.keys() |> Enum.sort() == Enum.sort(@combination_types)

    assert combinations["single"]["variants"] |> Map.keys() |> Enum.sort() ==
             Enum.sort(@single_ranks)

    assert combinations["single"]["variants"]["3"]["text"] == "三！"
    assert combinations["single"]["variants"]["J"]["text"] == "勾！"
    assert combinations["single"]["variants"]["Q"]["text"] == "圈！"
    assert combinations["single"]["variants"]["K"]["text"] == "K！"
    assert combinations["single"]["variants"]["small_joker"]["text"] == "小王！"

    airplane_with_pairs = combinations["airplane_with_pairs"]
    assert airplane_with_pairs["text"] == "飞机带对子！"

    assert airplane_with_pairs["post_processing"]["compress_silence"][
             "retained_duration_ms"
           ] == 30

    for type <- ~w(pair triple bomb) do
      assert combinations[type]["variants"] |> Map.keys() |> Enum.sort() ==
               Enum.sort(@standard_ranks)
    end
  end

  test "every persona provides one present, non-empty MP3 for every cue", %{
    directory: directory,
    manifest: manifest
  } do
    cue_files = manifest["events"] |> cue_files() |> Enum.sort()
    assert length(cue_files) == 69
    assert Enum.uniq(cue_files) == cue_files

    referenced_files =
      for persona <- Map.values(manifest["personas"]), file <- cue_files do
        Path.join(persona["base_path"], file)
      end
      |> Enum.sort()

    disk_files =
      directory
      |> Path.join("**/*.mp3")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, directory))
      |> Enum.sort()

    assert length(referenced_files) == 207
    assert Enum.uniq(referenced_files) == referenced_files
    assert referenced_files == disk_files

    for relative_path <- referenced_files do
      assert File.stat!(Path.join(directory, relative_path)).size > 100
    end
  end

  defp cue_files(%{"file" => file}), do: [file]

  defp cue_files(%{"variants" => variants}) do
    variants
    |> Map.values()
    |> Enum.flat_map(&cue_files/1)
  end

  defp cue_files(entries) when is_map(entries) do
    entries
    |> Map.values()
    |> Enum.flat_map(&cue_files/1)
  end
end
