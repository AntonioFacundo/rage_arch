# RageArch — Detailed documentation

This document describes the gem’s behaviour, API, and configuration in detail. For a getting started guide, see [GETTING_STARTED.md](GETTING_STARTED.md). For a high-level design, see [RAGE_GEM_PLAN.md](../RAGE_GEM_PLAN.md).

---

## 1. Overview

RageArch is a Clean Architecture–style layer for Rails applications:

- **Use cases** hold all application (business) logic. They receive params and dependencies (deps), return a `Result` (success or failure), and can call other use cases or publish domain events.
- **Deps** are injectable dependencies (persistence, mailer, APIs, etc.) resolved by symbol from a container. Use cases depend on symbols, not concrete classes.
- **Domain events** are published automatically when a use case finishes (configurable), or manually. Use cases can **subscribe** to events and run in response (e.g. send email, log).
- **Controllers** are thin: they build the use case, call it with params, and map the `Result` to HTTP (render/redirect, status, flash).
- **Models** stay dumb: schema and associations; no callbacks for side effects. Reactions live in use cases and event subscribers.

---

## 2. Use cases

### 2.1 Definition and registration

A use case is a class that inherits from `RageArch::UseCase::Base`, declares a **symbol**, optional **deps** and **use_cases**, and implements `call(params)`.

```ruby
class CreateOrder < RageArch::UseCase::Base
  use_case_symbol :create_order
  deps :order_store, :notifications

  def call(params = {})
    order = order_store.build(params)
    return failure(order.errors) unless order_store.save(order)
    notifications.notify(:order_created, order)
    success(order: order)
  end
end
```

- **`use_case_symbol :create_order`** — Registers this class under the symbol `:create_order`. Controllers and other use cases refer to it by this symbol. Must be unique.
- **`deps :order_store, :notifications`** — Declares dependencies. The gem injects them via the constructor when the use case is built. Each dep is available as a private method (e.g. `order_store`, `notifications`).
- **`call(params)`** — Entry point. Receives a Hash (or similar). Returns a `RageArch::Result` via `success(value)` or `failure(errors)`.

### 2.2 Building and running

- **`RageArch::UseCase::Base.build(:create_order)`** — Resolves the use case class by symbol, resolves its deps from the container (and AR defaults for `ar_dep`), and returns an instance.
- **`use_case.call(params)`** — Runs the use case and returns the `Result`.

Controllers typically use `run(:create_order, params, success: ..., failure: ...)` or `run_result(:create_order, params)` (see Controller).

### 2.3 Calling other use cases (orchestration)

Use cases in the same layer can call other use cases by symbol.

- **`use_cases :orders_create, :send_notification`** — Declares that this use case may run those use cases. For each symbol, a private method is defined that returns a runner.
- **`orders_create.call(params)`** — Runs the other use case and returns its `Result`. Implementation: `RageArch::UseCase::Base.build(:orders_create).call(params)`.

Example:

```ruby
class CreateOrderWithNotification < RageArch::UseCase::Base
  use_case_symbol :create_order_with_notification
  deps :order_store
  use_cases :orders_create, :send_notification

  def call(params = {})
    result = orders_create.call(params)
    return result unless result.success?
    send_notification.call(order_id: result.value[:order].id)
    result
  end
end
```

### 2.4 Subscribing to events

A use case can run in response to a published event (e.g. after another use case finishes, or a custom event).

- **`subscribe :posts_create`** — When the event `:posts_create` is published, this use case’s `call(payload)` is invoked with the event payload.
- **`subscribe :post_created, :post_updated`** — Subscribes to multiple events.
- **`subscribe :all`** — Subscribes to every published event. The payload includes `:event` with the event name.

The use case does not need a controller or route. Subscriptions are wired when you call `RageArch::UseCase::Base.wire_subscriptions_to(publisher)` in the initializer (see Event publisher).

Example (subscriber):

