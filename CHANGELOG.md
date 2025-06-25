# Changelog

All notable changes to this project will be documented in this file.

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
