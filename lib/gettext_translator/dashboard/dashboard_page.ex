defmodule GettextTranslator.Dashboard.DashboardPage do
  @moduledoc """
  Phoenix LiveDashboard page for managing Gettext translations.

  This module integrates with Phoenix LiveDashboard to provide a UI for viewing
  and managing gettext translations.
  """

  use Phoenix.LiveDashboard.PageBuilder
  import Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  require Logger
  alias GettextTranslator.Dashboard.TranslationStore

  alias GettextTranslator.Dashboard.Components.{
    Header,
    TranslationDetails,
    TranslationStats
  }

  @config_table :gettext_translator_dashboard_config

  @impl true
  def init(opts) do
    gettext_path = Keyword.get(opts, :gettext_path)
    application = Keyword.get(opts, :application)

    # Make sure we have a path
    unless gettext_path do
      raise ArgumentError, "Missing required option :gettext_path in #{inspect(opts)}"
    end

    # Store configuration in ETS - safely create or update
    store_config(gettext_path, application)

    {:ok, %{}}
  end

  @impl true
  def mount(_params, _session, socket) do
    # Get path from ETS
    gettext_path = get_config(:gettext_path)

    if gettext_path do
      # Ensure the TranslationStore is started
      case ensure_translation_store_started() do
        :ok ->
          {:ok, assign(socket, gettext_path: gettext_path, translations: [])}

        {:error, reason} ->
          Logger.error("Failed to start TranslationStore: #{inspect(reason)}")
          {:ok, assign(socket, gettext_path: gettext_path, translations: [])}
      end
    else
      {:ok,
       assign(socket, error: "Configuration error: gettext_path not provided", translations: [])}
    end
  end

  # Safely create or update ETS table with configuration
  defp store_config(gettext_path, application) do
    # Create table if it doesn't exist
    if :ets.whereis(@config_table) == :undefined do
      :ets.new(@config_table, [:set, :public, :named_table])
    end

    # Store configuration
    :ets.insert(@config_table, {:gettext_path, gettext_path})

    if application do
      :ets.insert(@config_table, {:application, application})
    end
  end

  # Safely get configuration from ETS
  defp get_config(key) do
    # First ensure the table exists
    ensure_config_table()

    # Then try to get the value
    lookup_config(key)
  end

  defp ensure_config_table do
    case :ets.info(@config_table) do
      :undefined ->
        # Table doesn't exist, create it and ignore any errors
        :ets.new(@config_table, [:set, :public, :named_table])
        :ok

      _ ->
        :ok
    end
  catch
    :error, _ -> :ok
  end

  defp lookup_config(key) do
    case :ets.lookup(@config_table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  catch
    :error, _ -> nil
  end

  @impl true
  def menu_link(_, _) do
    {:ok, "Gettext Translations"}
  end

  @impl true
  def render(assigns) do
    # Check if we have a gettext_path
    if Map.has_key?(assigns, :error) do
      assigns = assign(assigns, :translations, [])

      ~H"""
      <div class="dashboard-container">
        <div class="alert alert-danger">
          <%= @error %>
        </div>
      </div>
      """
    else
      translations = TranslationStore.list_translations()
      translations_count = length(translations)
      translations_loaded = translations_count > 0

      # Ensure gettext_path is assigned
      assigns =
        assigns
        |> assign(translations_count: translations_count)
        |> assign(translations_loaded: translations_loaded)
        |> assign(translations: translations)

      ~H"""
      <style>
        <%= raw GettextTranslator.Dashboard.GettextDashboardCSS.styles() %>
      </style>
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
      socket
      |> assign(viewing_translations: true)
      |> assign(viewing_language: language)
      |> assign(viewing_domain: domain)
      |> assign(filtered_translations: filtered_translations)

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
        %{"_id" => id, "translation" => translation} = params,
        socket
      ) do
    # Build updates map with optional plural_translation
    updates =
      %{
        translation: translation,
        status: :modified
      }
      |> maybe_add_plural_translation(params)

    case TranslationStore.update_translation(id, updates) do
      {:ok, updated} ->
        updated = update_changelog(updated, params)

        # Update filtered_translations in socket assigns
        filtered_translations =
          Enum.map(socket.assigns.filtered_translations, fn t ->
            if t.id == id, do: updated, else: t
          end)

        {:noreply,
         socket
         |> assign(filtered_translations: filtered_translations)
         |> assign(editing_id: nil)
         |> put_flash(:info, "Translation updated")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to update: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve_translation", %{"id" => id}, socket) do
    # Mark the translation as approved (change status to translated)
    case TranslationStore.update_translation(id, %{status: :translated}) do
      {:ok, updated} ->
        # Update the changelog status if present
        updated =
          if Map.has_key?(updated, :changelog_id) and not is_nil(updated.changelog_id) do
            # Update the changelog entry to APPROVED
            case :ets.lookup(:gettext_translator_changelog, updated.changelog_id) do
              [{_, changelog_entry}] ->
                # Only mark as modified if status is changing
                modified = changelog_entry.status != "APPROVED"

                modified_entry =
                  Map.merge(changelog_entry, %{
                    status: "APPROVED",
                    modified: modified
                  })

                :ets.insert(:gettext_translator_changelog, {updated.changelog_id, modified_entry})

                # Also update the in-memory representation to show the updated status immediately
                Map.put(updated, :changelog_status, "APPROVED")

              _ ->
                updated
            end
          else
            # Create a new changelog entry with APPROVED status
            {:ok, _} = TranslationStore.create_changelog_entry(updated, "APPROVED")
            Map.put(updated, :changelog_status, "APPROVED")
          end

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
    # Use the path from socket assigns - no fallback to default
    path = params["path"] || socket.assigns.gettext_path

    # Make sure we have a path
    unless path do
      {:noreply, socket |> put_flash(:error, "No gettext path provided")}
    end

    # Log for debugging
    Logger.debug("Loading translations from path: #{inspect(path)}")

    # Clear the table before loading to avoid duplicates
    try do
      # Load translations
      result = TranslationStore.load_translations(path)
      translations = TranslationStore.list_translations()

      languages = Enum.map(translations, & &1.language_code) |> Enum.uniq() |> Enum.sort()

      case result do
        {:ok, count} ->
          {:noreply,
           socket
           |> assign(translations_loaded: true)
           |> assign(translations: languages)
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

    # Save changelog entries first - this ensures any approved translations get saved
    changelog_results = TranslationStore.save_changelog_to_files()

    # Count successful changelog saves
    changelog_successful =
      Enum.count(changelog_results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.empty?(modified_translations) && changelog_successful == 0 do
      {:noreply, socket |> put_flash(:info, "No changes to save")}
    else
      # Group translations by file path
      by_file = Enum.group_by(modified_translations, fn t -> t.file_path end)

      # Process each file
      po_results =
        Enum.map(by_file, fn {file_path, file_translations} ->
          save_translations_to_file(file_path, file_translations)
        end)

      # Count successful PO file saves
      po_successful =
        Enum.count(po_results, fn
          {:ok, _} -> true
          _ -> false
        end)

      successful = po_successful + changelog_successful

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

  defp maybe_add_plural_translation(updates, params) do
    if Map.has_key?(params, "plural_translation") do
      Map.put(updates, :plural_translation, params["plural_translation"])
    else
      updates
    end
  end

  defp update_changelog(updated, params) do
    if has_changelog_id?(updated) do
      update_existing_changelog(updated, params)
    else
      create_new_changelog(updated)
    end
  end

  defp has_changelog_id?(updated) do
    Map.has_key?(updated, :changelog_id) and not is_nil(updated.changelog_id)
  end

  defp update_existing_changelog(updated, params) do
    case :ets.lookup(:gettext_translator_changelog, updated.changelog_id) do
      [{_, changelog_entry}] ->
        translated_text = build_translated_text(updated, params)

        modified_entry =
          Map.merge(changelog_entry, %{
            translated: translated_text,
            status: "MODIFIED",
            modified: true
          })

        :ets.insert(:gettext_translator_changelog, {updated.changelog_id, modified_entry})
        Map.put(updated, :changelog_status, "MODIFIED")

      _ ->
        # Entry doesn't exist but translation was marked as having one
        {:ok, _} = TranslationStore.create_changelog_entry(updated, "MODIFIED")
        Map.put(updated, :changelog_status, "MODIFIED")
    end
  end

  defp create_new_changelog(updated) do
    {:ok, _} = TranslationStore.create_changelog_entry(updated, "MODIFIED")
    Map.put(updated, :changelog_status, "MODIFIED")
  end

  defp build_translated_text(updated, params) do
    case updated.type do
      :plural ->
        plural_text = params["plural_translation"] || ""
        "#{params["translation"]} | #{plural_text}"

      _ ->
        params["translation"]
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
    # Base msgstr with the first two forms
    initial_msgstr = %{
      0 => [translation.translation],
      1 => [translation.plural_translation]
    }

    # Add third form for languages that need it (like Ukrainian)
    # The language_code should be available in the translation struct
    msgstr =
      case translation.language_code do
        "uk" ->
          # For Ukrainian, we need the third form
          third_form = Map.get(translation, :plural_translation_2, translation.plural_translation)
          Map.put(initial_msgstr, 2, [third_form])

        # Add other languages that need 3+ forms here
        "ru" ->
          Map.put(initial_msgstr, 2, [translation.plural_translation])

        "pl" ->
          Map.put(initial_msgstr, 2, [translation.plural_translation])

        # For languages with just 2 forms
        _ ->
          initial_msgstr
      end

    %{msg | msgstr: msgstr}
  end
end
