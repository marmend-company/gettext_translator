defmodule GettextTranslator.Dashboard.Components.TranslationDetails do
  @moduledoc """
  Component for showing and editing translation details.
  """
  use Phoenix.Component
  import GettextTranslator.Util.Helper, only: [empty_string?: 1]

  attr(:viewing_language, :string, required: true)
  attr(:viewing_domain, :string, required: true)
  attr(:filtered_translations, :list, required: true)
  attr(:editing_id, :string, default: nil)
  attr(:llm_translating, :boolean, default: false)
  attr(:llm_translation_result, :map, default: nil)
  attr(:llm_provider_info, :map, default: %{configured: false})

  def render(assigns) do
    # Sort translations by changelog timestamp (newest first)
    filtered_translations =
      Enum.sort_by(
        assigns.filtered_translations,
        fn t ->
          case t do
            %{changelog_timestamp: timestamp} when is_binary(timestamp) ->
              case DateTime.from_iso8601(timestamp) do
                {:ok, dt, _} -> dt
                _ -> ~U[1970-01-01 00:00:00Z]
              end

            _ ->
              ~U[1970-01-01 00:00:00Z]
          end
        end,
        {:desc, DateTime}
      )

    assigns = assign(assigns, :filtered_translations, filtered_translations)

    ~H"""
    <section id="translation-details" class="dashboard-card mt-4">
      <div class="card-title-container">
        <h5 class="card-title">{@viewing_language} / {@viewing_domain} Translations</h5>
        <button type="button" phx-click="hide_translations" class="btn btn-link">
          Close
        </button>
      </div>

      <%= if @llm_provider_info.configured do %>
        <div class="llm-provider-info">
          <span class="llm-provider-label">LLM Provider:</span>
          <span class="llm-provider-value">
            {@llm_provider_info.adapter_name} — {@llm_provider_info.model}
          </span>
        </div>
      <% end %>

      <div class="card-info">
        <div class="dashboard-table-container">
          <table class="table table-hover table-striped">
            <colgroup>
              <col style="width: 40%;" />
              <col style="width: 40%;" />
              <col style="width: 7%;" />
              <col style="width: 7%;" />
              <col style="width: 6%;" />
            </colgroup>
            <thead>
              <tr>
                <th>Message ID</th>
                <th>Translation</th>
                <th>Status</th>
                <th>Changelog</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for t <- @filtered_translations do %>
                <tr>
                  <td style="vertical-align: middle; padding: 12px 0 12px 8px; text-align: left;">
                    {t.message_id}
                    <%= if t.type == :plural do %>
                      <div style="margin-top: 6px;">
                        (plural) {t.plural_id}
                      </div>
                    <% end %>
                  </td>

                  <%= if @editing_id == t.id do %>
                    <td colspan="3" class="p-2">
                      <.translation_edit_form
                        translation={t}
                        llm_translating={@llm_translating}
                        llm_translation_result={@llm_translation_result}
                        llm_provider_info={@llm_provider_info}
                      />
                    </td>
                  <% else %>
                    <td style="vertical-align: middle; padding: 12px 0 12px 8px; text-align: left;">
                      <%= if empty_string?(t.translation) do %>
                        <span class="text-danger">(empty)</span>
                      <% else %>
                        {t.translation}
                      <% end %>

                      <%= if t.type == :plural do %>
                        <div style="margin-top: 6px;">
                          <%= if empty_string?(t.plural_translation) do %>
                            <span class="text-danger">(empty)</span>
                          <% else %>
                            {t.plural_translation}
                          <% end %>
                        </div>
                      <% end %>
                    </td>

                    <td class="text-center" style="vertical-align: middle;">
                      <.status_badge status={t.status} />
                    </td>

                    <td class="text-center" style="vertical-align: middle;">
                      <%= if Map.has_key?(t, :changelog_status) and not is_nil(t.changelog_status) do %>
                        <div>
                          <.changelog_badge status={t.changelog_status} />
                          <%= if Map.has_key?(t, :changelog_timestamp) do %>
                            <div
                              class="small text-muted"
                              style="font-size: 0.75rem; white-space: nowrap;"
                            >
                              {format_date(t.changelog_timestamp)}
                            </div>
                          <% end %>
                        </div>
                      <% else %>
                        <span class="text-muted">-</span>
                      <% end %>
                    </td>

                    <td class="action-cell text-center" style="vertical-align: middle;">
                      <div class="action-buttons">
                        <button
                          phx-click="edit_translation"
                          phx-value-id={t.id}
                          class="btn btn-link p-0"
                        >
                          Edit
                        </button>

                        <%= cond do %>
                          <% t.changelog_status == "NEW" -> %>
                            <button
                              phx-click="approve_translation"
                              phx-value-id={t.id}
                              class="btn btn-link text-success p-0 d-block"
                            >
                              Approve
                            </button>
                          <% t.status == :pending -> %>
                            <button
                              phx-click="approve_translation"
                              phx-value-id={t.id}
                              class="btn btn-link text-success p-0 d-block"
                            >
                              Approve
                            </button>
                          <% true -> %>
                            <span></span>
                        <% end %>
                      </div>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  attr(:translation, :map, required: true)
  attr(:llm_translating, :boolean, default: false)
  attr(:llm_translation_result, :map, default: nil)
  attr(:llm_provider_info, :map, default: %{configured: false})

  def translation_edit_form(assigns) do
    translation_value =
      llm_or_existing_translation(assigns.llm_translation_result, assigns.translation)

    plural_value = llm_or_existing_plural(assigns.llm_translation_result, assigns.translation)
    assigns = assign(assigns, translation_value: translation_value, plural_value: plural_value)

    ~H"""
    <div class="translation-edit-container">
      <form phx-submit="save_translation" class="translation-form">
        <input type="hidden" name="_id" value={@translation.id} />
        <div class="form-group">
          <label class="form-label">Translation</label>
          <textarea name="translation" rows="2" class="form-control"><%= @translation_value %></textarea>
        </div>

        <%= if @translation.type == :plural do %>
          <div class="form-group mt-2">
            <label class="form-label">Plural Translation</label>
            <textarea name="plural_translation" rows="2" class="form-control"><%= @plural_value %></textarea>
          </div>
        <% end %>

        <div class="form-actions">
          <button type="button" phx-click="cancel_edit" class="btn btn-secondary btn-sm">
            Cancel
          </button>

          <button type="submit" class="btn btn-primary btn-sm">
            Save
          </button>
        </div>
      </form>

      <%= if @llm_provider_info.configured do %>
        <form phx-submit="llm_translate" class="llm-translate-form">
          <input type="hidden" name="_id" value={@translation.id} />
          <div class="form-group">
            <label class="form-label">Additional LLM Instructions (optional)</label>
            <textarea
              name="additional_instructions"
              rows="2"
              class="form-control"
              placeholder="e.g. keep it formal, this is a button label, use informal tone..."
            ></textarea>
          </div>

          <div class="form-actions">
            <button type="submit" class="btn btn-info btn-sm" disabled={@llm_translating}>
              <%= if @llm_translating do %>
                Translating...
              <% else %>
                LLM Translate
              <% end %>
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  def status_badge(assigns) do
    badge_class =
      case assigns.status do
        :pending -> "badge bg-warning text-dark"
        :translated -> "badge bg-success"
        :modified -> "badge bg-info"
      end

    label =
      case assigns.status do
        :pending -> "Pending"
        :translated -> "Translated"
        :modified -> "Modified"
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :label, label)

    ~H"""
    <span class={@badge_class}>
      {@label}
    </span>
    """
  end

  attr(:status, :string, required: true)

  def changelog_badge(assigns) do
    badge_class =
      case assigns.status do
        "NEW" -> "badge bg-success"
        "APPROVED" -> "badge bg-info"
        "MODIFIED" -> "badge bg-warning text-dark"
        _ -> "badge bg-secondary"
      end

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <span class={@badge_class}>
      {@status}
    </span>
    """
  end

  defp llm_or_existing_translation(%{id: id, translation: llm_translation}, %{id: id}) do
    llm_translation || ""
  end

  defp llm_or_existing_translation(_llm_result, translation) do
    translation.translation || ""
  end

  defp llm_or_existing_plural(%{id: id, plural_translation: llm_plural}, %{id: id}) do
    llm_plural || ""
  end

  defp llm_or_existing_plural(_llm_result, translation) do
    Map.get(translation, :plural_translation) || ""
  end

  defp format_date(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M")

      _ ->
        timestamp
    end
  end

  defp format_date(_), do: "-"
end
