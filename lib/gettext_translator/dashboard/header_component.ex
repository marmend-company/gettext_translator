defmodule GettextTranslator.Dashboard.HeaderComponent do
  @moduledoc """
  Header component for the Gettext Translator dashboard.
  """
  use Phoenix.Component

  attr(:gettext_path, :string, required: true)
  attr(:translations_count, :integer, required: true)
  attr(:translations_loaded, :boolean, required: true)

  def render(assigns) do
    ~H"""
    <section class="dashboard-card">
      <h5 class="card-title">Gettext Translations</h5>

      <div class="dashboard-stats-container">
        <div class="dashboard-stat">
          <span class="dashboard-stat-label">Gettext path:</span>
          <span class="dashboard-stat-value"><%= @gettext_path %></span>
        </div>
        <div class="dashboard-stat">
          <span class="dashboard-stat-label">Loaded translations:</span>
          <span class="dashboard-stat-value"><%= @translations_count %></span>
        </div>

        <div class="dashboard-controls-container">
          <form phx-submit="load_translations" phx-change="noop">
            <input type="hidden" name="path" value={@gettext_path} />
            <button type="submit" class="btn btn-primary" phx-disable-with="Loading...">
              <%= if @translations_loaded, do: "Reload", else: "Load" %> Translations
            </button>
          </form>

          <%= if @translations_loaded do %>
            <form phx-submit="save_to_files" phx-change="noop">
              <button type="submit" class="btn btn-success" phx-disable-with="Saving...">
                Save Changes to Files
              </button>
            </form>
          <% end %>
        </div>
      </div>
    </section>
    """
  end
end
