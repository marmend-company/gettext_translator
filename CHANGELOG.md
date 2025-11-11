# Changelog

All notable changes to this project will be documented in this file.

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
