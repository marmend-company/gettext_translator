# defmodule GettextTranslator.Dashboard.TranslationDetailsComponent do
#   @moduledoc """
#   Component for showing and editing translation details.
#   """
#   use Phoenix.Component
#   import GettextTranslator.Util.Helper, only: [empty_string?: 1]

#   attr(:viewing_language, :string, required: true)
#   attr(:viewing_domain, :string, required: true)
#   attr(:filtered_translations, :list, required: true)
#   attr(:editing_id, :string, default: nil)

#   def render(assigns) do
#     # Sort translations by changelog timestamp (newest first), prioritizing NEW status
#     filtered_translations =
#       Enum.sort_by(
#         assigns.filtered_translations,
#         fn t ->
#           # First sort by changelog status (NEW first, then APPROVED, then others)
#           status_priority =
#             case t do
#               %{changelog_status: "NEW"} -> 0
#               %{changelog_status: "APPROVED"} -> 1
#               _ -> 2
#             end

#           # Then sort by timestamp
#           timestamp =
#             case t do
#               %{changelog_timestamp: ts} when is_binary(ts) ->
#                 case DateTime.from_iso8601(ts) do
#                   {:ok, dt, _} -> dt
#                   _ -> ~U[1970-01-01 00:00:00Z]
#                 end

#               _ ->
#                 ~U[1970-01-01 00:00:00Z]
#             end

#           {status_priority, timestamp}
#         end,
#         :asc
#       )

#     assigns = assign(assigns, :filtered_translations, filtered_translations)

#     ~H"""
#     <section id="translation-details" class="dashboard-card mt-4">
#       <div class="card-title-container">
#         <h5 class="card-title"><%= @viewing_language %> / <%= @viewing_domain %> Translations</h5>
#         <button
#           type="button"
#           phx-click="hide_translations"
#           class="btn btn-link"
#         >
#           <i class="fa fa-times"></i> Close
#         </button>
#       </div>

#       <div class="card-info">
#         <div class="dashboard-table-container">
#           <table class="table table-hover table-striped">
#             <thead>
#               <tr>
#                 <th>Message ID</th>
#                 <th>Translation</th>
#                 <th>Status</th>
#                 <th>Changelog</th>
#                 <th>Actions</th>
#               </tr>
#             </thead>
#             <tbody>
#               <%= for t <- @filtered_translations do %>
#                 <tr>
#                   <td class="message-id-cell">
#                     <div class="message-id" title={t.message_id}>
#                       <%= t.message_id %>
#                     </div>

#                     <%= if t.type == :plural do %>
#                       <div class="plural-id" title={t.plural_id}>
#                         (plural) <%= t.plural_id %>
#                       </div>
#                     <% end %>
#                   </td>

#                   <%= if @editing_id == t.id do %>
#                     <td colspan="3" class="p-2">
#                       <.translation_edit_form translation={t} />
#                     </td>
#                   <% else %>
#                     <td class="translation-cell">
#                       <%= if empty_string?(t.translation) do %>
#                         <span class="text-danger">(empty)</span>
#                       <% else %>
#                         <div class="translation-content">
#                           <%= t.translation %>
#                         </div>
#                       <% end %>

#                       <%= if t.type == :plural do %>
#                         <div class="plural-translation">
#                           <%= if empty_string?(t.plural_translation) do %>
#                             <span class="text-danger">(empty)</span>
#                           <% else %>
#                             <div class="translation-content">
#                               <%= t.plural_translation %>
#                             </div>
#                           <% end %>
#                         </div>
#                       <% end %>
#                     </td>

#                     <td>
#                       <.status_badge status={t.status} />
#                     </td>

#                     <td>
#                       <%= if Map.has_key?(t, :changelog_status) and not is_nil(t.changelog_status) do %>
#                         <.changelog_badge status={t.changelog_status} />
#                         <div class="small text-muted">
#                           <%= format_date(t.changelog_timestamp) %>
#                         </div>
#                       <% else %>
#                         <span class="text-muted">-</span>
#                       <% end %>
#                     </td>

#                     <td class="action-cell">
#                       <div class="action-buttons">
#                         <button
#                           phx-click="edit_translation"
#                           phx-value-id={t.id}
#                           class="btn btn-link"
#                         >
#                           Edit
#                         </button>

#                         <%= cond do %>
#                           <% t.changelog_status == "NEW" -> %>
#                             <button
#                               phx-click="approve_translation"
#                               phx-value-id={t.id}
#                               class="btn btn-link text-success"
#                             >
#                               Approve
#                             </button>
#                           <% t.status == :pending -> %>
#                             <button
#                               phx-click="approve_translation"
#                               phx-value-id={t.id}
#                               class="btn btn-link text-success"
#                             >
#                               Approve
#                             </button>
#                           <% true -> %>
#                             <span></span>
#                         <% end %>
#                       </div>
#                     </td>
#                   <% end %>
#                 </tr>
#               <% end %>
#             </tbody>
#           </table>
#         </div>
#       </div>
#     </section>
#     """
#   end

#   attr(:translation, :map, required: true)

#   def translation_edit_form(assigns) do
#     ~H"""
#     <form phx-submit="save_translation" class="translation-form">
#       <input type="hidden" name="_id" value={@translation.id} />
#       <div class="form-group">
#         <label class="form-label">Translation</label>
#         <textarea
#           name="translation"
#           rows="2"
#           class="form-control"
#         ><%= @translation.translation || "" %></textarea>
#       </div>

#       <%= if @translation.type == :plural do %>
#         <div class="form-group mt-2">
#           <label class="form-label">Plural Translation</label>
#           <textarea
#             name="plural_translation"
#             rows="2"
#             class="form-control"
#           ><%= @translation.plural_translation || "" %></textarea>
#         </div>
#       <% end %>

#       <div class="form-actions">
#         <button
#           type="button"
#           phx-click="cancel_edit"
#           class="btn btn-secondary btn-sm"
#         >
#           Cancel
#         </button>

#         <button
#           type="submit"
#           class="btn btn-primary btn-sm"
#         >
#           Save
#         </button>
#       </div>
#     </form>
#     """
#   end

#   attr(:status, :atom, required: true)

#   def status_badge(assigns) do
#     badge_class =
#       case assigns.status do
#         :pending -> "badge bg-warning text-dark"
#         :translated -> "badge bg-success"
#         :modified -> "badge bg-info"
#       end

#     label =
#       case assigns.status do
#         :pending -> "Pending"
#         :translated -> "Translated"
#         :modified -> "Modified"
#       end

#     assigns = assign(assigns, :badge_class, badge_class)
#     assigns = assign(assigns, :label, label)

#     ~H"""
#     <span class={@badge_class}>
#       <%= @label %>
#     </span>
#     """
#   end

#   attr(:status, :string, required: true)

#   def changelog_badge(assigns) do
#     badge_class =
#       case assigns.status do
#         "NEW" -> "badge bg-success"
#         "APPROVED" -> "badge bg-info"
#         _ -> "badge bg-secondary"
#       end

#     assigns = assign(assigns, :badge_class, badge_class)

#     ~H"""
#     <span class={@badge_class}>
#       <%= @status %>
#     </span>
#     """
#   end

#   defp format_date(timestamp) when is_binary(timestamp) do
#     case DateTime.from_iso8601(timestamp) do
#       {:ok, dt, _} ->
#         Calendar.strftime(dt, "%Y-%m-%d %H:%M")

#       _ ->
#         timestamp
#     end
#   end

#   defp format_date(_), do: "-"
# end
