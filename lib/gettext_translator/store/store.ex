defmodule GettextTranslator.Store do
  @moduledoc """
  In-memory store for translation entries and changelog using ETS.
  This module is responsible for the low-level persistence layer.
  """

  use GenServer
  require Logger

  @table_name :gettext_translator_entries
  @changelog_table :gettext_translator_changelog
  @approved_table :gettext_translator_approved_translations

  # Client API

  @doc """
  Starts the ETS store.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Translation table operations
  def insert_translation(id, translation) do
    :ets.insert(@table_name, {id, translation})
  end

  def get_translation(id) when is_binary(id) do
    case :ets.lookup(@table_name, id) do
      [{^id, translation}] -> {:ok, translation}
      [] -> {:error, :not_found}
    end
  end

  def list_translations do
    case :ets.info(@table_name) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@table_name)
        |> Enum.map(fn {_id, translation} -> translation end)
    end
  end

  def reset_translations do
    :ets.delete_all_objects(@table_name)
  end

  def count_by_status(status) do
    :ets.match_object(@table_name, {:"$1", %{status: status}})
    |> Enum.count()
  end

  # Changelog table operations
  def insert_changelog(id, entry) do
    :ets.insert(@changelog_table, {id, entry})
  end

  def get_changelog(id) when is_binary(id) do
    case :ets.lookup(@changelog_table, id) do
      [{^id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  def list_changelogs do
    case :ets.info(@changelog_table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@changelog_table)
        |> Enum.map(fn {_id, entry} -> entry end)
    end
  end

  def reset_changelogs do
    :ets.delete_all_objects(@changelog_table)
  end

  # Server callbacks
  @impl true
  def init(_) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@changelog_table, [:set, :named_table, :public, read_concurrency: true])
    start_approved_counter()
    {:ok, %{}}
  end

  @doc """
  Start the ETS table for approved translations when your application starts.
  Call this in your application's supervision tree.
  """
  def start_approved_counter do
    :ets.new(@approved_table, [:set, :public, :named_table])
    :ets.insert(@approved_table, {:count, 0})
    :ok
  end

  @doc """
  Increment the approved translations counter
  """
  def increment_approved do
    :ets.update_counter(@approved_table, :count, {2, 1})
  end

  @doc """
  Get the current count for approved translations
  """
  def count_approved_translations do
    case :ets.lookup(@approved_table, :count) do
      [{:count, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Reset the approved translations counter
  """
  def reset_approved_counter do
    :ets.insert(@approved_table, {:count, 0})
    0
  end

  @doc """
  Counts the number of translations with :modified status.
  """
  def count_modified_translations do
    case :ets.info(@table_name) do
      :undefined ->
        0

      _ ->
        :ets.match_object(@table_name, {:"$1", %{status: :modified}})
        |> Enum.count()
    end
  end

  def get_entries_by_file do
    :ets.tab2list(@changelog_table)
    |> Enum.map(fn {_, entry} -> entry end)
    |> Enum.group_by(& &1.source_file)
  end
end
