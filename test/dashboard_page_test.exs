# defmodule GettextTranslator.Dashboard.DashboardPageTest do
#   use ExUnit.Case
#   import Phoenix.LiveViewTest

#   alias GettextTranslator.Dashboard.{DashboardPage, TranslationStore}

#   @test_po_path "test/fixtures/gettext/uk/LC_MESSAGES/default.po"
#   @test_changelog_path "test/fixtures/translation_changelog/uk_default_changelog.json"

#   setup do
#     # Create test directories and files
#     File.mkdir_p!(Path.dirname(@test_po_path))
#     File.mkdir_p!(Path.dirname(@test_changelog_path))

#     case Process.whereis(TranslationStore) do
#       nil ->
#         # Not running - start it
#         start_supervised!(TranslationStore)
#       _ ->
#         # Already running - reset the tables
#         :ets.delete_all_objects(:gettext_translator_entries)
#         :ets.delete_all_objects(:gettext_translator_changelog)
#     end

#     # Create a test PO file
#     po_content = """
#     msgid ""
#     msgstr ""
#     "Language: uk\\n"

#     msgid "Hello"
#     msgstr "Привіт"

#     msgid "Goodbye"
#     msgstr "До побачення"
#     """

#     File.write!(@test_po_path, po_content)

#     # Clean up after tests
#     on_exit(fn ->
#       File.rm(@test_po_path)
#       File.rm(@test_changelog_path)
#     end)

#     :ok
#   end

#   describe "LiveDashboard page" do
#     test "initializes with empty translations" do
#       {:ok, _view, html} = live_isolated_component(
#         DashboardPage,
#         %{id: "test-dashboard", gettext_path: "test/fixtures/gettext", translations_loaded: false}
#       )

#       # Initial render should show the header but no translations yet
#       assert html =~ "Gettext Translations"
#       assert html =~ "Load Translations"
#       refute html =~ "Translation Stats"
#     end

#     test "loads translations" do
#       {:ok, view, _} = live_isolated_component(
#         DashboardPage,
#         %{id: "test-dashboard", gettext_path: "test/fixtures/gettext", translations_loaded: false}
#       )

#       # Simulate clicking the load button
#       html = view
#       |> element("form[phx-submit=\"load_translations\"] button")
#       |> render_click()

#       # Should show translation stats now
#       assert html =~ "Translation Stats"
#       assert html =~ "uk"
#       assert html =~ "default"
#     end

#     test "shows translation details" do
#       # Load translations first
#       TranslationStore.load_translations("test/fixtures/gettext")

#       {:ok, view, _} = live_isolated_component(
#         DashboardPage,
#         %{
#           id: "test-dashboard",
#           gettext_path: "test/fixtures/gettext",
#           translations_loaded: true,
#           translations: TranslationStore.list_translations()
#         }
#       )

#       # Simulate clicking the view button
#       html = view
#       |> element("button[phx-click=\"show_translations\"][phx-value-language=\"uk\"][phx-value-domain=\"default\"]")
#       |> render_click()

#       # Should show translation details
#       assert html =~ "uk / default Translations"
#       assert html =~ "Hello"
#       assert html =~ "Привіт"
#       assert html =~ "Goodbye"
#       assert html =~ "До побачення"
#     end

#     test "approves a translation" do
#       # Load translations first
#       TranslationStore.load_translations("test/fixtures/gettext")
#       translations = TranslationStore.list_translations()
#       hello = Enum.find(translations, & &1.message_id == "Hello")

#       # Create a changelog entry for the translation
#       {:ok, _} = TranslationStore.create_changelog_entry(hello, "NEW")

#       {:ok, view, _} = live_isolated_component(
#         DashboardPage,
#         %{
#           id: "test-dashboard",
#           gettext_path: "test/fixtures/gettext",
#           translations_loaded: true,
#           translations: TranslationStore.list_translations(),
#           viewing_translations: true,
#           viewing_language: "uk",
#           viewing_domain: "default",
#           filtered_translations: [hello]
#         }
#       )

#       # Simulate clicking the approve button
#       html = view
#       |> element("button[phx-click=\"approve_translation\"][phx-value-id=\"#{hello.id}\"]")
#       |> render_click()

#       # Should show approved status
#       assert html =~ "Translation approved"

#       # Check if translation was approved in store
#       updated_translations = TranslationStore.list_translations()
#       updated_hello = Enum.find(updated_translations, & &1.id == hello.id)

#       assert updated_hello.status == :translated
#       assert updated_hello.changelog_status == "APPROVED"
#     end