```ruby
class Notifications::SendPostCreatedEmail < RageArch::UseCase::Base
  use_case_symbol :send_post_created_email
  deps :mailer
  subscribe :posts_create

  def call(payload = {})
    return success unless payload[:success]
    mailer.send_post_created(payload[:value][:post])
    success
  end
end
```

### 2.5 Auto-publish and opt-out

By default, when a use case’s `call` finishes, the framework publishes an event whose name is the use case symbol, with payload `use_case`, `params`, `success`, `value`, `errors`. This only happens if:

- `config.rage_arch.auto_publish_events` is not `false`, and
- the use case did not call **`skip_auto_publish`**, and
- `:event_publisher` is registered in the container.

- **`skip_auto_publish`** — This use case will not trigger an automatic event when it finishes. Useful for use cases that only react (e.g. logger) to avoid redundant events.

### 2.6 AR deps (ar_dep)

For a dep that is “Active Record for a model”, you can declare:

```ruby
ar_dep :user_store, User
```

If `:user_store` is not registered in the container, the gem uses `RageArch::Deps::ActiveRecord.for(User)`. In the initializer you can still override with `RageArch.register_ar(:user_store, User)` or `RageArch.register(:user_store, CustomUserStore.new)`.

### 2.7 Summary of use case class methods

| Method | Purpose |
|--------|--------|
| `use_case_symbol :sym` | Register this use case under `:sym`. |
| `deps :a, :b` | Inject these deps (by symbol) into the instance. |
| `ar_dep :sym, Model` | Dep that defaults to AR for `Model` if not registered. |
| `use_cases :uc1, :uc2` | Allow calling these use cases via `uc1.call(params)` etc. |
| `subscribe :ev1, :ev2` | Run this use case when these events are published. |
| `subscribe :all` | Run this use case on every published event (payload has `:event`). |
| `skip_auto_publish` | Do not publish an event when this use case finishes. |

---

## 3. Dependencies (deps)

### 3.1 Container

- **`RageArch.register(:symbol, implementation)`** — Registers an implementation for a symbol. `implementation` can be an instance, a class (instantiated when resolved), or a block (called when resolved).
- **`RageArch.register_ar(:symbol, Model)`** — Registers a dep that uses `RageArch::Deps::ActiveRecord.for(Model)` (build, find, save, update, destroy, list).
- **`RageArch.resolve(:symbol)`** — Resolves the implementation for the symbol (raises if not registered).
- **`RageArch.registered?(:symbol)`** — Returns whether the symbol is registered.

Use cases declare deps with `deps :a, :b`. When the use case is built, the gem resolves each symbol from the container (or uses the AR default for `ar_dep`) and passes them to the constructor.

### 3.2 Dep placement and naming

Deps are typically implemented in `app/deps/`, optionally under a module (e.g. `app/deps/orders/order_store.rb` → `Orders::OrderStore`). The generators `rage_arch:dep` and `rage_arch:ar_dep` infer the folder from the symbol (e.g. `post_store` → `posts/`).

---

## 4. Event publisher

### 4.1 Roles

- **Publishing** — Sending an event with a name and payload. Done automatically after each use case run (if enabled) or manually via `event_publisher.publish(:event_name, **payload)`.
- **Subscribing** — Registering a handler for an event. Handlers can be blocks, callables, or use case symbols. Use cases declare subscriptions with `subscribe :event_name` (or `:all`); wiring is done with `wire_subscriptions_to(publisher)`.

### 4.2 Setup

In `config/initializers/rage_arch.rb` (inside `Rails.application.config.after_initialize`):

```ruby
publisher = RageArch::EventPublisher.new
RageArch::UseCase::Base.wire_subscriptions_to(publisher)
RageArch.register(:event_publisher, publisher)
```

`wire_subscriptions_to` iterates over all registered use case classes and, for each class that declared `subscribe`, registers that use case (by symbol) as a handler for the given event(s).

