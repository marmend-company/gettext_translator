defmodule GettextTranslator.Dashboard.PromptTemplates do
  @moduledoc """
  Locale-aware prompt templates for quick LLM translation actions.

  Each action (regenerate, short_version, rephrase, synonyms) has a prompt
  written in the target language to help the LLM produce more natural output.
  Falls back to English for unsupported locales.
  """

  @type action :: :regenerate | :short_version | :rephrase | :synonyms

  @prompts %{
    regenerate: %{
      "uk" =>
        "Перекладіть цей текст заново, запропонуйте новий варіант перекладу, відмінний від попереднього",
      "en" => "Translate this text again, provide a fresh alternative translation",
      "es" => "Traduce este texto de nuevo, ofrece una nueva alternativa de traducción",
      "de" => "Übersetze diesen Text erneut, biete eine neue alternative Übersetzung an",
      "pl" => "Przetłumacz ten tekst ponownie, zaproponuj nową alternatywną wersję tłumaczenia",
      "fr" => "Traduis ce texte à nouveau, propose une nouvelle traduction alternative",
      "pt" => "Traduza este texto novamente, ofereça uma nova alternativa de tradução"
    },
    short_version: %{
      "uk" => "Зроби переклад якомога коротшим, зберігаючи основний зміст",
      "en" => "Make the translation as short as possible while keeping the core meaning",
      "es" => "Haz la traducción lo más corta posible manteniendo el significado principal",
      "de" => "Mache die Übersetzung so kurz wie möglich und behalte die Kernbedeutung bei",
      "pl" => "Zrób tłumaczenie jak najkrótsze, zachowując główne znaczenie",
      "fr" => "Rends la traduction la plus courte possible tout en gardant le sens principal",
      "pt" => "Faça a tradução o mais curta possível mantendo o significado principal"
    },
    rephrase: %{
      "uk" =>
        "Перефразуй переклад іншими словами, збережи той самий зміст але використай інші конструкції",
      "en" =>
        "Rephrase the translation using different words, keep the same meaning but use alternative phrasing",
      "es" =>
        "Reformula la traducción usando palabras diferentes, mantén el mismo significado pero usa frases alternativas",
      "de" =>
        "Formuliere die Übersetzung mit anderen Worten um, behalte die gleiche Bedeutung aber verwende alternative Formulierungen",
      "pl" =>
        "Przeformułuj tłumaczenie innymi słowami, zachowaj to samo znaczenie ale użyj alternatywnych sformułowań",
      "fr" =>
        "Reformule la traduction en utilisant des mots différents, garde le même sens mais utilise des formulations alternatives",
      "pt" =>
        "Reformule a tradução usando palavras diferentes, mantenha o mesmo significado mas use frases alternativas"
    },
    synonyms: %{
      "uk" => "Використай синоніми в перекладі, заміни ключові слова на їх синоніми",
      "en" => "Use synonyms in the translation, replace key words with their synonyms",
      "es" => "Usa sinónimos en la traducción, reemplaza las palabras clave por sus sinónimos",
      "de" => "Verwende Synonyme in der Übersetzung, ersetze Schlüsselwörter durch ihre Synonyme",
      "pl" => "Użyj synonimów w tłumaczeniu, zamień kluczowe słowa na ich synonimy",
      "fr" =>
        "Utilise des synonymes dans la traduction, remplace les mots clés par leurs synonymes",
      "pt" => "Use sinônimos na tradução, substitua as palavras-chave por seus sinônimos"
    }
  }

  @doc """
  Returns the prompt for a given action and language code.

  The language code is a POSIX locale (e.g., "uk", "es", "pt_BR").
  Falls back to English if the locale is not supported.

  ## Examples

      iex> PromptTemplates.get_prompt(:rephrase, "uk")
      "Перефразуй переклад іншими словами, збережи той самий зміст але використай інші конструкції"

      iex> PromptTemplates.get_prompt(:regenerate, "pt_BR")
      "Traduza este texto novamente, ofereça uma nova alternativa de tradução"

      iex> PromptTemplates.get_prompt(:short_version, "ja")
      "Make the translation as short as possible while keeping the core meaning"
  """
  @spec get_prompt(action(), String.t()) :: String.t()
  def get_prompt(action, language_code) when is_atom(action) and is_binary(language_code) do
    lang = extract_base_language(language_code)

    @prompts
    |> Map.get(action, %{})
    |> Map.get(lang, Map.get(@prompts[action] || %{}, "en", ""))
  end

  @doc """
  Returns the list of available quick actions.

  ## Examples

      iex> PromptTemplates.actions()
      [:regenerate, :short_version, :rephrase, :synonyms]
  """
  @spec actions() :: [action()]
  def actions, do: [:regenerate, :short_version, :rephrase, :synonyms]

  @doc """
  Returns a human-readable label for a quick action.

  ## Examples

      iex> PromptTemplates.action_label(:short_version)
      "Short Version"
  """
  @spec action_label(action()) :: String.t()
  def action_label(:regenerate), do: "Regenerate"
  def action_label(:short_version), do: "Short Version"
  def action_label(:rephrase), do: "Rephrase"
  def action_label(:synonyms), do: "Synonyms"

  # Extracts the two-letter base language from a POSIX locale code.
  # "pt_BR" -> "pt", "en_US" -> "en", "uk" -> "uk"
  defp extract_base_language(code) do
    code
    |> String.split("_")
    |> hd()
    |> String.downcase()
  end
end
