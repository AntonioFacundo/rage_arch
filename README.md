# RageArch

**Clean Architecture Light for Rails.** Business logic in testable use cases, thin controllers, and models free of callbacks.

## Core concepts

- **Controllers** only orchestrate — no business logic
- **Models** stay clean — no business callbacks
- **Use cases** hold all logic, with injected dependencies and typed results

## Setup

```bash
bundle install
rails g rage_arch:install
```

Creates `config/initializers/rage_arch.rb`, `app/use_cases/`, `app/deps/`, and injects `include RageArch::Controller` into `ApplicationController`.

---

## Components

### `RageArch::Result` — typed result object

```ruby
result = RageArch::Result.success(order)
result.success?  # => true
result.value     # => order

result = RageArch::Result.failure(["Validation error"])
result.failure?  # => true
result.errors    # => ["Validation error"]
```

---

### `RageArch::UseCase::Base` — use cases

```ruby
class CreateOrder < RageArch::UseCase::Base
  use_case_symbol :create_order
  deps :order_store, :notifications  # injected by symbol

  def call(params = {})
    order = order_store.build(params)
    return failure(order.errors) unless order_store.save(order)
    notifications.notify(:order_created, order)
    success(order)
  end
end
```

Build and run manually:

```ruby
use_case = RageArch::UseCase::Base.build(:create_order)
result = use_case.call(reference: "REF-1", total_cents: 1000)
```

---

### `RageArch::Container` — dependency registration

```ruby
RageArch.register(:order_store, MyApp::Deps::OrderStore.new)
RageArch.register_ar(:user_store, User)  # automatic ActiveRecord wrapper
RageArch.resolve(:order_store)
```

---

### `RageArch::Controller` — thin controller mixin

```ruby
def create
  run :users_register, register_params,
    success: ->(r) { session[:user_id] = r.value[:user].id; redirect_to root_path, notice: "Created." },
    failure: ->(r) { flash_errors(r); render :new, status: :unprocessable_entity }
end
```

- `run(symbol, params, success:, failure:)` — runs the use case and calls the matching block
- `run_result(symbol, params)` — runs and returns the `Result` directly
- `flash_errors(result)` — sets `flash.now[:alert]` from `result.errors`

---

### `RageArch::EventPublisher` — domain events

Every use case automatically publishes an event when it finishes. Other use cases subscribe to react:

```ruby
class Notifications::SendPostCreatedEmail < RageArch::UseCase::Base
  use_case_symbol :send_post_created_email
  deps :mailer
  subscribe :posts_create  # runs when :posts_create event is published

  def call(payload = {})
    return success unless payload[:success]
    mailer.send_post_created(payload[:value][:post])
    success
  end
end
```

Subscribe to multiple events or everything:

```ruby
subscribe :post_created, :post_updated
subscribe :all  # payload includes :event with the event name
```

Opt out of auto-publish for a specific use case:

```ruby
skip_auto_publish
```

---

### Orchestration — use cases calling use cases

```ruby
class CreateOrderWithNotification < RageArch::UseCase::Base
  use_case_symbol :create_order_with_notification
  deps :order_store
  use_cases :orders_create, :notifications_send

  def call(params = {})
    result = orders_create.call(params)
    return result unless result.success?
    notifications_send.call(order_id: result.value[:order].id, type: :order_created)
    result
  end
end
```

---

## Generators

| Command | What it does |
|---|---|
| `rails g rage_arch:install` | Initial setup (initializer, directories, controller mixin) |
| `rails g rage_arch:scaffold Post title:string` | Full CRUD: model, use cases, dep, controller, views, routes |
| `rails g rage_arch:scaffold Post title:string --api` | Same but API-only (JSON responses) |
| `rails g rage_arch:scaffold Post title:string --skip-model` | Skip model/migration if it already exists |
| `rails g rage_arch:use_case CreateOrder` | Generates a base use case file |
| `rails g rage_arch:dep post_store` | Generates a dep class by scanning method calls in use cases |
| `rails g rage_arch:ar_dep post_store Post` | Generates a dep that wraps an ActiveRecord model |

---

## Testing

```ruby
# spec/rails_helper.rb
require "rage_arch/rspec_matchers"
require "rage_arch/fake_event_publisher"
```

**Result matchers:**

```ruby
expect(result).to succeed_with(post: a_kind_of(Post))
expect(result).to fail_with_errors(["Not found"])
```

**Fake event publisher:**

```ruby
publisher = RageArch::FakeEventPublisher.new
RageArch.register(:event_publisher, publisher)
# ... run use case ...
expect(publisher.published).to include(hash_including(event: :post_created))
publisher.clear
```

---

## Boot verification

At boot, `RageArch.verify_deps!` runs automatically and raises if any dep, method, or use case reference is unregistered. Disable with `config.rage_arch.verify_deps = false`.

---

## Instrumentation

Every use case emits `"rage_arch.use_case.run"` via `ActiveSupport::Notifications` with payload `symbol`, `params`, `success`, `errors`, `result`.

---

## Documentation

- [`doc/REFERENCE.md`](doc/REFERENCE.md) — Full API reference with all options and examples
- [`doc/DOCUMENTATION.md`](doc/DOCUMENTATION.md) — Detailed behaviour (use cases, deps, events, config)
- [`doc/GETTING_STARTED.md`](doc/GETTING_STARTED.md) — Getting started guide with common tasks

## License

MIT