### 4.3 Auto-publish payload

When a use case finishes and auto-publish is on, the published event name is the use case symbol. The payload includes:

- `use_case` — the use case symbol
- `params` — params passed to `call`
- `success` — boolean
- `value` — `result.value`
- `errors` — `result.errors`

Subscriber use cases receive this hash in `call(payload)`.

### 4.4 Manual publish

In a use case that has `deps :event_publisher`:

```ruby
event_publisher.publish(:post_created, post_id: post.id, user_id: post.user_id)
```

Handlers subscribed to `:post_created` (and `:all`) run with that payload. For `:all`, the payload given to the handler also includes `:event` (e.g. `:post_created`).

### 4.5 Configuration

- **`config.rage_arch.auto_publish_events`** — Default is `true`. Set to `false` to disable automatic publishing when use cases finish. You can still register `:event_publisher` and call `event_publisher.publish(...)` manually where needed.

### 4.6 Re-entrancy

The publisher limits re-entrancy (nested publish) to avoid infinite loops. If a handler publishes an event and that leads to too deep a stack, an error is raised.

---

## 5. Controller

Include `RageArch::Controller` in `ApplicationController` (done by `rails g rage_arch:install`).

### 5.1 Methods

- **`run(symbol, params = {}, success:, failure:)`** — Builds the use case with `symbol`, calls it with `params`, then invokes the `success` or `failure` proc with the `Result`. Use for the common “success → redirect/render, failure → errors” flow.
- **`run_result(symbol, params = {})`** — Builds the use case, runs it, and returns the `Result`. Use when you need to handle success/failure yourself (e.g. different status codes, or to get `value` inside a failure block for form data).
- **`flash_errors(result)`** — Sets `flash.now[:alert]` to `result.errors.join(", ")`.

All three are private.

### 5.2 Example

```ruby
def create
  run :create_order, order_params,
    success: ->(r) { redirect_to order_path(r.value[:order].id), notice: "Created." },
    failure: ->(r) { flash_errors(r); render :new, status: :unprocessable_entity }
end
```

---

## 6. Result object

- **`RageArch::Result.success(value)`** — Builds a successful result with `value`.
- **`RageArch::Result.failure(errors)`** — Builds a failed result with `errors` (array or hash).
- **`result.success?`** / **`result.failure?`**
- **`result.value`** / **`result.errors`**

Use cases typically use the helpers `success(value)` and `failure(errors)` (which delegate to these).

---

## 7. Generators

| Generator | Purpose |
|-----------|--------|
| `rails g rage_arch:install` | Creates initializer (with event publisher wired), `app/use_cases`, `app/deps`, and adds `RageArch::Controller` to `ApplicationController`. |
| `rails g rage_arch:scaffold ModelName attr:type ...` | Full CRUD: model + migration, use cases, dep, **Rails scaffold_controller** (views + helper + specs), RageArch controller (overwrites), routes; injects `register_ar`. Options: `--skip-model`, `--api` (JSON only, no views). |
| `rails g rage_arch:use_case Name` | Creates a use case file (e.g. `app/use_cases/name.rb` or `app/use_cases/module/name.rb`). |
| `rails g rage_arch:dep symbol [ClassName]` | Creates a dep class with methods inferred from use case calls; folder inferred from symbol. If the file already exists (e.g. custom class name), only adds stub methods that are missing. |
| `rails g rage_arch:ar_dep symbol Model` | Creates an AR-backed dep (build, find, save, update, destroy, list) plus any extra methods from use cases. |
| `rails g rage_arch:dep_switch symbol [ClassName]` | Lists implementations for the dep and updates the initializer to register the chosen one. |

---

## 8. Configuration

