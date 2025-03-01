defmodule GettextTranslator.Dashboard.DashboardPage do
  @moduledoc """
  Phoenix LiveDashboard page for managing Gettext translations.

  This module integrates with Phoenix LiveDashboard to provide a UI for viewing
  and managing gettext translations.
  """

  use Phoenix.LiveDashboard.PageBuilder
  import GettextTranslator.Util.Helper

  if Code.ensure_loaded?(Phoenix.HTML) do
    import Phoenix.Component
  end

  require Logger
  alias GettextTranslator.Dashboard.TranslationStore

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
    case Process.whereis(TranslationStore) do
      nil ->
        # Not started - try to start it
        case TranslationStore.start_link() do
          {:ok, _pid} ->
            Logger.info("Started GettextTranslator.Dashboard.TranslationStore")
            {:ok, assign(socket, gettext_path: gettext_path) |> assign(:translations, [])}

          {:error, {:already_started, _pid}} ->
            Logger.info("GettextTranslator.Dashboard.TranslationStore already started")
            {:ok, assign(socket, gettext_path: gettext_path)}

          error ->
            Logger.error("Failed to start TranslationStore: #{inspect(error)}")
            {:ok, assign(socket, gettext_path: gettext_path)}
        end

      _pid ->
        # Already started
        Logger.info("GettextTranslator.Dashboard.TranslationStore already running")
        {:ok, assign(socket, gettext_path: gettext_path) |> assign(:translations, [])}
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

    ~H"""
    <div class="bg-white p-4">
      <h1 class="text-xl font-bold">Gettext Translations</h1>

      <div class="mt-4 p-4 bg-gray-100 rounded">
        <div class="flex justify-between items-center">
          <div>
            <p class="font-semibold">Gettext path: <%= @gettext_path %></p>
            <p>Currently loaded translations: <%= @translations_count %></p>
          </div>

          <div class="flex space-x-2">
            <form phx-submit="load_translations" phx-change="noop">
              <input type="hidden" name="path" value={@gettext_path} />
              <button
                type="submit"
                class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
              >
                <%= if @translations_loaded, do: "Reload", else: "Load" %> Translations
              </button>
            </form>

            <%= if @translations_loaded do %>
              <form phx-submit="save_to_files" phx-change="noop">
                <button
                  type="submit"
                  class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600"
                >
                  Save Changes to Files
                </button>
              </form>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @translations_loaded do %>
        <div class="mt-4">
          <h2 class="text-lg font-semibold">Translation Stats</h2>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-sm">
              <thead>
                <tr class="bg-gray-200">
                  <th class="p-2 text-left">Language</th>
                  <th class="p-2 text-left">Domain</th>
                  <th class="p-2 text-left">Count</th>
                  <th class="p-2 text-left">Pending</th>
                  <th class="p-2 text-left">Translated</th>
                  <th class="p-2 text-left">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for language <- @translations do %>
                  <%
                    by_language = Enum.filter(translations, & &1.language_code == language)
                    domains = Enum.map(by_language, & &1.domain) |> Enum.uniq() |> Enum.sort()
                  %>
                  <%= for {domain, index} <- Enum.with_index(domains) do %>
                    <%
                      domain_translations = Enum.filter(by_language, & &1.domain == domain)
                      count = length(domain_translations)
                      pending = Enum.count(domain_translations, & &1.status == :pending)
                      translated = Enum.count(domain_translations, & &1.status == :translated)

                      # Only show language in first row for each language group
                      lang_cell = if index == 0 do
                        Phoenix.HTML.raw("<td rowspan=\"#{length(domains)}\" class=\"p-2 border-t\">#{language}</td>")
                      else
                        Phoenix.HTML.raw("")
                      end
                    %>
                    <tr class="border-t">
                      <%= lang_cell %>
                      <td class="p-2"><%= domain %></td>
                      <td class="p-2"><%= count %></td>
                      <td class="p-2"> <%= if pending > 0, do: "text-yellow-600 font-medium" %>">
                        <%= pending %>
                      </td>
                      <td class="p-2"> <%= if translated > 0, do: "text-green-600 font-medium" %>">
                        <%= translated %>
                      </td>
                      <td class="p-2">
                        <button
                          type="button"
                          phx-click="show_translations"
                          phx-value-language={language}
                          phx-value-domain={domain}
                          class="text-blue-600 underline hover:text-blue-800"
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

        <%= if assigns[:viewing_translations] do %>
          <div class="mt-8">
            <div class="flex justify-between items-center">
              <h2 class="text-lg font-semibold">
                <%= @viewing_language %> / <%= @viewing_domain %> Translations
              </h2>
              <button
                type="button"
                phx-click="hide_translations"
                class="text-blue-600 hover:text-blue-800"
              >
                &times; Close
              </button>
            </div>

            <div class="overflow-x-auto mt-4">
              <table class="w-full text-sm">
                <thead>
                  <tr class="bg-gray-200">
                    <th class="p-2 text-left">Message ID</th>
                    <th class="p-2 text-left">Translation</th>
                    <th class="p-2 text-left">Status</th>
                    <th class="p-2 text-left">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for t <- @filtered_translations do %>
                    <tr class="border-t hover:bg-gray-50">
                      <td class="p-2 align-top font-mono text-xs max-w-xs">
                        <div class="truncate w-60" title={t.message_id}>
                          <%= t.message_id %>
                        </div>

                        <%= if t.type == :plural do %>
                          <div class="mt-1 text-gray-500 truncate w-60" title={t.plural_id}>
                            (plural) <%= t.plural_id %>
                          </div>
                        <% end %>
                      </td>

                      <%= if assigns[:editing_id] && assigns.editing_id == t.id do %>
                        <td class="p-2" colspan="3">
                          <form phx-submit="save_translation" class="space-y-2">
                            <input type="hidden" name="id" value={t.id} />

                            <div>
                              <label class="block text-xs font-medium">Translation</label>
                              <textarea
                                name="translation"
                                rows="2"
                                class="w-full border rounded p-1 text-sm"
                              ><%= t.translation || "" %></textarea>
                            </div>

                            <%= if t.type == :plural do %>
                              <div>
                                <label class="block text-xs font-medium">Plural Translation</label>
                                <textarea
                                  name="plural_translation"
                                  rows="2"
                                  class="w-full border rounded p-1 text-sm"
                                ><%= t.plural_translation || "" %></textarea>
                              </div>
                            <% end %>

                            <div class="flex justify-end space-x-2">
                              <button
                                type="button"
                                phx-click="cancel_edit"
                                class="px-2 py-1 text-xs bg-gray-100 rounded"
                              >
                                Cancel
                              </button>

                              <button
                                type="submit"
                                class="px-2 py-1 text-xs bg-blue-500 text-white rounded"
                              >
                                Save
                              </button>
                            </div>
                          </form>
                        </td>
                      <% else %>
                        <td class="p-2 align-top font-mono text-xs">
                          <%= if empty_string?(t.translation) do %>
                            <span class="text-red-500 italic">(empty)</span>
                          <% else %>
                            <div class="break-all">
                              <%= t.translation %>
                            </div>
                          <% end %>

                          <%= if t.type == :plural do %>
                            <div class="mt-1 text-gray-500">
                              <%= if empty_string?(t.plural_translation) do %>
                                <span class="text-red-500 italic">(empty)</span>
                              <% else %>
                                <div class="break-all">
                                  <%= t.plural_translation %>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        </td>

                        <td class="p-2 align-top">
                          <%= case t.status do %>
                            <% :pending -> %>
                              <span class="inline-block px-2 py-1 bg-yellow-100 text-yellow-800 text-xs rounded-full">
                                Pending
                              </span>
                            <% :translated -> %>
                              <span class="inline-block px-2 py-1 bg-green-100 text-green-800 text-xs rounded-full">
                                Translated
                              </span>
                            <% :modified -> %>
                              <span class="inline-block px-2 py-1 bg-blue-100 text-blue-800 text-xs rounded-full">
                                Modified
                              </span>
                          <% end %>
                        </td>

                        <td class="p-2 align-top whitespace-nowrap">
                          <div class="flex space-x-2">
                            <button
                              phx-click="edit_translation"
                              phx-value-id={t.id}
                              class="text-blue-600 hover:text-blue-800 text-sm"
                            >
                              Edit
                            </button>

                            <%= if t.status == :pending do %>
                              <button
                                phx-click="approve_translation"
                                phx-value-id={t.id}
                                class="text-green-600 hover:text-green-800 text-sm"
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
  def handle_event("edit_translation", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  @impl true
  def handle_event(
        "save_translation",
        %{"id" => id, "translation" => translation} = params,
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
          |> assign(:translations, filtered_translations)
          |> assign(editing_id: nil)
          |> put_flash(:info, "Translation updated")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to update: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve_translation", %{"id" => id}, socket) do
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
      translations = GettextTranslator.Dashboard.TranslationStore.list_translations()
      translations = Enum.map(translations, & &1.language_code) |> Enum.uniq() |> Enum.sort()
      Logger.debug("Translation load result: #{inspect(translations)}")

      case result do
        {:ok, count} ->
          {:noreply,
           assign(socket, translations_loaded: true)
           |> assign(:translations, translations)
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
              nil ->
                # No changes for this message
                msg

              translation ->
                # Update the message with the new translation
                update_po_message(msg, translation)
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
