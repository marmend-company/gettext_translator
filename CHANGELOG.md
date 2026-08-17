# Changelog

All notable changes to this project will be documented in this file.

## [0.9.3] - 2026-08-17

Self-hosted **vLLM** — and any OpenAI-compatible gateway — is now supported end to
end. The provider can be **configured inline** in your application config, and that
same provider can still be **overridden per session** from the dashboard. Since
0.9.2 the LiveDashboard **Override LLM Provider** form offers a vLLM adapter you can
point at a gateway by hand; this release closes the loop, so an instance that already
has a gateway in its config no longer has to retype it: the form opens on the
configured provider, and anything you do type overrides it.

### Added

- **`:default_provider` — configure the provider inline, override it when you want.**
  An instance whose endpoint and API key already come from its own environment
  should not make an operator retype them into a dashboard form. Naming the
  provider your config is for:

  ```elixir
  config :gettext_translator, GettextTranslator,
    endpoint: MyApp.LLM.ChatVLLM,
    endpoint_model: System.get_env("GETTEXT_TRANSLATOR_MODEL", "gemma-4-26b-a4b-it"),
    default_provider: :vllm
  ```

  opens the **Override LLM Provider** form with that adapter selected and
  `:endpoint_model` filled in, marks API Key and Endpoint URL optional, and treats
  a blank field as "use what the instance is configured with". Submitting the form
  unchanged translates against your gateway.

  Crucially, the override then routes through your **own** `:endpoint` module
  rather than the generic `LangChain.ChatModels.ChatOpenAI`. For a self-hosted
  gateway that is the difference between working and not: a module like
  `MyApp.LLM.ChatVLLM` resolves its endpoint and bearer token itself, whereas
  `ChatOpenAI` requires the full `/v1/chat/completions` URL to be supplied by hand.

  Anything typed into the form still wins, selecting a different provider behaves
  exactly as before — and never inherits the configured provider's credentials —
  and leaving `:default_provider` unset preserves the previous behavior exactly:
  nothing at all is inherited unless the option opts in.

  The value is validated against `Parser.known_providers/0`; an unrecognized slug
  is refused with a logged warning rather than accepted, because it would match no
  `<option>` and leave the browser selecting OpenAI while the model stayed
  prefilled from config.

  Exposed as `GettextTranslator.Util.Parser.instance_default/0`,
  `provider_label/1`, `known_providers/0` and `resolve_override/2` — the override
  form's provider/credential resolution moved out of the LiveDashboard page into
  `Parser`, where it is config resolution rather than view logic and is directly
  unit-tested.

### Changed

- **Dependencies:** `langchain` 0.9.2 → **0.10.0**, `phoenix_live_dashboard` 0.8.7 →
  **0.9.0**, `phoenix_live_view` 1.2.6 → **1.2.9**, plus transitive `phoenix` 1.8.11,
  `req` 0.7.2, `ecto` 3.14.2, `mint` 1.9.3 and `plug_crypto` 2.2.0.

  The requirements in `mix.exs` are **unchanged** and stay deliberately open —
  `langchain >= 0.8.0`, `phoenix_live_dashboard >= 0.6.0`,
  `phoenix_live_view >= 0.17.0` — so host applications remain free to resolve their
  own versions. Only `mix.lock` moved.

  LangChain 0.10.0's breaking changes are confined to `Message.status` — stream
  failures now report `:stream_error` rather than `:cancelled`, and a provider
  content filter (or an Anthropic `"refusal"` stop reason) now reports
  `:content_filtered` rather than `:complete`. None of them reach this library:
  it never enables streaming, registers no callbacks, and never matches on
  `Message.status` — only on `{:ok, %{last_message: %Message{content: content}}}`
  and `{:error, _, reason}`.

  The call surface is otherwise untouched. `LLMChain.new!/1`, `add_messages/2`
  and `run/1`, `Message.new_system!/1` and `new_user!/1`,
  `ContentPart.parts_to_string/1`, and the `ChatOpenAI`, `ChatAnthropic`,
  `ChatOllamaAI` and `ChatGoogleAI` adapters all keep their signatures — no
  public function was added or removed in any module this library calls, and
  `run/1` still returns `{:ok, chain}` / `{:error, chain, error}`.