- **`config.rage_arch`** — Set in the Railtie. Options:
  - **`auto_publish_events`** — `true` (default) or `false`. When `true`, each use case run publishes an event after completion (if the use case does not call `skip_auto_publish` and `:event_publisher` is registered).
  - **`verify_deps`** — `true` (default) or `false`. When `true`, the framework runs `RageArch.verify_deps!` automatically after all initializers have loaded, before the app handles any request. Set to `false` to skip the check (e.g. in a legacy app where you are adopting RageArch incrementally).

---

## 9. Boot verification (`verify_deps!`)

`RageArch.verify_deps!` is called automatically at boot (unless `config.rage_arch.verify_deps = false`). It raises a `RuntimeError` listing all problems found, so you catch wiring issues immediately instead of at runtime.

What it checks:

- Every dep declared with `deps :symbol` in a registered use case is registered in the container (unless the dep is declared with `ar_dep`, which has an AR fallback).
- For registered deps, every method the use cases call on that dep is actually implemented by the registered object (static analysis via `DepScanner`).
- Every use case symbol declared with `use_cases :symbol` is registered in the use case registry.

```ruby
# Call at the end of your after_initialize block, after all deps are registered:
RageArch.verify_deps! unless ENV["SECRET_KEY_BASE_DUMMY"].present?
# => true, or raises RuntimeError with a list of missing deps/methods
```

**Important**: do NOT rely on the Railtie's automatic call — it runs before the app's `after_initialize` block (where deps are typically registered), so deps would not be visible yet. Instead, call `verify_deps!` manually at the end of `config/initializers/rage_arch.rb`, after all `RageArch.register` calls (as the generated template does).

To disable entirely:

```ruby
# config/application.rb
config.rage_arch.verify_deps = false
```

---

## 10. Instrumentation

Every use case `call` is wrapped in an `ActiveSupport::Notifications` instrument (when Rails is loaded):

- **Event name**: `"rage_arch.use_case.run"`
- **Payload** (available in the `finish` callback): `symbol`, `params`, `success` (boolean), `errors` (when failure), `result` (the `RageArch::Result` object).

Example subscriber in an initializer:

```ruby
ActiveSupport::Notifications.subscribe("rage_arch.use_case.run") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[UseCase] #{event.payload[:symbol]} (#{event.duration.round}ms) success=#{event.payload[:success]}"
end
```

---

## 11. Testing

Optional RSpec matchers and a fake event publisher improve test readability.

### 11.1 RSpec matchers

In `spec/spec_helper.rb` or `spec/rails_helper.rb` add:

```ruby
require "rage_arch/rspec_matchers"
```

- **`expect(result).to succeed_with(key: value, ...)`** — Asserts `result.success?` and that `result.value` (when a Hash) includes the given key/value pairs. Supports composable matchers (e.g. `a_kind_of(Post)`). For a single non-hash value: `expect(result).to succeed_with(42)`.
- **`expect(result).to fail_with_errors(errors)`** — Asserts `result.failure?` and that `result.errors` matches the given value (array or RSpec matcher, e.g. `include("not found")`).

### 11.2 Fake event publisher

To assert that events were published without running real handlers, use `RageArch::FakeEventPublisher`:

```ruby
require "rage_arch/fake_event_publisher"

# In your test (e.g. in a before block)
publisher = RageArch::FakeEventPublisher.new
RageArch.register(:event_publisher, publisher)
# ... run use case ...
expect(publisher.published).to include(
  hash_including(event: :post_created, payload: hash_including(post_id: kind_of(Integer)))
)
publisher.clear   # optional: reset between examples
```

`FakeEventPublisher#subscribe` is a no-op; only `#publish` is recorded.

### 11.3 General approach

- **Use cases** — Register fake deps: `RageArch.register(:order_store, fake_store)` then `RageArch::UseCase::Base.build(:create_order).call(params)`. Assert with `succeed_with` / `fail_with_errors`.
- **Subscribers** — Use `FakeEventPublisher` to record events, or use the real publisher and assert side effects.
- **Controllers** — Use `run_result` in tests to get the `Result` and assert on it with the matchers above.