#     test "edits a translation" do
#       # Load translations first
#       TranslationStore.load_translations("test/fixtures/gettext")
#       translations = TranslationStore.list_translations()
#       hello = Enum.find(translations, & &1.message_id == "Hello")

#       {:ok, view, _} = live_isolated_component(
#         DashboardPage,
#         %{
#           id: "test-dashboard",
#           gettext_path: "test/fixtures/gettext",
#           translations_loaded: true,
#           translations: TranslationStore.list_translations(),
#           viewing_translations: true,
#           viewing_language: "uk",
#           viewing_domain: "default",
#           filtered_translations: [hello]
#         }
#       )

#       # Simulate clicking the edit button
#       html = view
#       |> element("button[phx-click=\"edit_translation\"][phx-value-id=\"#{hello.id}\"]")
#       |> render_click()

#       # Should show edit form
#       assert html =~ "Translation"
#       assert html =~ "textarea"

#       # Submit the form with updated translation
#       html = view
#       |> element("form[phx-submit=\"save_translation\"]")
#       |> render_submit(%{"_id" => hello.id, "translation" => "Вітаю"})

#       # Should show success message
#       assert html =~ "Translation updated"

#       # Check if translation was updated in store
#       updated_translations = TranslationStore.list_translations()
#       updated_hello = Enum.find(updated_translations, & &1.id == hello.id)

#       assert updated_hello.translation == "Вітаю"
#       assert updated_hello.status == :modified
#       assert updated_hello.changelog_status == "MODIFIED"
#     end

#     test "saves changes to files" do
#       # Load translations first
#       TranslationStore.load_translations("test/fixtures/gettext")
#       translations = TranslationStore.list_translations()
#       hello = Enum.find(translations, & &1.message_id == "Hello")

#       # Create a changelog entry for the translation
#       {:ok, _} = TranslationStore.create_changelog_entry(hello, "NEW")

#       # Update the translation
#       {:ok, updated} = TranslationStore.update_translation(hello.id, %{
#         translation: "Вітаю",
#         status: :modified
#       })

#       # Update changelog to MODIFIED
#       :ets.lookup(:gettext_translator_changelog, updated.changelog_id)
#       |> case do
#         [{_, changelog_entry}] ->
#           modified_entry = Map.merge(changelog_entry, %{
#             status: "MODIFIED",
#             modified: true
#           })
#           :ets.insert(:gettext_translator_changelog, {updated.changelog_id, modified_entry})
#         _ -> :ok
#       end

#       {:ok, view, _} = live_isolated_component(
#         DashboardPage,
#         %{
#           id: "test-dashboard",
#           gettext_path: "test/fixtures/gettext",
#           translations_loaded: true,
#           translations: TranslationStore.list_translations()
#         }
#       )

#       # Simulate clicking the save button
#       html = view
#       |> element("form[phx-submit=\"save_to_files\"] button")
#       |> render_click()

#       # Should show success message
#       assert html =~ "Saved changes to"

#       # Check if PO file was updated
#       assert File.exists?(@test_po_path)
#       po_content = File.read!(@test_po_path)
#       assert po_content =~ "msgstr \"Вітаю\""

#       # Check if changelog file was created
#       assert File.exists?(@test_changelog_path)
#       changelog_content = File.read!(@test_changelog_path)
#       {:ok, changelog} = Jason.decode(changelog_content)

#       # Check changelog content
#       assert Map.has_key?(changelog, "history")
#       history_entry = List.first(changelog["history"])
#       entries = history_entry["entries"]
#       modified_entry = Enum.find(entries, fn e -> Enum.join(e["original"], "") == "Hello" end)

#       assert modified_entry["status"] == "MODIFIED"
#       assert modified_entry["translated"] == "Вітаю"
#     end
#   end

#   # Helper function to test LiveView components in isolation
#   # This is a simplified version for testing purposes
#   defp live_isolated_component(component, assigns) do
#     # Create a basic LiveView that just renders the component
#     module = Module.concat([__MODULE__, "TestLiveView_#{:rand.uniform(1000)}"])

#     defmodule module do
#       use Phoenix.LiveView

#       def render(assigns) do
#         ~H"""
#         <%= component.render(assigns) %>
#         """
#       end

#       def mount(_params, _session, socket) do
#         {:ok, assign(socket, assigns)}
#       end

#       def handle_event(event, params, socket) do
#         apply(component, :handle_event, [event, params, socket])
#       end
#     end

#     # Test the LiveView
#     {:ok, view, html} = live_isolated(build_conn(), module)
#     {:ok, view, html}
#   end

#   # Simplified build_conn helper
#   defp build_conn do
#     Plug.Test.conn(:get, "/")
#   end
# end