### Fixed

- **An unset token env var now reports "token not configured" instead of failing
  obscurely.** Both the GitHub and GitLab pull-request clients read their token
  with `Map.get(config, :key, "")`, whose default only applies to a *missing* key.
  The usual config shape — `github_token: System.get_env("GITHUB_TOKEN")` with the
  variable unset — produces a key that is present and `nil`, which slipped past the
  `token == ""` guard and was sent as a nil HTTP header value, failing deep inside
  the client. Both clients now coalesce nil to `""` and return the intended error.

## [0.9.2] - 2026-07-13

### Added

- **First-class vLLM provider.** The LiveDashboard **Override LLM Provider** form now
  offers a **vLLM (OpenAI-compatible)** adapter alongside OpenAI, Anthropic, Ollama, and
  Google AI. It maps to `LangChain.ChatModels.ChatOpenAI` (vLLM speaks the OpenAI wire
  format) with the endpoint URL you supply, so a self-hosted gateway behind nginx + a
  bearer token can be selected per session without editing config files. See the new
  "Using vLLM" section in the README.

### Fixed

- **Custom OpenAI-compatible base URLs are now actually used.** `ChatOpenAI` reads its
  base URL only from the struct passed to `new!/1` — it does not resolve one from
  application env — but the translation chain never threaded the configured endpoint into
  that struct. As a result, a configured `"openai_endpoint"` (or a dashboard-override
  endpoint URL) was silently ignored and every request went to
  `https://api.openai.com/v1/chat/completions`. The endpoint is now threaded into the
  adapter via the new `GettextTranslator.Processor.LLM.build_llm_attrs/1`, honoring both
  the `"openai_endpoint"` (documented config) and `"endpoint"` (dashboard override) keys.
  This makes the documented custom-endpoint configuration — and the new vLLM option —
  work as described.

## [0.9.1] - 2026-07-11

### Fixed

- **Higher plural forms are no longer corrupted on dashboard save.** Saving from
  the LiveDashboard rewrites every already-translated entry, and for plural messages the
  third-and-up forms (`msgstr[2]`+) were rebuilt from the store — which only tracks
  `msgstr[0]` and `msgstr[1]` — so `msgstr[2]` was silently overwritten with a copy of
  `msgstr[1]` (e.g. Ukrainian "кредитів" became "кредити"). `PoHelper.update_po_message/2`
  now preserves any non-empty higher plural forms already present in the PO file and only
  fills them with the generic plural translation when they are still empty. The hardcoded
  `uk`/`ru`/`pl` language list is gone: the PO file's own `msgstr[n]` keys (from
  `Plural-Forms`/`nplurals`) define which forms exist, so all languages — including
  6-form ones like Arabic — are handled correctly. An explicit `:plural_translation_2`
  on a translation entry still overrides `msgstr[2]` when provided.
- **`mix gettext_translator.run` no longer drops higher plural forms.** The CLI processor
  replaced the whole `msgstr` map with only forms 0 and 1 when translating pending plural
  messages, deleting the `msgstr[2]` line entirely for three-form languages. It now reuses
  the same form-preserving update logic as the dashboard.
- **Changelog JSON files no longer churn in diffs.** Entries whose text and status are
  unchanged keep their original `last_updated` timestamp (previously every pending entry
  was rewritten with a fresh timestamp on each dashboard session), and the JSON output is
  now deterministically sorted by message id — so `translation_changelog/*.json` diffs
  only show real changes instead of hundreds of rewritten lines.

### Changed

