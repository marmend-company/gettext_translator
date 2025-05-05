defmodule GettextTranslator.Dashboard.Components.TranslationStats do
  @moduledoc """
  Component for displaying translation statistics.
  """
  use Phoenix.Component

  attr(:translations, :list, required: true)

  def render(assigns) do
    ~H"""
    <section id="translation-stats" class="dashboard-card mt-4">
      <h5 class="card-title">Translation Stats</h5>
      <div class="card-info">
        <div class="dashboard-table-container">
          <table class="table table-hover table-striped">
            <thead>
              <tr>
                <th>Language</th>
                <th>Domain</th>
                <th>Count</th>
                <th>Pending</th>
                <th>New</th>
                <th>Approved</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for language <- @translations |> Enum.map(& &1.language_code) |> Enum.uniq() |> Enum.sort() do %>
                <%
                  by_language = Enum.filter(@translations, & &1.language_code == language)
                  domains = Enum.map(by_language, & &1.domain) |> Enum.uniq() |> Enum.sort()
                %>
                <%= for {domain, index} <- Enum.with_index(domains) do %>
                  <%
                    domain_translations = Enum.filter(by_language, & &1.domain == domain)
                    count = length(domain_translations)

                    # Standard status counts
                    pending = Enum.count(domain_translations, & &1.status == :pending)

                    # Changelog status counts
                    new_count = Enum.count(domain_translations, & &1.changelog_status == "NEW")
                    approved_count = Enum.count(domain_translations, & &1.changelog_status == "APPROVED")
                  %>
                  <tr>
                    <%= if index == 0 do %>
                      <td rowspan={length(domains)} class="align-middle"><%= language %></td>
                    <% end %>
                    <td><%= domain %></td>
                    <td><%= count %></td>
                    <td class={pending_class(pending)}><%= pending %></td>
                    <td class="text-success fw-semibold"><%= new_count %></td>
                    <td class="text-info fw-semibold"><%= approved_count %></td>
                    <td>
                      <button
                        type="button"
                        phx-click="show_translations"
                        phx-value-language={language}
                        phx-value-domain={domain}
                        class="btn btn-link"
                      >
                        View
                      </button>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  defp pending_class(0), do: ""
  defp pending_class(_), do: "text-warning fw-semibold"
end
