defmodule GettextTranslator.Dashboard.Components.TranslatedStats do
  @moduledoc """
  Component for displaying batch-translated translations from the current session,
  grouped by language and domain for review, approval, and editing.
  """
  use Phoenix.Component

  attr(:translated_entries, :list, required: true)

  def render(assigns) do
    total = length(assigns.translated_entries)

    groups =
      assigns.translated_entries
      |> Enum.group_by(fn t -> {t.language_code, t.domain} end)
      |> Enum.sort_by(fn {{lang, domain}, _} -> {lang, domain} end)

    assigns = assign(assigns, total: total, groups: groups)

    ~H"""
    <section id="translated-stats" class="dashboard-card mt-4">
      <div class="card-title-container">
        <h5 class="card-title">New Translated — Review ({@total})</h5>
      </div>

      <p class="text-muted" style="font-size: 0.875rem; margin-bottom: 1rem;">
        These translations were created during this session. Review, edit, or approve them before saving.
      </p>

      <div class="card-info">
        <div class="dashboard-table-container">
          <table class="table table-hover table-striped">
            <thead>
              <tr>
                <th>Language</th>
                <th>Domain</th>
                <th>Translated</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for {{language, domain}, entries} <- @groups do %>
                <tr>
                  <td>{language}</td>
                  <td>{domain}</td>
                  <td class="text-success fw-semibold">{length(entries)}</td>
                  <td>
                    <button
                      type="button"
                      phx-click="show_translated"
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
    </section>
    """
  end
end
