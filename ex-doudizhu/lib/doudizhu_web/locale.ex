defmodule DoudizhuWeb.Locale do
  @moduledoc "Negotiates and normalizes the locales supported by the browser UI."

  @default "en"
  @supported ["en", "zh_Hans"]

  @spec default() :: String.t()
  def default, do: @default

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec normalize(term()) :: String.t() | nil
  def normalize(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> String.replace("-", "_")
    |> String.downcase()
    |> case do
      "en" -> "en"
      "en_us" -> "en"
      "en_gb" -> "en"
      "zh" -> "zh_Hans"
      "zh_cn" -> "zh_Hans"
      "zh_sg" -> "zh_Hans"
      "zh_hans" -> "zh_Hans"
      _unsupported -> nil
    end
  end

  def normalize(_locale), do: nil

  @spec negotiate([term()]) :: String.t()
  def negotiate(candidates) when is_list(candidates) do
    Enum.find_value(candidates, @default, &normalize/1)
  end

  @spec from_accept_language(String.t() | nil) :: String.t() | nil
  def from_accept_language(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(fn language_range ->
      language_range
      |> String.split(";", parts: 2)
      |> hd()
    end)
    |> Enum.find_value(&normalize/1)
  end

  def from_accept_language(_header), do: nil

  @spec language_tag(String.t()) :: String.t()
  def language_tag("zh_Hans"), do: "zh-Hans"
  def language_tag(_locale), do: "en"
end
