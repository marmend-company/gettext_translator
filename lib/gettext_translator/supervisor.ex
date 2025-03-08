defmodule GettextTranslator.Supervisor do
  @moduledoc """
  Supervisor for GettextTranslator processes.

  This module provides a supervisor that can be included in your application's
  supervision tree to manage the GettextTranslator dashboard components.

  ## Usage

  Add to your application supervision tree:

  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # ... other children
      GettextTranslator.Supervisor
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```
  """

  use Supervisor
  require Logger

  @doc false
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      if dashboard_available?() do
        if Process.whereis(GettextTranslator.Dashboard.TranslationStore) do
          # Store already running, don't start it again
          Logger.info("GettextTranslator dashboard enabled (using existing TranslationStore)")
          []
        else
          Logger.info("GettextTranslator dashboard enabled")
          [GettextTranslator.Dashboard.TranslationStore]
        end
      else
        Logger.debug(
          "GettextTranslator dashboard not available (Phoenix LiveDashboard not loaded)"
        )

        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp dashboard_available? do
    Code.ensure_loaded?(Phoenix.LiveDashboard) &&
      Code.ensure_loaded?(Phoenix.LiveView)
  end
end
