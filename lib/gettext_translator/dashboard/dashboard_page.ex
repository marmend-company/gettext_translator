defmodule GettextTranslator.Dashboard.DashboardPage do
  @moduledoc """
  Phoenix LiveDashboard page for managing Gettext translations.

  This module integrates with Phoenix LiveDashboard to provide a UI for viewing
  and managing gettext translations.
  """

  use Phoenix.LiveDashboard.PageBuilder
  import Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  import GettextTranslator.Util.Helper

  require Logger

  alias GettextTranslator.Dashboard.Components.ExtractedStats
  alias GettextTranslator.Dashboard.Components.Header
  alias GettextTranslator.Dashboard.Components.LLMOverrideForm
  alias GettextTranslator.Dashboard.Components.TabNav
  alias GettextTranslator.Dashboard.Components.TranslationDetails
  alias GettextTranslator.Dashboard.Components.TranslationStats
  alias GettextTranslator.Processor.LLM
  alias GettextTranslator.Store
  alias GettextTranslator.Store.Changelog
  alias GettextTranslator.Store.Translation
  alias GettextTranslator.Util.Extractor
  alias GettextTranslator.Util.MakePullRequest
  alias GettextTranslator.Util.Parser

  @impl true
  def init(opts) do
    Logger.info("DashboardPage init received opts: #{inspect(opts)}")

    # Store the raw configs without resolving paths
    gettext_path = Keyword.get(opts, :gettext_path)
    application = Keyword.get(opts, :application)

    # Ensure the table exists
    ensure_config_table()

    # Store raw configs in ETS
    store_config(:raw_gettext_path, gettext_path)
    store_config(:application, application)

    # Also persist in Application env (survives ETS table recreation on recompile)
    if gettext_path,
      do: Application.put_env(:gettext_translator, :dashboard_gettext_path, gettext_path)

    if application,
      do: Application.put_env(:gettext_translator, :dashboard_application, application)

    {:ok, %{}}
  end

  @impl true
  def mount(_params, _session, socket) do
    modified_count = Store.count_modified_translations()
    approved_count = Store.count_approved_translations()
    # Just assign socket without loading translations
    {:ok,
     assign(socket,
       translations: [],
       translations_loaded: false,
       translations_count: 0,
       gettext_path: nil,
       loading: false,
       modified_count: modified_count,
       approved_count: approved_count,
       llm_translating: false,
       llm_translation_result: nil,
       llm_provider_info: Parser.provider_info(),
       active_tab: "stats",
       extracting: false,
       batch_translating: false,
       batch_progress: 0,
       batch_total: 0,
       llm_override: nil,
       show_override_form: false
     )}
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
          {@error}
        </div>
      </div>
      """
    else
      translations = Store.list_translations()
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
        <%= raw GettextTranslator.Dashboard.Components.GettextDashboardCSS.styles() %>
      </style>
      <div class="dashboard-container">
        <Header.render
          gettext_path={@gettext_path}
          translations_count={@translations_count}
          translations_loaded={@translations_loaded}
          modified_count={@modified_count}
          approved_count={@approved_count}
          loading={@loading}
          extracting={@extracting}
        />

        <%= if @translations_loaded do %>
          <LLMOverrideForm.render
            llm_override={@llm_override}
            llm_provider_info={@llm_provider_info}
            show_override_form={@show_override_form}
          />

          <TabNav.render
            active_tab={@active_tab}
            extracted_count={Enum.count(@translations, fn t -> t.status == :pending end)}
          />

          <%= if @active_tab == "stats" do %>
            <TranslationStats.render translations={@translations} />
          <% else %>
            <ExtractedStats.render
              translations={@translations}
              llm_provider_info={@llm_provider_info}
              batch_translating={@batch_translating}
              batch_progress={@batch_progress}
              batch_total={@batch_total}
            />
          <% end %>

          <%= if assigns[:viewing_translations] do %>
            <TranslationDetails.render
              viewing_language={@viewing_language}
              viewing_domain={@viewing_domain}
              filtered_translations={@filtered_translations}
              editing_id={assigns[:editing_id]}
              llm_translating={@llm_translating}
              llm_translation_result={@llm_translation_result}
              llm_provider_info={@llm_provider_info}
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
    translations = Store.list_translations()

    filtered =
      Enum.filter(translations, fn t ->
        t.language_code == language && t.domain == domain
      end)

    socket =
      socket
      |> assign(viewing_translations: true)
      |> assign(viewing_language: language)
      |> assign(viewing_domain: domain)
      |> assign(filtered_translations: filtered)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_extracted", %{"language" => language, "domain" => domain}, socket) do
    translations = Store.list_translations()

    # Show only pending translations for this language/domain
    filtered =
      Enum.filter(translations, fn t ->
        t.language_code == language && t.domain == domain && t.status == :pending
      end)

    socket =
      socket
      |> assign(viewing_translations: true)
      |> assign(viewing_language: language)
      |> assign(viewing_domain: domain)
      |> assign(filtered_translations: filtered)

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
    {:noreply,
     assign(socket,
       editing_id: id,
       llm_translating: false,
       llm_translation_result: nil
     )}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  @impl true
  def handle_event("llm_translate", %{"_id" => id} = params, socket) do
    provider_info = socket.assigns.llm_provider_info

    if provider_info.configured do
      self_pid = self()
      additional_instructions = Map.get(params, "additional_instructions", "")

      case Store.get_translation(id) do
        {:ok, translation} ->
          provider = resolve_provider(socket.assigns.llm_override)

          opts = %{
            language_code: translation.language_code,
            message: translation.message_id,
            type: translation.type,
            plural_message: Map.get(translation, :plural_id)
          }

          Task.start(fn ->
            result =
              try do
                LLM.translate_single(provider, opts, additional_instructions)
              rescue
                e -> {:error, Exception.message(e)}
              end

            send(self_pid, {:llm_translation_result, id, result})
          end)

          {:noreply, assign(socket, llm_translating: true)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Translation not found")}
      end
    else
      {:noreply, put_flash(socket, :error, "LLM provider is not configured")}
    end
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

    case Translation.update_translation(id, updates) do
      {:ok, updated} ->
        updated = Changelog.update_for_modified_translation(updated, params)

        filtered =
          Enum.map(socket.assigns.filtered_translations, fn t ->
            if t.id == id, do: updated, else: t
          end)

        modified_count = Store.count_modified_translations()

        {:noreply,
         socket
         |> assign(filtered_translations: filtered)
         |> assign(editing_id: nil)
         |> assign(modified_count: modified_count)
         |> put_flash(:info, "Translation updated")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to update: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("load_translations", _params, socket) do
    do_load_reload_translations(socket)
  end

  @impl true
  def handle_event("save_to_files", _params, socket) do
    socket = assign(socket, loading: true)
    # Get all translations from the store
    translations = Store.list_translations()

    # Get all modified translations (status = :modified or :translated)
    modified_translations =
      Enum.filter(translations, fn t ->
        t.status == :modified || t.status == :translated
      end)

    # Save changelog entries first - this ensures any approved translations get saved
    {:ok, changelog_results} = Changelog.save_to_files()

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
          Translation.save_translations_to_file(file_path, file_translations)
        end)

      # Count successful PO file saves
      po_successful =
        Enum.count(po_results, fn
          {:ok, _} -> true
          _ -> false
        end)

      successful = po_successful + changelog_successful

      if successful > 0 do
        updated_socket = reload_translations(socket)

        {:noreply,
         updated_socket
         |> assign(loading: false)
         |> put_flash(:info, "Successfully saved #{successful} files")}
      else
        {:noreply,
         socket |> assign(loading: false) |> put_flash(:error, "Failed to save changes")}
      end
    end
  end

  @impl true
  def handle_event("make_pull_request", _params, socket) do
    socket = assign(socket, loading: true)
    # Get all translations from the store
    translations = Store.list_translations()

    # Get all modified translations
    modified_translations =
      Enum.filter(translations, fn t ->
        t.status == :modified || t.status == :translated
      end)

    # Get changelog entries
    changelog_entries = Store.get_entries_by_file()

    if Enum.empty?(modified_translations) && Enum.empty?(changelog_entries) do
      {:noreply,
       socket
       |> assign(loading: false)
       |> put_flash(:info, "No changes to create pull request for")}
    else
      # Create a pull request with the changes
      case MakePullRequest.create_pull_request(modified_translations, changelog_entries) do
        {:ok, pr_url} ->
          updated_socket = reload_translations(socket)

          {:noreply,
           updated_socket
           |> assign(loading: false)
           |> put_flash(:info, "Created pull request: #{pr_url}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "Failed to create pull request: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("approve_translation", %{"id" => id}, socket) do
    # Set loading state to prevent multiple clicks
    socket = assign(socket, loading: true)

    # Use the Translation service to update the translation
    case Translation.update_translation(id, %{status: :translated}) do
      {:ok, updated} ->
        filtered =
          Enum.map(socket.assigns.filtered_translations, fn t ->
            if t.id == id, do: updated, else: t
          end)

        Store.increment_approved()
        approved_count = Store.count_approved_translations()

        socket =
          socket
          |> assign(filtered_translations: filtered)
          |> assign(loading: false)
          |> assign(approved_count: approved_count)
          |> put_flash(:info, "Translation approved")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:error, "Failed to approve: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    # Close any open detail view when switching tabs
    {:noreply,
     socket
     |> assign(active_tab: tab)
     |> assign(viewing_translations: false)
     |> assign(filtered_translations: [])
     |> assign(editing_id: nil)}
  end

  @impl true
  def handle_event("extract_and_merge", _params, socket) do
    self_pid = self()
    gettext_path = socket.assigns.gettext_path

    Task.start(fn ->
      result = Extractor.extract_and_merge(gettext_path)
      send(self_pid, {:extraction_result, result})
    end)

    {:noreply, assign(socket, extracting: true)}
  end

  @impl true
  def handle_event("batch_translate_all", _params, socket) do
    provider_info = socket.assigns.llm_provider_info

    if provider_info.configured do
      # Collect all pending translations
      pending =
        Store.list_translations()
        |> Enum.filter(fn t -> t.status == :pending end)

      if Enum.empty?(pending) do
        {:noreply, put_flash(socket, :info, "No pending translations to batch translate")}
      else
        self_pid = self()
        llm_override = socket.assigns.llm_override

        Task.start(fn ->
          provider = resolve_provider(llm_override)

          Enum.each(pending, fn translation ->
            opts = %{
              language_code: translation.language_code,
              message: translation.message_id,
              type: translation.type,
              plural_message: Map.get(translation, :plural_id)
            }

            result =
              try do
                LLM.translate_single(provider, opts)
              rescue
                e -> {:error, Exception.message(e)}
              end

            send(self_pid, {:batch_translate_progress, translation.id, result})
          end)

          send(self_pid, {:batch_translate_complete})
        end)

        {:noreply,
         assign(socket,
           batch_translating: true,
           batch_progress: 0,
           batch_total: length(pending)
         )}
      end
    else
      {:noreply, put_flash(socket, :error, "LLM provider is not configured")}
    end
  end

  @impl true
  def handle_event("update_llm_override", params, socket) do
    adapter_name = Map.get(params, "adapter", "openai")
    model = Map.get(params, "model", "")
    api_key = Map.get(params, "api_key", "")
    endpoint_url = Map.get(params, "endpoint_url", "")

    {adapter_module, config_key, display_name} = adapter_info(adapter_name)

    endpoint_config =
      %{}
      |> maybe_put_config(config_key, api_key)
      |> maybe_put_endpoint_url(adapter_name, endpoint_url)

    override = %{
      adapter: adapter_module,
      adapter_name: display_name,
      model: model,
      config: endpoint_config
    }

    provider_info = %{configured: true, adapter_name: display_name, model: model}

    {:noreply,
     socket
     |> assign(llm_override: override)
     |> assign(llm_provider_info: provider_info)
     |> assign(show_override_form: false)
     |> put_flash(:info, "LLM provider override applied: #{display_name} — #{model}")}
  end

  @impl true
  def handle_event("clear_llm_override", _params, socket) do
    {:noreply,
     socket
     |> assign(llm_override: nil)
     |> assign(llm_provider_info: Parser.provider_info())
     |> put_flash(:info, "LLM provider override cleared")}
  end

  @impl true
  def handle_event("toggle_llm_override_form", _params, socket) do
    {:noreply, assign(socket, show_override_form: !socket.assigns.show_override_form)}
  end

  @impl true
  def handle_info({:extraction_result, result}, socket) do
    case result do
      {:ok, message} ->
        updated_socket = reload_translations(socket)

        {:noreply,
         updated_socket
         |> assign(extracting: false)
         |> assign(active_tab: "extracted")
         |> assign(viewing_translations: false)
         |> assign(filtered_translations: [])
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(extracting: false)
         |> put_flash(:error, "Extraction failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:batch_translate_progress, id, result}, socket) do
    progress = socket.assigns.batch_progress + 1

    socket =
      case result do
        {:ok, %{translation: translation_text} = translation_result} ->
          updates = %{
            translation: translation_text,
            plural_translation: Map.get(translation_result, :plural_translation),
            status: :translated
          }

          case Translation.update_translation(id, updates) do
            {:ok, _updated} -> socket
            {:error, _reason} -> socket
          end

        {:error, _reason} ->
          socket
      end

    {:noreply, assign(socket, batch_progress: progress)}
  end

  @impl true
  def handle_info({:batch_translate_complete}, socket) do
    modified_count = Store.count_modified_translations()
    approved_count = Store.count_approved_translations()

    {:noreply,
     socket
     |> assign(batch_translating: false)
     |> assign(modified_count: modified_count)
     |> assign(approved_count: approved_count)
     |> put_flash(
       :info,
       "Batch translation complete: #{socket.assigns.batch_progress} of #{socket.assigns.batch_total} translated"
     )}
  end

  @impl true
  def handle_info({:llm_translation_result, id, result}, socket) do
    case result do
      {:ok, translation_result} ->
        {:noreply,
         socket
         |> assign(llm_translating: false)
         |> assign(llm_translation_result: Map.put(translation_result, :id, id))
         |> put_flash(:info, "LLM translation ready — review and save")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(llm_translating: false)
         |> put_flash(:error, "LLM translation failed: #{inspect(reason)}")}
    end
  end

  defp do_load_reload_translations(socket) do
    updated_socket = reload_translations(socket)
    {:noreply, updated_socket}
  end

  defp reload_translations(socket) do
    # Resolve the path at runtime when button is clicked
    # Try ETS first, fall back to Application env (persists across ETS table recreation)
    app =
      get_config(:application) ||
        Application.get_env(:gettext_translator, :dashboard_application)

    raw_path =
      get_config(:raw_gettext_path) ||
        Application.get_env(:gettext_translator, :dashboard_gettext_path)

    gettext_path =
      cond do
        app && raw_path ->
          # Resolve path at runtime using application dir
          resolved_path = Application.app_dir(app, raw_path)
          store_config(:gettext_path, resolved_path)
          Logger.info("Resolved gettext path: #{resolved_path}")
          resolved_path

        raw_path ->
          # No application configured, use raw path directly (dev mode)
          store_config(:gettext_path, raw_path)
          Logger.info("Using raw gettext path: #{raw_path}")
          raw_path

        true ->
          get_config(:gettext_path)
      end

    if gettext_path do
      # Ensure the TranslationStore is started
      case ensure_translation_store_started() do
        :ok ->
          # Load translations
          {:ok, count} = Translation.load_translations(gettext_path)

          assign(socket,
            gettext_path: gettext_path,
            translations_loaded: count > 0,
            translations_count: count,
            modified_count: Store.count_modified_translations(),
            approved_count: Store.count_approved_translations()
          )

        {:error, reason} ->
          Logger.error("Failed to start TranslationStore: #{inspect(reason)}")
          socket |> put_flash(:error, "Failed to start translation store: #{inspect(reason)}")
      end
    else
      # Provide a helpful error message
      Logger.error("Missing gettext_path in load_translations event")
      socket |> put_flash(:error, "Configuration error: gettext_path not provided")
    end
  end

  # Helper function to ensure TranslationStore is started
  defp ensure_translation_store_started do
    case Process.whereis(TranslationStore) do
      nil ->
        # Not started - try to start it
        case Store.start_link() do
          {:ok, _pid} ->
            Logger.info("Started GettextTranslator.Store")
            :ok

          {:error, {:already_started, _pid}} ->
            Logger.info("GettextTranslator.Store already started")
            :ok

          error ->
            {:error, error}
        end

      _pid ->
        # Already started
        Logger.info("GettextTranslator.Store already running")
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

  defp resolve_provider(nil), do: Parser.parse_provider()

  defp resolve_provider(override) do
    config = Application.get_env(:gettext_translator, GettextTranslator, [])

    %{
      endpoint: %{
        adapter: override.adapter,
        model: override.model,
        temperature: Keyword.get(config, :endpoint_temperature, 0.3),
        config: override.config
      },
      persona:
        Keyword.get(
          config,
          :persona,
          "You are a proffesional translator. Your goal is to translate the message to the target language and try to keep the same meaning and length of the output sentence as original one."
        ),
      style: Keyword.get(config, :style, "Casual, use simple language"),
      ignored_languages: Keyword.get(config, :ignored_languages, [])
    }
  end

  defp adapter_info("openai"),
    do: {LangChain.ChatModels.ChatOpenAI, "openai_key", "OpenAI"}

  defp adapter_info("anthropic"),
    do: {LangChain.ChatModels.ChatAnthropic, "anthropic_key", "Anthropic"}

  defp adapter_info("ollama"),
    do: {LangChain.ChatModels.ChatOllamaAI, nil, "Ollama"}

  defp adapter_info("google_ai"),
    do: {LangChain.ChatModels.ChatGoogleAI, "google_ai_key", "Google AI"}

  defp adapter_info(_),
    do: {LangChain.ChatModels.ChatOpenAI, "openai_key", "OpenAI"}

  defp maybe_put_config(config, nil, _api_key), do: config
  defp maybe_put_config(config, _key, ""), do: config
  defp maybe_put_config(config, key, api_key), do: Map.put(config, key, api_key)

  defp maybe_put_endpoint_url(config, _adapter, ""), do: config
  defp maybe_put_endpoint_url(config, "ollama", url), do: Map.put(config, "endpoint", url)
  defp maybe_put_endpoint_url(config, _adapter, url), do: Map.put(config, "endpoint", url)
end
