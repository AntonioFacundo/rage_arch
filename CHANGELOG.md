# Changelog

## [0.2.0] - 2026-04-01

### Added
- Convention-based `use_case_symbol` inference from class name and file location
- Auto-registration of use cases from `app/use_cases/` at boot
- Auto-registration of deps from `app/deps/` at boot
- AR model auto-resolution: `:slot_store` resolves to `Slot` if no dep file exists
- `undo` support: define `def undo(value)` on any use case, called automatically on failure
- Cascade `undo` when orchestrating via `use_cases` — reverse-order rollback
- Async subscribers by default via ActiveJob — `async: false` to opt out
- `config.rage_arch.async_subscribers = false` for test environments
- `RageArch.isolate` for scoped container in tests
- `RageArch::RSpecHelpers` module for automatic test isolation
- `RageArch::SubscriberJob` internal ActiveJob for async subscriber dispatch
- Boot verification: symbol/convention mismatch warning
- Boot verification: AR model not found for `_store` dep error

### Removed
- `ar_dep` macro inside use cases
- `rails g rage_arch:ar_dep` generator

### Migration from 0.1.x
- Remove `use_case_symbol` declarations that match the convention (optional cleanup)
- Remove `ar_dep :store, Model` from use cases — delete the line entirely,
  rage_arch resolves the model automatically if `app/deps/` has no override
- Remove explicit `RageArch.register` calls for use cases and standard deps —
  auto-registration handles them. Keep only external adapters (Stripe, etc.)
- Add `config.rage_arch.async_subscribers = false` to `config/environments/test.rb`
  if your tests depend on synchronous subscriber execution

## [0.1.4] - 2026-03-31

### Fixed
- Renamed `config.rage.*` to `config.rage_arch.*` in code and documentation
- Renamed `"rage.use_case.run"` to `"rage_arch.use_case.run"` instrumentation event
- Fixed Gemfile.lock gem name from `rage` to `rage_arch`
- Renamed all `rage:` generator references to `rage_arch:` in docs and comments

### Improved
- Expanded README with deps section, all generators, configuration, and examples
