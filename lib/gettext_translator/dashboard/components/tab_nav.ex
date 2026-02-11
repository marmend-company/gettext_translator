defmodule GettextTranslator.Dashboard.Components.TabNav do
  @moduledoc """
  Top-level tab navigation for the dashboard page.
  Switches between Translation Stats, New Extracted, and New Translated views.
  """
  use Phoenix.Component

  attr(:active_tab, :string, required: true)
  attr(:extracted_count, :integer, required: true)
  attr(:translated_count, :integer, required: true)

  def render(assigns) do
    ~H"""
    <div class="tab-nav">
      <button
        type="button"
        class={"tab-nav-item #{if @active_tab == "stats", do: "active", else: ""}"}
        phx-click="switch_tab"
        phx-value-tab="stats"
      >
        Translation Stats
      </button>
      <button
        type="button"
        class={"tab-nav-item #{if @active_tab == "extracted", do: "active", else: ""}"}
        phx-click="switch_tab"
        phx-value-tab="extracted"
      >
        New Extracted
        <%= if @extracted_count > 0 do %>
          <span class="tab-badge tab-badge-pending">{@extracted_count}</span>
        <% end %>
      </button>
      <%= if @translated_count > 0 do %>
        <button
          type="button"
          class={"tab-nav-item #{if @active_tab == "translated", do: "active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab="translated"
        >
          New Translated <span class="tab-badge tab-badge-translated">{@translated_count}</span>
        </button>
      <% end %>
    </div>
    """
  end
end
