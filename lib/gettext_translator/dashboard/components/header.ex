defmodule GettextTranslator.Dashboard.Components.Header do
  @moduledoc """
  Header component for the Gettext Translator dashboard.
  """
  use Phoenix.Component

  attr(:gettext_path, :string, required: true)
  attr(:translations_count, :integer, required: true)
  attr(:translations_loaded, :boolean, required: true)
  attr(:modified_count, :integer, default: 0)
  attr(:approved_count, :integer, default: 0)
  attr(:loading, :boolean, default: false)

  def render(assigns) do
    ~H"""
    <section class="dashboard-card">
      <h5 class="card-title">Gettext Translations</h5>

      <div class="dashboard-stats-container">
        <div class="dashboard-stat mb-6 border-b pb-4">
          <span class="dashboard-stat-label">Gettext path:</span>
          <span class="dashboard-stat-value">{@gettext_path}</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="dashboard-stat">
            <span class="dashboard-stat-label">Loaded translations:</span>
            <span class="dashboard-stat-value">{@translations_count}</span>
          </div>
          <div class="dashboard-stat">
            <span class="dashboard-stat-label">Modified translations:</span>
            <span class="dashboard-stat-value">{@modified_count}</span>
          </div>
          <div class="dashboard-stat">
            <span class="dashboard-stat-label">Approved translations:</span>
            <span class="dashboard-stat-value">{@approved_count}</span>
          </div>
        </div>

        <div class="dashboard-controls-container">
          <form phx-submit="load_translations" phx-change="noop">
            <input type="hidden" name="path" value={@gettext_path} />
            <button type="submit" class="btn btn-primary" phx-disable-with="Loading...">
              {if @translations_loaded, do: "Reload", else: "Load"} Translations
            </button>
          </form>

          <%= if @translations_loaded do %>
            <form phx-submit="save_to_files" phx-change="noop">
              <button
                phx-click="save_to_files"
                disabled={@loading}
                type="submit"
                class="btn btn-success"
              >
                <%= if @loading do %>
                  Saving...
                <% else %>
                  Save Changes to Files Modified: ({@modified_count}) + Approved: ({@approved_count})
                <% end %>
              </button>
            </form>

            <form phx-submit="make_pull_request" phx-change="noop">
              <button type="submit" class="btn btn-info" phx-disable-with="Creating PR...">
                Make Pull Request Modified: ({@modified_count}) + Approved: ({@approved_count})
              </button>
            </form>
          <% end %>
        </div>
      </div>
    </section>
    """
  end
end