- Removed the unreachable `[TRANSLATION_FAILED]` fallback in the CLI plural path
  (`LLM.translate/2` already falls back to an empty translation on provider errors),
  fixing an Elixir 1.20 type-inference warning. Cleaned up remaining unused
  `require Logger` warnings.
- `jason` is now a declared dependency (`~> 1.4`). It was already used at runtime for
  changelog persistence but was only available transitively.

### Dependencies

- Verified compatibility with **LangChain 0.9.x** and bumped the lockfile to 0.9.2.
  LangChain 0.9.0's breaking changes are confined to telemetry event names and custom
  `ChatModel` implementations; the `LLMChain.run/2` / message-construction APIs used by
  this library are unchanged.
- Lockfile bumps with security fixes for transitive deps: `req` 0.5.18 → 0.6.2 and
  `mint` 1.8.0 → 1.9.1 (HIGH CVEs), `plug` 1.19.2 → 1.20.3, `hpax` 1.0.3 → 1.0.4,
  `phoenix` 1.8.7 → 1.8.9, `finch` 0.22.0 → 0.23.0, `phoenix_live_view`
  1.1.31 → 1.2.6, `credo` 1.7.18 → 1.7.19.

## [0.9.0] - 2026-06-01

### Changed

- **LangChain requirement widened to `>= 0.8.0`** (was `~> 0.6.2`). The open upper
  bound means GettextTranslator no longer pins a maximum LangChain version, so host
  applications are free to upgrade LangChain (0.8.x, 0.9.x, …) without this library
  blocking dependency resolution. Verified compiling and testing clean against
  LangChain 0.8.11. The existing `ContentPart` / `LLMChain.run/2` handling already
  covers the upstream content-structure and return-value changes introduced in 0.4.0.

### Added

- **Configurable request retries** — New optional `:endpoint_retry_count` config key,
  forwarded to the chat model constructor. Since LangChain 0.7.0 disabled Req-level
  HTTP retries by default and surfaces transient `429`/`503` errors after `retry_count`
  attempts (upstream default: `2`), this lets you raise or disable retries for
  rate-limited endpoints. When omitted, the chat model's own default is used.

### Dependencies

- Bumped tooling/optional dependencies to latest within existing requirements:
  `credo` 1.7.16 → 1.7.18, `ex_doc` 0.40.1 → 0.40.3,
  `phoenix_live_view` 1.1.22 → 1.1.31.

## [0.8.0] - 2026-03-26

### Added

- **TranslateGemma Support** — Automatic detection and prompt formatting for Google's TranslateGemma open translation models (4B, 12B, 27B). When the model name contains "translategemma" (case-insensitive), the library uses the model's required prompt structure: a single user message with professional translator persona, source/target language names and ISO codes, and two blank lines before the text to translate. No system message is sent.
- **Source Language Configuration** — New `:source_language` config option to specify the language of `msgid` strings (defaults to `"en"`). Used by TranslateGemma to build accurate source-to-target translation prompts.
- **Language Names Utility** — New `GettextTranslator.Util.LanguageNames` module mapping 90+ POSIX locale codes to full language names and ISO/BCP47 codes. Handles regional variants (e.g., `pt_BR` -> "Portuguese" / `pt-BR`, `zh_CN` -> "Chinese (Simplified)" / `zh-Hans`).

### Changed

- `GettextTranslator.Processor.LLM` now branches prompt construction based on model type: TranslateGemma models use the dedicated format, all other models use the existing system+user message format unchanged.
- Provider type updated to include `source_language` field across parser, translator type, and dashboard resolver.

## [0.7.0] - 2026-02-28

### Breaking Changes

**LangChain Upgrade: 0.5.x → 0.6.0**

This release upgrades the LangChain dependency from ~> 0.5.0 to ~> 0.6.0, which includes new features and breaking changes upstream.

#### Upstream Breaking Changes (LangChain 0.6.0)

