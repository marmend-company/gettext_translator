defmodule GettextTranslator.Dashboard do
  @moduledoc """
  Phoenix LiveDashboard integration for GettextTranslator.

  This module provides functions to register the GettextTranslator dashboard
  with your Phoenix application.

  ## Setup

  1. Add the required dependencies to your mix.exs:

  ```elixir
  def deps do
    [
      {:gettext_translator, "~> 0.1.0"},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:phoenix_live_view, "~> 1.0.0"}
    ]
  end
  ```

  2. Add the GettextTranslator supervisor to your application:

  ```elixir
  # lib/my_app/application.ex
  def start(_type, _args) do
    children = [
      # ... other children
      GettextTranslator.Supervisor
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```

  3. Add the dashboard page to your Phoenix router:

  ```elixir
  # lib/my_app_web/router.ex
  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through [:browser, :admin_auth] # replace with your actual pipeline

    live_dashboard "/dashboard",
      metrics: MyAppWeb.Telemetry,
      additional_pages: GettextTranslator.Dashboard.page_config(gettext_path: "priv/gettext")
  end
  ```

  ## Usage

  Once set up, you can access the Gettext Translations page from your Phoenix LiveDashboard.
  The dashboard allows you to:

  - View all translations across all language files
  - Filter translations by language, domain, and status
  - Edit translations directly in the UI
  - Commit changes back to PO files
  - Create Git commits and PRs (if the git_cli dependency is available)

  You can also continue to use the mix task for batch translation:

  ```
  mix gettext_translator.run
  ```
  """

  @doc """
  Returns a list of additional pages configuration for Phoenix LiveDashboard.

  ## Options

  * `:gettext_path` - Path to the gettext directory (default: "priv/gettext")

  ## Example

  ```elixir
  live_dashboard "/dashboard",
    metrics: MyAppWeb.Telemetry,
    additional_pages: GettextTranslator.Dashboard.page_config(gettext_path: "priv/gettext")
  ```
  """
  def page_config(opts \\ []) do
    if ensure_dashboard_dependencies_loaded?() do
      gettext_path = Keyword.get(opts, :gettext_path, "priv/gettext")

      [
        gettext_translations: {
          GettextTranslator.Dashboard.DashboardPage,
          [gettext_path: gettext_path]
        }
      ]
    else
      raise """
      Cannot register GettextTranslator dashboard because Phoenix LiveDashboard is not loaded.
      Please make sure you have added :phoenix_live_dashboard and :phoenix_live_view
      to your dependencies.
      """
    end
  end

  @doc """
  Returns the gettext dashboard page configuration.

  ## Options

  * `:gettext_path` - Path to the gettext directory (default: "priv/gettext")

  ## Example

  ```elixir
  # When manually constructing the dashboard pages
  additional_pages = [
    my_custom_page: {MyCustomPage, []},
    gettext_translations: GettextTranslator.Dashboard.page()
  ]
  ```
  """
  def page(opts \\ []) do
    if ensure_dashboard_dependencies_loaded?() do
      gettext_path = Keyword.get(opts, :gettext_path, "priv/gettext")

      {GettextTranslator.Dashboard.DashboardPage, [gettext_path: gettext_path]}
    else
      raise """
      Cannot register GettextTranslator dashboard because Phoenix LiveDashboard is not loaded.
      Please make sure you have added :phoenix_live_dashboard and :phoenix_live_view
      to your dependencies.
      """
    end
  end

  @doc """
  Checks if the Phoenix.LiveDashboard and Phoenix.LiveView dependencies are available.
  """
  def ensure_dashboard_dependencies_loaded? do
    Code.ensure_loaded?(Phoenix.LiveDashboard) &&
      Code.ensure_loaded?(Phoenix.LiveView)
  end

  @doc """
  Starts the translation store process manually if needed.

  This is usually handled by the GettextTranslator.Supervisor, but can be
  called directly if needed.
  """
  def start_translation_store do
    GettextTranslator.Dashboard.TranslationStore.start_link()
  end

  @doc """
  Loads translations from the given gettext path.

  This must be called after the translation store is started to load the
  translations into memory.

  Returns `{:ok, count}` where count is the number of translations loaded,
  or `{:error, reason}` if loading failed.
  """
  def load_translations(gettext_path \\ "priv/gettext") do
    GettextTranslator.Dashboard.TranslationStore.load_translations(gettext_path)
  end

  @doc """
  Helper function to quickly test the dashboard API in IEx.

  This function starts the translation store, loads translations from the
  given gettext path, and returns basic stats about the loaded translations.

  ## Example

  ```elixir
  iex> GettextTranslator.Dashboard.quick_test("priv/gettext")
  ```
  """
  def quick_test(gettext_path \\ "priv/gettext") do
    # Start the translation store
    case start_translation_store() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> throw(error)
    end

    # Load translations
    {:ok, count} = load_translations(gettext_path)

    # Get all translations and calculate some stats
    translations = GettextTranslator.Dashboard.TranslationStore.list_translations()
    languages = translations |> Enum.map(& &1.language_code) |> Enum.uniq() |> Enum.sort()
    domains = translations |> Enum.map(& &1.domain) |> Enum.uniq() |> Enum.sort()
    pending = Enum.count(translations, &(&1.status == :pending))
    translated = Enum.count(translations, &(&1.status == :translated))

    %{
      loaded_count: count,
      total_count: length(translations),
      languages: languages,
      domains: domains,
      pending: pending,
      translated: translated
    }
  end
end
