#!/usr/bin/env elixir
# Example script demonstrating how to use the GettextTranslator Dashboard API

# Ensure the path is properly set
path_to_gettext = 
  case System.argv() do
    [path | _] -> path
    [] -> "priv/gettext"  # Default path if none provided
  end

# Print header
IO.puts "GettextTranslator Dashboard API Example"
IO.puts "======================================="
IO.puts "Using Gettext path: #{path_to_gettext}"
IO.puts ""

# Run the quick test to see translation stats
IO.puts "Running quick test..."
stats = GettextTranslator.Dashboard.quick_test(path_to_gettext)

# Print stats
IO.puts "Translation Statistics:"
IO.puts "  Loaded translations: #{stats.loaded_count}"
IO.puts "  Total translations: #{stats.total_count}"
IO.puts "  Languages: #{Enum.join(stats.languages, ", ")}"
IO.puts "  Domains: #{Enum.join(stats.domains, ", ")}"
IO.puts "  Pending translations: #{stats.pending}"
IO.puts "  Translated messages: #{stats.translated}"
IO.puts ""

# Demonstrate filtering
IO.puts "Filtering examples:"

# For each language, show count of translations
Enum.each(stats.languages, fn lang ->
  translations = GettextTranslator.Dashboard.TranslationStore.filter_translations(%{language_code: lang})
  pending = Enum.count(translations, & &1.status == :pending)
  translated = Enum.count(translations, & &1.status == :translated)
  
  IO.puts "  #{lang}: #{length(translations)} total (#{translated} translated, #{pending} pending)"
end)

IO.puts ""
IO.puts "Example completed. You can now use these functions in your own application."