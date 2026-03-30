# RageArch — API Reference

Quick-lookup reference for all classes, methods, and configuration options. For detailed explanations, see [DOCUMENTATION.md](DOCUMENTATION.md). For step-by-step tasks, see [GETTING_STARTED.md](GETTING_STARTED.md). For a high-level overview, see the [README](../README.md).

---

## RageArch (module)

| Method | Description |
|--------|-------------|
| `register(symbol, impl)` | Register a dep by symbol. `impl` can be an instance, class, or block. |
| `register_ar(symbol, Model)` | Register an AR adapter for `Model` (provides `build`, `find`, `save`, `update`, `destroy`, `list`). |
| `resolve(symbol)` | Returns the registered implementation. Raises if not found. |
| `registered?(symbol)` | Returns `true` if the symbol is registered. |
| `verify_deps!` | Checks all use case wiring at boot. Raises `RuntimeError` listing problems. |

---

## RageArch::Result

| Method | Description |
|--------|-------------|
| `Result.success(value)` | Creates a successful result. `value` can be any object. |
| `Result.failure(errors)` | Creates a failed result. `errors` is typically an Array or Hash. |
| `result.success?` | `true` if success. |
| `result.failure?` | `true` if failure. |
| `result.value` | The value (success only, `nil` on failure). |
| `result.errors` | The errors (failure only, `nil` on success). |

---

## RageArch::UseCase::Base

### Class methods (DSL)

| Method | Description |
|--------|-------------|
| `use_case_symbol :sym` | Registers this use case under `:sym`. Must be unique. Required. |
| `deps :a, :b, ...` | Declares dependencies by symbol. Injected from the container at build time. Available as private methods. |
| `ar_dep :sym, Model` | Declares a dep that falls back to `RageArch::Deps::ActiveRecord.for(Model)` if `:sym` is not registered. |
| `use_cases :uc1, :uc2, ...` | Declares other use cases this one may call. Each symbol becomes a private method returning a runner. |
| `subscribe :ev1, :ev2, ...` | Runs this use case when the listed events are published. |
| `subscribe :all` | Runs this use case on every published event. Payload includes `:event`. |
| `skip_auto_publish` | Prevents automatic event publishing when this use case finishes. |

### Class methods (runtime)

| Method | Description |
|--------|-------------|
| `build(symbol)` | Resolves the use case class by symbol, injects deps, returns an instance. |
| `wire_subscriptions_to(publisher)` | Iterates all registered use cases and wires their `subscribe` declarations to the given publisher. |

### Instance methods

| Method | Description |
|--------|-------------|
| `call(params = {})` | Entry point. Implement in subclass. Must return a `Result`. |
| `success(value)` | Returns `RageArch::Result.success(value)`. |
| `failure(errors)` | Returns `RageArch::Result.failure(errors)`. |

### Auto-publish payload

When a use case finishes and auto-publish is enabled, the framework publishes an event with this payload:

| Key | Value |
|-----|-------|
| `use_case` | The use case symbol |
| `params` | Params passed to `call` |
| `success` | `true` or `false` |
| `value` | `result.value` |
| `errors` | `result.errors` |

---

## RageArch::Controller

Include in `ApplicationController` (done by `rails g rage_arch:install`). All methods are **private**.

| Method | Description |
|--------|-------------|
| `run(symbol, params = {}, success:, failure:)` | Builds and runs the use case. Calls `success` or `failure` proc with the `Result`. |
| `run_result(symbol, params = {})` | Builds and runs the use case. Returns the `Result` directly. |
| `flash_errors(result)` | Sets `flash.now[:alert]` to `result.errors.join(", ")`. |

---

## RageArch::EventPublisher

| Method | Description |
|--------|-------------|
| `EventPublisher.new` | Creates a new publisher instance. |
| `subscribe(event_name, handler)` | Registers `handler` (block, callable, or use case symbol) for the event. `:all` subscribes to everything. |
| `publish(event_name, **payload)` | Publishes the event. All subscribed handlers run with the payload. `:all` handlers receive extra `:event` key. |

**Re-entrancy:** nested publish calls are limited to prevent infinite loops.

---

