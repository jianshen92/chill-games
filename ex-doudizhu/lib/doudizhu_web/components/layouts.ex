defmodule DoudizhuWeb.Layouts do
  @moduledoc false

  use DoudizhuWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :connected, :boolean, default: false
  attr :locale, :string, required: true
  attr :language_tag, :string, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="site-header" data-connected={@connected} lang={@language_tag}>
      <a class="brand" href={~p"/"} aria-label={gettext("Doudizhu home")}>
        <span class="brand-mark" aria-hidden="true">地</span>
        <span><strong>斗地主</strong><small>Doudizhu</small></span>
      </a>
      <div class="header-actions">
        <form id="locale-form" phx-change="change-locale">
          <label class="visually-hidden" for="locale-select">{gettext("Language")}</label>
          <select
            id="locale-select"
            name="locale"
            aria-label={gettext("Language")}
            autocomplete="off"
          >
            <option value="en" selected={@locale == "en"}>English</option>
            <option value="zh_Hans" selected={@locale == "zh_Hans"}>简体中文</option>
          </select>
        </form>
        <div class="connection" aria-live="polite">
          <span class="status-dot connection-online" aria-hidden="true"></span>
          <span class="connection-online">{gettext("Online")}</span>
          <span class="status-dot connecting connection-offline" aria-hidden="true"></span>
          <span class="connection-offline">{gettext("Reconnecting…")}</span>
        </div>
      </div>
    </header>

    <main>{render_slot(@inner_block)}</main>
    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <p :if={message = Phoenix.Flash.get(@flash, :info)} class="toast">{message}</p>
      <p :if={message = Phoenix.Flash.get(@flash, :error)} class="toast error">{message}</p>
    </div>
    """
  end
end