- **DeepResearch Source Migration** — Inline `Source` struct replaced with unified `Citation`/`CitationSource` structs
- **Perplexity Response Format** — Content now returns as `ContentPart` structs instead of plain strings
- **Google AI Grounding Metadata** — Raw metadata moved to `message.metadata["grounding_metadata"]`

> **Note**: These upstream changes do not affect the core translation workflow of this library, as it does not use DeepResearch, Perplexity, or Google AI grounding features directly.

#### New Upstream Features Available

- **Citations Support** — Unified citation abstraction across all providers (Anthropic, OpenAI, Google AI, Perplexity)
- **Customizable Run Modes** — Composable execution modes (`WhileNeedsResponse`, `UntilSuccess`, `Step`, `UntilToolUsed`)
- **Streaming Reasoning Callbacks** — `on_llm_reasoning_delta` for Azure OpenAI reasoning summaries

### Added

- **Quick Prompt Buttons** — Locale-aware translation action buttons (Regenerate, Short Version, Rephrase, Synonyms) in the translation details panel
- **PromptTemplates Module** — New `GettextTranslator.Dashboard.PromptTemplates` module with per-locale prompt templates for 7 languages (English, Ukrainian, Spanish, German, Polish, French, Portuguese)
- **Quick Translate Event** — New `llm_quick_translate` LiveView event handler for executing prompt-based translation actions

### Changed

- Renamed "LLM Translate" button to "GPT" for brevity
- Updated LangChain dependency from ~> 0.5.0 to ~> 0.6.0

## [0.6.0] - 2026-02-11

### Added

- **Dashboard Tab Navigation** — Page-level tabs separating Translation Stats, New Extracted, and New Translated views for a streamlined workflow
- **Extract & Merge from Dashboard** — Run `mix gettext.extract --merge --no-fuzzy` directly from the dashboard UI; automatically switches to the New Extracted tab to show newly discovered strings
- **Batch Translate All Pending** — Translate every pending entry in a single click with real-time progress bar tracking; uses sequential processing to respect LLM API rate limits
- **New Translated Review Tab** — After batch translation, a dedicated tab appears showing all translations from the current session grouped by language and domain, allowing review, editing, and approval before saving
- **LLM Provider Override** — Session-scoped form to switch AI adapter (OpenAI, Anthropic, Ollama, Google AI), model, API key, and endpoint URL without modifying config files
- **Extractor Module** — New `GettextTranslator.Util.Extractor` for dev/prod-aware extraction (System.cmd in dev, Expo-based merge in releases)

### Changed

- Dashboard UI restructured from flat view to tab-based navigation
- Improved session-based config passing between `init` and `mount` for reliable path resolution across LiveDashboard page loads
- Updated README with full dashboard workflow documentation and screenshots

### Fixed

- Fixed `gettext_path` being nil on page reload by passing config through the LiveDashboard session instead of relying solely on ETS/persistent_term

## [0.5.0] - 2025-11-11

### Breaking Changes

**LangChain Upgrade: 0.3.3 → 0.4.0**

This release upgrades the LangChain dependency from 0.3.3 to 0.4.0, which introduces breaking changes in how LLM responses are handled.

#### What Changed

- **Message Content Structure**: LangChain 0.4.0 returns message content as a list of `ContentPart` structs instead of plain strings
  - Before: `%Message{content: "text response"}`
  - After: `%Message{content: [%ContentPart{type: :text, content: "text response"}]}`
  - The library now automatically converts this using `ContentPart.parts_to_string/1`

#### Model Support Changes

LangChain 0.4.0 officially supports only the following LLM providers:
- ✅ **OpenAI ChatGPT** - Fully supported
- ✅ **Anthropic Claude** - Fully supported
- ✅ **Google Gemini** - Fully supported
- ✅ **Google Vertex AI** - Fully supported
- ❌ **Other models** - May not work with LangChain 0.4.0

