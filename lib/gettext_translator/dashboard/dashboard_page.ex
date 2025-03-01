defmodule GettextTranslator.Dashboard.DashboardPage do
  @moduledoc """
  Phoenix LiveDashboard page for managing Gettext translations.

  This module integrates with Phoenix LiveDashboard to provide a UI for viewing
  and managing gettext translations.
  """

  use Phoenix.LiveDashboard.PageBuilder
  import Phoenix.Component
  import GettextTranslator.Util.Helper

  require Logger
  alias GettextTranslator.Dashboard.TranslationStore

  alias GettextTranslator.Dashboard.Components.{
    Header,
    TranslationStats,
    TranslationDetails
  }

  @default_gettext_path "priv/gettext"

  @impl true
  def init(opts) do
    gettext_path = opts[:gettext_path] || @default_gettext_path

    {:ok,
     %{
       gettext_path: gettext_path,
       translations_loaded: false
     }, application: opts[:application]}
  end

  @impl true
  def mount(_params, _session, socket) do
    # Get the gettext_path - fallback to default if not available
    gettext_path =
      case socket.assigns do
        %{page: %{gettext_path: path}} when is_binary(path) -> path
        _ -> @default_gettext_path
      end

    # Ensure the TranslationStore is started
    case ensure_translation_store_started() do
      :ok ->
        {:ok, assign(socket, gettext_path: gettext_path, translations: [])}

      {:error, reason} ->
        Logger.error("Failed to start TranslationStore: #{inspect(reason)}")
        {:ok, assign(socket, gettext_path: gettext_path, translations: [])}
    end
  end

  @impl true
  def menu_link(_, _) do
    {:ok, "Gettext Translations"}
  end

  @impl true
  def render(assigns) do
    translations = TranslationStore.list_translations()
    translations_count = length(translations)
    translations_loaded = translations_count > 0

    # Ensure gettext_path is assigned
    assigns =
      assigns
      |> Map.put(:translations_count, translations_count)
      |> Map.put(:translations_loaded, translations_loaded)
      |> Map.put(:translations, translations)

    ~H"""
    <div class="dashboard-container">
      <Header.render
        gettext_path={@gettext_path}
        translations_count={@translations_count}
        translations_loaded={@translations_loaded}
      />

      <%= if @translations_loaded do %>
        <TranslationStats.render translations={@translations} />

        <%= if assigns[:viewing_translations] do %>
          <TranslationDetails.render
            viewing_language={@viewing_language}
            viewing_domain={@viewing_domain}
            filtered_translations={@filtered_translations}
            editing_id={assigns[:editing_id]}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  # Needed for phx-change="noop"
  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_translations", %{"language" => language, "domain" => domain}, socket) do
    translations = TranslationStore.list_translations()

    # Filter translations by language and domain
    filtered_translations =
      Enum.filter(translations, fn t ->
        t.language_code == language && t.domain == domain
      end)

    socket =
      assign(socket,
        viewing_translations: true,
        viewing_language: language,
        viewing_domain: domain,
        filtered_translations: filtered_translations
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_translations", _params, socket) do
    socket =
      socket
      |> assign(viewing_translations: false)
      |> assign(filtered_translations: [])
      |> assign(editing_id: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_translation", %{"_id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  @impl true
  def handle_event(
        "save_translation",
        %{"_id" => id, "translation" => translation} = params,
        socket
      ) do
    # Extract the id and translation text from params
    updates = %{
      translation: translation,
      status: :modified
    }

    # Add plural_translation if it exists in params
    updates =
      if Map.has_key?(params, "plural_translation") do
        Map.put(updates, :plural_translation, params["plural_translation"])
      else
        updates
      end

    # Update the translation in ETS
    case TranslationStore.update_translation(id, updates) do
      {:ok, updated} ->
        # Update the filtered_translations in socket assigns
        filtered_translations =
          Enum.map(socket.assigns.filtered_translations, fn t ->
            if t.id == id, do: updated, else: t
          end)

        socket =
          socket
          |> assign(filtered_translations: filtered_translations)
          |> assign(editing_id: nil)
          |> put_flash(:info, "Translation updated")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to update: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve_translation", %{"_id" => id}, socket) do
    # Mark the translation as approved (change status to translated)
    case TranslationStore.update_translation(id, %{status: :translated}) do
      {:ok, updated} ->
        # Update the filtered_translations in socket assigns
        filtered_translations =
          Enum.map(socket.assigns.filtered_translations, fn t ->
            if t.id == id, do: updated, else: t
          end)

        socket =
          socket
          |> assign(filtered_translations: filtered_translations)
          |> put_flash(:info, "Translation approved")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to approve: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("load_translations", params, socket) do
    # Get path from params or fallback to socket assigns or default
    gettext_path = params["path"] || socket.assigns.gettext_path || @default_gettext_path

    # Log for debugging
    Logger.debug("Loading translations from path: #{inspect(gettext_path)}")

    # Clear the table before loading to avoid duplicates
    try do
      # Load translations
      result = TranslationStore.load_translations(gettext_path)
      translations = TranslationStore.list_translations()

      translations_by_language =
        Enum.map(translations, & &1.language_code) |> Enum.uniq() |> Enum.sort()

      case result do
        {:ok, count} ->
          {:noreply,
           assign(socket, translations_loaded: true, translations: translations_by_language)
           |> put_flash(:info, "Loaded #{count} translations")}

        {:error, reason} ->
          {:noreply,
           socket |> put_flash(:error, "Failed to load translations: #{inspect(reason)}")}
      end
    rescue
      e ->
        Logger.error("Error loading translations: #{inspect(e)}")

        {:noreply,
         socket |> put_flash(:error, "Error loading translations: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_event("save_to_files", _params, socket) do
    # Get all translations from the store
    translations = TranslationStore.list_translations()

    # Get all modified translations (status = :modified or :translated)
    modified_translations =
      Enum.filter(translations, fn t ->
        t.status == :modified || t.status == :translated
      end)

    if Enum.empty?(modified_translations) do
      {:noreply, socket |> put_flash(:info, "No changes to save")}
    else
      # Group translations by file path
      by_file = Enum.group_by(modified_translations, fn t -> t.file_path end)

      # Process each file
      results =
        Enum.map(by_file, fn {file_path, file_translations} ->
          save_translations_to_file(file_path, file_translations)
        end)

      # Count successful saves
      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      if successful > 0 do
        {:noreply, socket |> put_flash(:info, "Saved changes to #{successful} files")}
      else
        {:noreply, socket |> put_flash(:error, "Failed to save changes")}
      end
    end
  end

  # Helper function to ensure TranslationStore is started
  defp ensure_translation_store_started do
    case Process.whereis(TranslationStore) do
      nil ->
        # Not started - try to start it
        case TranslationStore.start_link() do
          {:ok, _pid} ->
            Logger.info("Started GettextTranslator.Dashboard.TranslationStore")
            :ok

          {:error, {:already_started, _pid}} ->
            Logger.info("GettextTranslator.Dashboard.TranslationStore already started")
            :ok

          error ->
            {:error, error}
        end

      _pid ->
        # Already started
        Logger.info("GettextTranslator.Dashboard.TranslationStore already running")
        :ok
    end
  end

  # Helper function to save translations to a PO file
  defp save_translations_to_file(file_path, translations) do
    # Parse existing PO file
    case Expo.PO.parse_file(file_path) do
      {:ok, po} ->
        # Create a map of message_id -> translation for quick lookup
        translations_map = Map.new(translations, fn t -> {t.message_id, t} end)

        # Update each message in the PO file
        updated_messages =
          Enum.map(po.messages, fn msg ->
            msg_id = get_message_id(msg)

            case Map.get(translations_map, msg_id) do
              # No changes for this message
              nil -> msg
              # Update the message with the new translation
              translation -> update_po_message(msg, translation)
            end
          end)

        # Create updated PO file
        updated_po = %{po | messages: updated_messages}

        # Write the file
        case File.write(file_path, Expo.PO.compose(updated_po)) do
          :ok -> {:ok, file_path}
          error -> error
        end

      error ->
        error
    end
  end

  # Helper function to get the message ID from a PO message
  defp get_message_id(%Expo.Message.Singular{msgid: msgid}), do: Enum.join(msgid, "")
  defp get_message_id(%Expo.Message.Plural{msgid: msgid}), do: Enum.join(msgid, "")

  # Helper function to update a PO message with new translation
  defp update_po_message(%Expo.Message.Singular{} = msg, translation) do
    %{msg | msgstr: [translation.translation]}
  end

  defp update_po_message(%Expo.Message.Plural{} = msg, translation) do
    %{
      msg
      | msgstr: %{
          0 => [translation.translation],
          1 => [translation.plural_translation]
        }
    }
  end
end

# Header Component
defmodule GettextTranslator.Dashboard.Components.Header do
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
            <button type="submit" class="btn btn-primary">
              <%= if @translations_loaded, do: "Reload", else: "Load" %> Translations
            </button>
          </form>

          <%= if @translations_loaded do %>
            <form phx-submit="save_to_files" phx-change="noop">
              <button type="submit" class="btn btn-success">
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

# Translation Stats Component
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
                <th>Translated</th>
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
                    pending = Enum.count(domain_translations, & &1.status == :pending)
                    translated = Enum.count(domain_translations, & &1.status == :translated)
                  %>
                  <tr>
                    <%= if index == 0 do %>
                      <td rowspan={length(domains)} class="align-middle"><%= language %></td>
                    <% end %>
                    <td><%= domain %></td>
                    <td><%= count %></td>
                    <td class={pending_class(pending)}><%= pending %></td>
                    <td class={translated_class(translated)}><%= translated %></td>
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

  defp translated_class(0), do: ""
  defp translated_class(_), do: "text-success fw-semibold"
end

# Translation Details Component
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

  def render(assigns) do
    ~H"""
    <section id="translation-details" class="dashboard-card mt-4">
      <div class="card-title-container">
        <h5 class="card-title"><%= @viewing_language %> / <%= @viewing_domain %> Translations</h5>
        <button
          type="button"
          phx-click="hide_translations"
          class="btn btn-link"
        >
          <i class="fa fa-times"></i> Close
        </button>
      </div>

      <div class="card-info">
        <div class="dashboard-table-container">
          <table class="table table-hover table-striped">
            <thead>
              <tr>
                <th>Message ID</th>
                <th>Translation</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for t <- @filtered_translations do %>
                <tr>
                  <td class="message-id-cell">
                    <div class="message-id" title={t.message_id}>
                      <%= t.message_id %>
                    </div>

                    <%= if t.type == :plural do %>
                      <div class="plural-id" title={t.plural_id}>
                        (plural) <%= t.plural_id %>
                      </div>
                    <% end %>
                  </td>

                  <%= if @editing_id == t.id do %>
                    <td colspan="3" class="p-2">
                      <.translation_edit_form translation={t} />
                    </td>
                  <% else %>
                    <td class="translation-cell">
                      <%= if empty_string?(t.translation) do %>
                        <span class="text-danger">(empty)</span>
                      <% else %>
                        <div class="translation-content">
                          <%= t.translation %>
                        </div>
                      <% end %>

                      <%= if t.type == :plural do %>
                        <div class="plural-translation">
                          <%= if empty_string?(t.plural_translation) do %>
                            <span class="text-danger">(empty)</span>
                          <% else %>
                            <div class="translation-content">
                              <%= t.plural_translation %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </td>

                    <td>
                      <.status_badge status={t.status} />
                    </td>

                    <td class="action-cell">
                      <div class="action-buttons">
                        <button
                          phx-click="edit_translation"
                          phx-value-id={t.id}
                          class="btn btn-link"
                        >
                          Edit
                        </button>

                        <%= if t.status == :pending do %>
                          <button
                            phx-click="approve_translation"
                            phx-value-id={t.id}
                            class="btn btn-link text-success"
                          >
                            Approve
                          </button>
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

  def translation_edit_form(assigns) do
    ~H"""
    <form phx-submit="save_translation" class="translation-form">
      <input type="hidden" name="_id" value={@translation.id} />
      <div class="form-group">
        <label class="form-label">Translation</label>
        <textarea
          name="translation"
          rows="2"
          class="form-control"
        ><%= @translation.translation || "" %></textarea>
      </div>

      <%= if @translation.type == :plural do %>
        <div class="form-group mt-2">
          <label class="form-label">Plural Translation</label>
          <textarea
            name="plural_translation"
            rows="2"
            class="form-control"
          ><%= @translation.plural_translation || "" %></textarea>
        </div>
      <% end %>

      <div class="form-actions">
        <button
          type="button"
          phx-click="cancel_edit"
          class="btn btn-secondary btn-sm"
        >
          Cancel
        </button>

        <button
          type="submit"
          class="btn btn-primary btn-sm"
        >
          Save
        </button>
      </div>
    </form>
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
      <%= @label %>
    </span>
    """
  end
