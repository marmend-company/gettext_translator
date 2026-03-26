defmodule GettextTranslator.TranslateGemmaTest do
  use ExUnit.Case

  alias GettextTranslator.Processor.LLM
  alias GettextTranslator.Util.LanguageNames

  describe "translategemma?/1" do
    test "identifies TranslateGemma model names" do
      assert LLM.translategemma?("translategemma-4b")
      assert LLM.translategemma?("translategemma-12b")
      assert LLM.translategemma?("translategemma-27b")
      assert LLM.translategemma?("TranslateGemma-27b")
      assert LLM.translategemma?("TRANSLATEGEMMA-4B")
      assert LLM.translategemma?("google/translategemma-27b")
    end

    test "does not match non-TranslateGemma models" do
      refute LLM.translategemma?("gpt-4")
      refute LLM.translategemma?("claude-sonnet-4-5-20250929")
      refute LLM.translategemma?("llama3.2:latest")
      refute LLM.translategemma?("gemma-3-27b")
    end
  end

  describe "build_translategemma_prompt/3" do
    test "builds correct prompt for English to Spanish" do
      prompt = LLM.build_translategemma_prompt("Hello, how are you?", "en", "es")

      assert prompt ==
               "You are a professional English (en) to Spanish (es) translator. " <>
                 "Your goal is to accurately convey the meaning and nuances of the original English text " <>
                 "while adhering to Spanish grammar, vocabulary, and cultural sensitivities.\n" <>
                 "Produce only the Spanish translation, without any additional explanations or commentary. " <>
                 "Please translate the following English text into Spanish:\n\n\nHello, how are you?"
    end

    test "builds correct prompt for German to English" do
      prompt =
        LLM.build_translategemma_prompt("Guten Morgen, wie geht es Ihnen?", "de", "en")

      assert prompt ==
               "You are a professional German (de) to English (en) translator. " <>
                 "Your goal is to accurately convey the meaning and nuances of the original German text " <>
                 "while adhering to English grammar, vocabulary, and cultural sensitivities.\n" <>
                 "Produce only the English translation, without any additional explanations or commentary. " <>
                 "Please translate the following German text into English:\n\n\nGuten Morgen, wie geht es Ihnen?"
    end

    test "handles POSIX codes with region variants" do
      prompt = LLM.build_translategemma_prompt("Hello", "en", "pt_BR")

      assert String.contains?(prompt, "Portuguese (pt-BR)")
      assert String.contains?(prompt, "English (en)")
    end

    test "handles Chinese simplified code" do
      prompt = LLM.build_translategemma_prompt("Hello", "zh_CN", "en")

      assert String.contains?(prompt, "Chinese (Simplified) (zh-Hans)")
    end

    test "includes two blank lines before the text" do
      prompt = LLM.build_translategemma_prompt("Test message", "en", "de")

      assert String.ends_with?(prompt, "\n\n\nTest message")
    end
  end

  describe "LanguageNames.language_name/1" do
    test "returns full language name for known codes" do
      assert LanguageNames.language_name("en") == "English"
      assert LanguageNames.language_name("es") == "Spanish"
      assert LanguageNames.language_name("de") == "German"
      assert LanguageNames.language_name("ja") == "Japanese"
      assert LanguageNames.language_name("uk") == "Ukrainian"
    end

    test "returns name for regional variants" do
      assert LanguageNames.language_name("pt_BR") == "Portuguese"
      assert LanguageNames.language_name("zh_CN") == "Chinese (Simplified)"
      assert LanguageNames.language_name("zh_TW") == "Chinese (Traditional)"
    end

    test "falls back to base language for unknown regional variant" do
      assert LanguageNames.language_name("es_MX") == "Spanish"
    end

    test "returns code itself for completely unknown languages" do
      assert LanguageNames.language_name("xx") == "xx"
    end
  end

  describe "LanguageNames.iso_code/1" do
    test "returns ISO code for known POSIX codes" do
      assert LanguageNames.iso_code("en") == "en"
      assert LanguageNames.iso_code("es") == "es"
      assert LanguageNames.iso_code("ja") == "ja"
    end

    test "converts POSIX regional codes to BCP47 format" do
      assert LanguageNames.iso_code("pt_BR") == "pt-BR"
      assert LanguageNames.iso_code("zh_CN") == "zh-Hans"
      assert LanguageNames.iso_code("zh_TW") == "zh-Hant"
    end

    test "converts unknown regional codes using underscore to hyphen" do
      assert LanguageNames.iso_code("es_MX") == "es"
    end
  end
end