## RageArch::Deps::ActiveRecord

Created via `RageArch::Deps::ActiveRecord.for(Model)` or `RageArch.register_ar(:symbol, Model)`.

| Method | Implementation |
|--------|---------------|
| `build(attrs = {})` | `Model.new(attrs)` |
| `find(id)` | `Model.find_by(id: id)` |
| `save(record)` | `record.save` |
| `update(record, attrs)` | `record.update(attrs)` |
| `destroy(record)` | `record.destroy` |
| `list(filters: {})` | `Model.where(filters).to_a` |

---

## RageArch::FakeEventPublisher (testing)

| Method | Description |
|--------|-------------|
| `FakeEventPublisher.new` | Creates a fake publisher that records calls. |
| `publish(event_name, **payload)` | Records the event. Does not run handlers. |
| `subscribe(...)` | No-op. |
| `published` | Array of recorded events: `[{ event: :name, payload: { ... } }, ...]` |
| `clear` | Resets `published` to empty. |

---

## RSpec matchers

Require with `require "rage_arch/rspec_matchers"`.

| Matcher | Description |
|---------|-------------|
| `succeed_with(key: value, ...)` | Asserts `result.success?` and `result.value` includes the given pairs. Supports composable matchers. |
| `succeed_with(value)` | For non-hash values: asserts `result.success?` and `result.value == value`. |
| `fail_with_errors(errors)` | Asserts `result.failure?` and `result.errors` matches the given value or matcher. |

---

## Instrumentation

| Key | Value |
|-----|-------|
| Event name | `"rage_arch.use_case.run"` (ActiveSupport::Notifications) |
| Payload keys | `symbol`, `params`, `success`, `errors`, `result` |

```ruby
ActiveSupport::Notifications.subscribe("rage_arch.use_case.run") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[UseCase] #{event.payload[:symbol]} (#{event.duration.round}ms)"
end
```

---

## Configuration (Railtie)

Set via `config.rage_arch` in `config/application.rb` or an initializer.

| Option | Default | Description |
|--------|---------|-------------|
| `auto_publish_events` | `true` | Publish an event automatically when each use case finishes. Set `false` for manual-only. |
| `verify_deps` | `true` | Run `verify_deps!` at boot. Set `false` to skip (e.g. incremental adoption). |

---

## Generators

| Command | What it generates |
|---------|-------------------|
| `rails g rage_arch:install` | Initializer, `app/use_cases/`, `app/deps/`, controller mixin. |
| `rails g rage_arch:scaffold Model attr:type` | Model, migration, use cases (index/show/create/update/destroy), dep, controller, views, routes. Options: `--api`, `--skip-model`. |
| `rails g rage_arch:use_case Name` | Use case file. Supports namespacing: `Orders::Create`. |
| `rails g rage_arch:dep symbol [ClassName]` | Dep class with methods inferred from use case calls. Adds missing methods if file exists. |
| `rails g rage_arch:ar_dep symbol Model` | AR-backed dep (build, find, save, update, destroy, list) + extra methods from use cases. |
| `rails g rage_arch:dep_switch symbol [ClassName]` | Lists dep implementations, updates initializer registration. |

### Dep folder inference

| Symbol | Generated path | Constant |
|--------|---------------|----------|
| `:post_store` | `app/deps/posts/post_store.rb` | `Posts::PostStore` |
| `:like_store` | `app/deps/likes/like_store.rb` | `Likes::LikeStore` |
| `:email_sender` (no entity) | Folder from use cases that reference it | e.g. `Notifications::EmailSender` |

---

## Boot verification (`verify_deps!`)

Runs automatically at boot (unless `verify_deps = false`). Raises `RuntimeError` if:

| Check | Condition |
|-------|-----------|
| Missing dep | `deps :symbol` declared but `:symbol` not registered (and not `ar_dep`). |
| Missing method | Use case calls `dep.method` but registered object doesn't implement `#method`. |
| Missing use case | `use_cases :symbol` declared but `:symbol` not in registry. |

**Note:** Call `verify_deps!` manually at the end of your `after_initialize` block (after all `register` calls), not in the Railtie — the Railtie runs before `after_initialize`.