end

# CSS for Dashboard
defmodule GettextTranslator.Dashboard.GettextDashboardCSS do
  @moduledoc """
  Provides CSS styles for the Gettext Translator Dashboard that match
  Phoenix LiveDashboard's look and feel.
  """

  def styles do
    """
    /* Dashboard Container */
    .dashboard-container {
      padding: 1rem;
    }

    /* Card styles - matches LiveDashboard */
    .dashboard-card {
      background-color: #fff;
      border-radius: 0.5rem;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
      margin-bottom: 1rem;
      padding: 1rem;
    }

    .card-title {
      color: #333;
      font-size: 1.25rem;
      font-weight: 600;
      margin-bottom: 1rem;
    }

    .card-title-container {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1rem;
    }

    /* Stats container */
    .dashboard-stats-container {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
    }

    .dashboard-stat {
      display: flex;
      flex-direction: column;
      margin-right: 2rem;
    }

    .dashboard-stat-label {
      color: #666;
      font-size: 0.875rem;
    }

    .dashboard-stat-value {
      font-size: 1rem;
      font-weight: 500;
    }

    .dashboard-controls-container {
      display: flex;
      gap: 0.5rem;
      margin-left: auto;
    }

    /* Table styles */
    .dashboard-table-container {
      overflow-x: auto;
    }

    .table {
      width: 100%;
      margin-bottom: 1rem;
      color: #212529;
      border-collapse: collapse;
    }

    .table th,
    .table td {
      padding: 0.75rem;
      vertical-align: top;
      border-top: 1px solid #dee2e6;
    }

    .table thead th {
      vertical-align: bottom;
      border-bottom: 2px solid #dee2e6;
      font-weight: 600;
      text-align: left;
    }

    .table-striped tbody tr:nth-of-type(odd) {
      background-color: rgba(0, 0, 0, 0.05);
    }

    .table-hover tbody tr:hover {
      background-color: rgba(0, 0, 0, 0.075);
    }

    /* Message ID cell */
    .message-id-cell {
      font-family: monospace;
      font-size: 0.875rem;
      max-width: 20rem;
    }

    .message-id {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      width: 100%;
    }

    .plural-id {
      color: #6c757d;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      width: 100%;
      margin-top: 0.25rem;
    }

    /* Translation cell */
    .translation-cell {
      font-family: monospace;
      font-size: 0.875rem;
    }

    .translation-content {
      word-break: break-all;
    }

    .plural-translation {
      color: #6c757d;
      margin-top: 0.5rem;
    }

    /* Buttons */
    .btn {
      display: inline-block;
      font-weight: 400;
      text-align: center;
      vertical-align: middle;
      user-select: none;
      border: 1px solid transparent;
      padding: 0.375rem 0.75rem;
      font-size: 0.875rem;
      line-height: 1.5;
      border-radius: 0.25rem;
      transition: color 0.15s, background-color 0.15s, border-color 0.15s;
      cursor: pointer;
    }

    .btn-primary {
      background-color: #3490dc;
      color: white;
    }

    .btn-primary:hover {
      background-color: #2779bd;
    }

    .btn-success {
      background-color: #38c172;
      color: white;
    }

    .btn-success:hover {
      background-color: #2d995b;
    }

    .btn-secondary {
      background-color: #6c757d;
      color: white;
    }

    .btn-secondary:hover {
      background-color: #5a6268;
    }

    .btn-link {
      font-weight: 400;
      color: #3490dc;
      text-decoration: none;
      background-color: transparent;
      border: none;
      padding: 0;
    }

    .btn-link:hover {
      color: #1d68a7;
      text-decoration: underline;
    }

    .btn-sm {
      padding: 0.25rem 0.5rem;
      font-size: 0.75rem;
    }

    /* Status badges */
    .badge {
      display: inline-block;
      padding: 0.35em 0.65em;
      font-size: 0.75em;
      font-weight: 700;
      line-height: 1;
      text-align: center;
      white-space: nowrap;
      vertical-align: baseline;
      border-radius: 0.25rem;
    }

    .bg-warning {
      background-color: #ffc107;
    }

    .bg-success {
      background-color: #28a745;
      color: white;
    }

    .bg-info {
      background-color: #17a2b8;
      color: white;
    }

    .text-warning {
      color: #ffc107;
    }

    .text-success {
      color: #28a745;
    }

    .text-danger {
      color: #dc3545;
    }

    .fw-semibold {
      font-weight: 600;
    }

    /* Forms */
    .translation-form {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }

    .form-group {
      margin-bottom: 0.5rem;
    }

    .form-label {
      display: block;
      margin-bottom: 0.25rem;
      font-size: 0.875rem;
      font-weight: 500;
    }

    .form-control {
      display: block;
      width: 100%;
      padding: 0.375rem 0.75rem;
      font-size: 0.875rem;
      line-height: 1.5;
      color: #495057;
      background-color: #fff;
      background-clip: padding-box;
      border: 1px solid #ced4da;
      border-radius: 0.25rem;
      transition: border-color 0.15s;
    }

    .form-control:focus {
      border-color: #80bdff;
      outline: 0;
      box-shadow: 0 0 0 0.2rem rgba(0, 123, 255, 0.25);
    }

    .form-actions {
      display: flex;
      justify-content: flex-end;
      gap: 0.5rem;
      margin-top: 0.75rem;
    }

    .align-middle {
      vertical-align: middle !important;
    }

    .mt-4 {
      margin-top: 1.5rem;
    }
    """
  end
end
