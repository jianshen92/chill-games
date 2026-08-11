defmodule DoudizhuWeb.Layouts do
  @moduledoc false

  use DoudizhuWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :connected, :boolean, default: false
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="site-header" data-connected={@connected}>
      <a class="brand" href={~p"/"} aria-label="Doudizhu home">
        <span class="brand-mark" aria-hidden="true">地</span>
        <span><strong>斗地主</strong><small>Doudizhu</small></span>
      </a>
      <div class="connection" aria-live="polite">
        <span class="status-dot connection-online" aria-hidden="true"></span>
        <span class="connection-online">Online</span>
        <span class="status-dot connecting connection-offline" aria-hidden="true"></span>
        <span class="connection-offline">Reconnecting…</span>
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
