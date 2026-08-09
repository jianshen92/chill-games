defmodule Doudizhu.TelemetryMeasurements do
  @moduledoc false

  def game_processes do
    count =
      case Process.whereis(Doudizhu.Games.GameSupervisor) do
        nil ->
          0

        _pid ->
          Doudizhu.Games.GameSupervisor
          |> DynamicSupervisor.count_children()
          |> Map.fetch!(:active)
      end

    :telemetry.execute([:doudizhu, :games], %{active: count}, %{})
  end
end
