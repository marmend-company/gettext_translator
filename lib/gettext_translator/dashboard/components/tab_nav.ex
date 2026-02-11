defmodule GettextTranslator.Dashboard.Components.TabNav do
  @moduledoc """
  Tab navigation component for switching between All, New, and Extracted translations.
  """
  use Phoenix.Component

  attr(:active_tab, :string, required: true)
  attr(:new_count, :integer, required: true)
  attr(:extracted_count, :integer, required: true)

  def render(assigns) do
    ~H"""
    <div class="tab-nav">
      <button
        type="button"
        class={"tab-nav-item #{if @active_tab == "all", do: "active", else: ""}"}
        phx-click="switch_tab"
        phx-value-tab="all"
      >
        All Translations
      </button>
      <button
        type="button"
        class={"tab-nav-item #{if @active_tab == "new", do: "active", else: ""}"}
        phx-click="switch_tab"
        phx-value-tab="new"
      >
        New Translations
        <%= if @new_count > 0 do %>
          <span class="tab-badge">{@new_count}</span>
        <% end %>
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
    </div>
    """
  end
end
