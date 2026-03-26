defmodule GettextTranslator.Util.LanguageNames do
  @moduledoc """
  Maps POSIX language codes to full language names and ISO codes.
  Used primarily for TranslateGemma prompt formatting.
  """

  @language_map %{
    "af" => %{name: "Afrikaans", code: "af"},
    "am" => %{name: "Amharic", code: "am"},
    "ar" => %{name: "Arabic", code: "ar"},
    "az" => %{name: "Azerbaijani", code: "az"},
    "be" => %{name: "Belarusian", code: "be"},
    "bg" => %{name: "Bulgarian", code: "bg"},
    "bn" => %{name: "Bengali", code: "bn"},
    "bs" => %{name: "Bosnian", code: "bs"},
    "ca" => %{name: "Catalan", code: "ca"},
    "cs" => %{name: "Czech", code: "cs"},
    "cy" => %{name: "Welsh", code: "cy"},
    "da" => %{name: "Danish", code: "da"},
    "de" => %{name: "German", code: "de"},
    "el" => %{name: "Greek", code: "el"},
    "en" => %{name: "English", code: "en"},
    "es" => %{name: "Spanish", code: "es"},
    "et" => %{name: "Estonian", code: "et"},
    "eu" => %{name: "Basque", code: "eu"},
    "fa" => %{name: "Persian", code: "fa"},
    "fi" => %{name: "Finnish", code: "fi"},
    "fil" => %{name: "Filipino", code: "fil"},
    "fr" => %{name: "French", code: "fr"},
    "ga" => %{name: "Irish", code: "ga"},
    "gl" => %{name: "Galician", code: "gl"},
    "gu" => %{name: "Gujarati", code: "gu"},
    "ha" => %{name: "Hausa", code: "ha"},
    "he" => %{name: "Hebrew", code: "he"},
    "hi" => %{name: "Hindi", code: "hi"},
    "hr" => %{name: "Croatian", code: "hr"},
    "hu" => %{name: "Hungarian", code: "hu"},
    "hy" => %{name: "Armenian", code: "hy"},
    "id" => %{name: "Indonesian", code: "id"},
    "ig" => %{name: "Igbo", code: "ig"},
    "is" => %{name: "Icelandic", code: "is"},
    "it" => %{name: "Italian", code: "it"},
    "ja" => %{name: "Japanese", code: "ja"},
    "jv" => %{name: "Javanese", code: "jv"},
    "ka" => %{name: "Georgian", code: "ka"},
    "kk" => %{name: "Kazakh", code: "kk"},
    "km" => %{name: "Khmer", code: "km"},
    "kn" => %{name: "Kannada", code: "kn"},
    "ko" => %{name: "Korean", code: "ko"},
    "lo" => %{name: "Lao", code: "lo"},
    "lt" => %{name: "Lithuanian", code: "lt"},
    "lv" => %{name: "Latvian", code: "lv"},
    "mk" => %{name: "Macedonian", code: "mk"},
    "ml" => %{name: "Malayalam", code: "ml"},
    "mn" => %{name: "Mongolian", code: "mn"},
    "mr" => %{name: "Marathi", code: "mr"},
    "ms" => %{name: "Malay", code: "ms"},
    "mt" => %{name: "Maltese", code: "mt"},
    "my" => %{name: "Burmese", code: "my"},
    "nb" => %{name: "Norwegian Bokmål", code: "nb"},
    "ne" => %{name: "Nepali", code: "ne"},
    "nl" => %{name: "Dutch", code: "nl"},
    "nn" => %{name: "Norwegian Nynorsk", code: "nn"},
    "no" => %{name: "Norwegian", code: "no"},
    "pa" => %{name: "Punjabi", code: "pa"},
    "pl" => %{name: "Polish", code: "pl"},
    "pt" => %{name: "Portuguese", code: "pt"},
    "pt_BR" => %{name: "Portuguese", code: "pt-BR"},
    "pt_PT" => %{name: "Portuguese", code: "pt-PT"},
    "ro" => %{name: "Romanian", code: "ro"},
    "ru" => %{name: "Russian", code: "ru"},
    "si" => %{name: "Sinhala", code: "si"},
    "sk" => %{name: "Slovak", code: "sk"},
    "sl" => %{name: "Slovenian", code: "sl"},
    "so" => %{name: "Somali", code: "so"},
    "sq" => %{name: "Albanian", code: "sq"},
    "sr" => %{name: "Serbian", code: "sr"},
    "sv" => %{name: "Swedish", code: "sv"},
    "sw" => %{name: "Swahili", code: "sw"},
    "ta" => %{name: "Tamil", code: "ta"},
    "te" => %{name: "Telugu", code: "te"},
    "th" => %{name: "Thai", code: "th"},
    "tr" => %{name: "Turkish", code: "tr"},
    "uk" => %{name: "Ukrainian", code: "uk"},
    "ur" => %{name: "Urdu", code: "ur"},
    "uz" => %{name: "Uzbek", code: "uz"},
    "vi" => %{name: "Vietnamese", code: "vi"},
    "yo" => %{name: "Yoruba", code: "yo"},
    "zh" => %{name: "Chinese", code: "zh"},
    "zh_CN" => %{name: "Chinese (Simplified)", code: "zh-Hans"},
    "zh_Hans" => %{name: "Chinese (Simplified)", code: "zh-Hans"},
    "zh_TW" => %{name: "Chinese (Traditional)", code: "zh-Hant"},
    "zh_Hant" => %{name: "Chinese (Traditional)", code: "zh-Hant"},
    "zu" => %{name: "Zulu", code: "zu"}
  }

  @doc """
  Returns the full language name for a given POSIX locale code.

  Falls back to the base language if the full code is not found,
  and to the code itself if no mapping exists.

  ## Examples

      iex> GettextTranslator.Util.LanguageNames.language_name("en")
      "English"

      iex> GettextTranslator.Util.LanguageNames.language_name("pt_BR")
      "Portuguese"

      iex> GettextTranslator.Util.LanguageNames.language_name("unknown")
      "unknown"
  """
  @spec language_name(String.t()) :: String.t()
  def language_name(posix_code) do
    case Map.get(@language_map, posix_code) do
      %{name: name} -> name
      nil -> fallback_language_name(posix_code)
    end
  end

  @doc """
  Returns the ISO/BCP47 language code for a given POSIX locale code.

  Converts POSIX underscore format (pt_BR) to BCP47 hyphen format (pt-BR).

  ## Examples

      iex> GettextTranslator.Util.LanguageNames.iso_code("en")
      "en"

      iex> GettextTranslator.Util.LanguageNames.iso_code("pt_BR")
      "pt-BR"

      iex> GettextTranslator.Util.LanguageNames.iso_code("zh_CN")
      "zh-Hans"
  """
  @spec iso_code(String.t()) :: String.t()
  def iso_code(posix_code) do
    case Map.get(@language_map, posix_code) do
      %{code: code} -> code
      nil -> fallback_iso_code(posix_code)
    end
  end

  defp fallback_language_name(posix_code) do
    base = extract_base_language(posix_code)

    if base != posix_code do
      case Map.get(@language_map, base) do
        %{name: name} -> name
        nil -> posix_code
      end
    else
      posix_code
    end
  end

  defp fallback_iso_code(posix_code) do
    base = extract_base_language(posix_code)

    if base != posix_code do
      case Map.get(@language_map, base) do
        %{code: code} -> code
        nil -> String.replace(posix_code, "_", "-")
      end
    else
      posix_code
    end
  end

  defp extract_base_language(code) do
    code |> String.split("_") |> List.first()
  end
end