**Important**: If you're using ChatOllamaAI or other unsupported models, they may not function correctly with this version. We recommend:
1. Testing your specific model after upgrading
2. Using one of the officially supported providers
3. Implementing a custom adapter if needed
4. Staying on version 0.4.5 if you require unsupported models

#### Migration Notes

If you're upgrading from 0.4.5 to 0.5.0:

1. **No configuration changes required** - Your existing configuration will continue to work
2. **Test your LLM provider** - Verify translations work with your chosen provider
3. **Check the updated README** - New examples added for Anthropic Claude, Google Gemini, and custom endpoints

### Added

- Support for Anthropic Claude via `LangChain.ChatModels.ChatAnthropic`
- Support for Google Gemini via `LangChain.ChatModels.ChatGoogleAI`
- Comprehensive documentation for custom remote LLM endpoints
- Examples of sync and streaming response formats for custom endpoints

### Changed

- Updated LangChain dependency from 0.3.3 to ~> 0.4.0
- Modified message content handling to support new ContentPart structure
- Updated README with additional provider examples and custom endpoint configuration

### Technical Details

The `translate/2` function in `GettextTranslator.Processor.LLM` now:
- Pattern matches on `{:ok, %{last_message: %Message{content: content}}}`
- Converts ContentPart list to string using `ContentPart.parts_to_string/1`
- Maintains backward compatibility with existing configurations

## [0.4.5] - 2025-09-03
- Fixed bug regarding  nil values in the message strings that the Expo.PO.Composer can't handle.

## [0.4.4] - 2025-06-25
- Fixed bug with plural translations [#14](https://github.com/marmend-company/gettext_translator/issues/14)

## [0.4.3] - 2025-06-25
- Fixed bug regarding a new creation of changelog entries when making PRs to gitlab.

## [0.4.2] - 2025-05-08
- Fixed difference in changelog structure when making PR and saving locally to files.

## [0.4.1] - 2025-05-08
- Fixed bugs.

## [0.4.0] - 2025-05-08
    [Breaking chanegs]
- Reworked changelog integration to use a simple 1:1 mapping between translations and changelog entries. Previous changelog will be overwritten, therefore new changelog entries will be created with a different structure.
- Fixed bugs, refactored code.
- Added visibility which changes are done in current session and will be commited or saved to files.

## [0.3.0] - 2025-05-04
- Git integration for committing changes as PRs.
- Support Gitlab and Github (not fully tested).

## [0.2.3] - 2025-05-01
- Fixes for release environments

## [0.2.2] - 2025-05-01
- Update regex pattern in `extract_language_code/1` to correctly match LC_MESSAGES folder structure
- Extract common path patterns to module attributes to reduce repetition
- Add private `app_path/2` helper to standardize path generation
- Ensure consistent path handling across all helper functions

## [0.2.1] - 2025-05-01

### Fixed
- Fixed path resolution in release environments by using Application.app_dir
- Added application parameter to properly resolve paths in releases
- Fixed Ukrainian pluralization by adding support for required third plural form
- Modified TranslationStore to correctly save and load translations in releases
- Added ETS-based configuration for LiveDashboard integration
- Improved PathHelper to handle both development and production environments

### Added
- New helpers for proper path resolution in both dev and release environments
- ETS-based configuration state management between LiveView mounts
- Support for additional plural forms required by specific languages

## [0.2.0] - 2025-03-08
### Added
- Phoenix LiveDashboard integration for monitoring and managing translations
- In-memory translation store using ETS tables
- Web UI for viewing, editing, and approving translations
- Filtering and pagination in dashboard
- Improved documentation with dashboard setup guide

### Fixed
- LLM integration for gettext files.

## [0.1.0] - 2025-02-23
### Added
- Initial release of GettextTranslator.
- Multi-provider support for AI translation.
- CLI integration for translating Gettext files.
- Basic documentation and configuration examples.
