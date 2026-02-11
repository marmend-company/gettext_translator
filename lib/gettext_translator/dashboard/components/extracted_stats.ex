defmodule GettextTranslator.Dashboard.Components.ExtractedStats do
  @moduledoc """
  Component for displaying newly extracted (pending) translations by language and domain,
  with batch translate controls and progress tracking.
  """
  use Phoenix.Component

  attr(:translations, :list, required: true)
  attr(:llm_provider_info, :map, default: %{configured: false})
  attr(:batch_translating, :boolean, default: false)
  attr(:batch_progress, :integer, default: 0)
  attr(:batch_total, :integer, default: 0)

  def render(assigns) do
    pending = Enum.filter(assigns.translations, fn t -> t.status == :pending end)
    total_pending = length(pending)

    # Group by language then domain, only include combos with pending entries
    groups =
      pending
      |> Enum.group_by(fn t -> {t.language_code, t.domain} end)
      |> Enum.sort_by(fn {{lang, domain}, _} -> {lang, domain} end)

    assigns = assign(assigns, pending: pending, total_pending: total_pending, groups: groups)

    ~H"""
    <section id="extracted-stats" class="dashboard-card mt-4">
      <div class="card-title-container">
        <h5 class="card-title">New Extracted Translations ({@total_pending})</h5>
        <%= if @total_pending > 0 && @llm_provider_info.configured do %>
          <button
            type="button"
            class="btn btn-warning"
            phx-click="batch_translate_all"
            disabled={@batch_translating}
          >
            <%= if @batch_translating do %>
              Translating...
            <% else %>
              Batch Translate All Pending ({@total_pending})
            <% end %>
          </button>
        <% end %>
      </div>

      <%= if @batch_translating do %>
        <div class="batch-progress-container">
          <div class="batch-progress-bar-wrapper">
            <div
              class="batch-progress-bar"
              style={"width: #{progress_percentage(@batch_progress, @batch_total)}%"}
            >
            </div>
          </div>
          <span class="batch-progress-text">
            Translating {@batch_progress} of {@batch_total}...
          </span>
        </div>
      <% end %>

      <%= if @total_pending == 0 do %>
        <p class="text-muted" style="padding: 1rem 0;">
          No pending translations. Use Extract & Merge to find new entries.
        </p>
      <% else %>
        <div class="card-info">
          <div class="dashboard-table-container">
            <table class="table table-hover table-striped">
              <thead>
                <tr>
                  <th>Language</th>
                  <th>Domain</th>
                  <th>Pending</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for {{language, domain}, entries} <- @groups do %>
                  <tr>
                    <td>{language}</td>
                    <td>{domain}</td>
                    <td class="text-warning fw-semibold">{length(entries)}</td>
                    <td>
                      <button
                        type="button"
                        phx-click="show_extracted"
                        phx-value-language={language}
                        phx-value-domain={domain}
                        class="btn btn-link"
                      >
                        View
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </section>
    """
  end

  defp progress_percentage(_progress, 0), do: 0
  defp progress_percentage(progress, total), do: round(progress / total * 100)
end
