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

### `RageArch::Container` — dependency registration

```ruby
# Register by instance
RageArch.register(:order_store, MyApp::Deps::OrderStore.new)

# Register with a block (lazy evaluation)
RageArch.register(:mailer) { Mailer.new }

# Register an ActiveRecord model as dep (wraps it automatically)
RageArch.register_ar(:user_store, User)

# Resolve
RageArch.resolve(:order_store)  # => the registered implementation

# Check if registered
RageArch.registered?(:order_store)  # => true
```

**Convention-based auto-registration:** Use cases from `app/use_cases/` and deps from `app/deps/` are auto-registered at boot. The initializer is only needed to override conventions or register external adapters.

**AR model auto-resolution:** If a dep symbol ends in `_store` and no file exists in `app/deps/`, rage_arch looks for an ActiveRecord model automatically:

- `:post_store` resolves to `Post`
- `:appointment_store` resolves to `Appointment`

Explicit `RageArch.register(...)` always takes priority.

---

### Dependencies (Deps)

A dep is any object that a use case needs from the outside world: persistence, mailers, external APIs, caches, etc. No base class required — any Ruby object can be a dep.

#### Writing a dep manually

```ruby
# app/deps/posts/post_store.rb
module Posts
  class PostStore
    def build(attrs = {})
      Post.new(attrs)
    end

    def save(record)
      record.save
    end

    def find(id)
      Post.find_by(id: id)
    end

    def list(filters: {})
      Post.where(filters).to_a
    end
  end
end
```

Auto-registered by convention from `app/deps/` — no manual registration needed.

#### Generating a dep from use case analysis

```bash
rails g rage_arch:dep post_store
```

Scans your use cases for method calls on `:post_store` and generates a class with stub methods for each one. If the file already exists, only missing methods are added.

#### Switching dep implementations

Use `dep_switch` to swap between multiple implementations of the same dep:

```bash
# Interactive — lists all available implementations and prompts you to choose
rails g rage_arch:dep_switch post_store

# Direct — activate a specific implementation
rails g rage_arch:dep_switch post_store PostgresPostStore

# Switch to ActiveRecord adapter
rails g rage_arch:dep_switch post_store ar
```

The generator scans `app/deps/` for files matching the symbol, updates `config/initializers/rage_arch.rb` by commenting out the old registration and adding the new one.

---

### `RageArch::UseCase::Base` — use cases

Use cases declare their dependencies by symbol, receive them via injection, and return a `Result`. The symbol is inferred from the class name by convention:

```ruby
class Orders::Create < RageArch::UseCase::Base
  # symbol :orders_create is inferred automatically
  deps :order_store, :notifications

  def call(params = {})
    order = order_store.build(params)
    return failure(order.errors) unless order_store.save(order)
    notifications.notify(:order_created, order)
    success(order: order)
  end
end
```

Symbol inference: `Orders::Create` becomes `:orders_create`. Explicit `use_case_symbol :my_symbol` still works as override.

Build and run manually:

```ruby
use_case = RageArch::UseCase::Base.build(:orders_create)
result = use_case.call(reference: "REF-1", total_cents: 1000)
```

---

### undo — automatic rollback on failure

Define `def undo(value)` on any use case. If `call` returns `failure(...)`, `undo` is called automatically:

```ruby
class Payments::Charge < RageArch::UseCase::Base
  deps :payment_gateway

  def call(params = {})
    charge = payment_gateway.charge(params[:amount])
    return failure(["Payment failed"]) unless charge.success?
    success(charge_id: charge.id)
  end

  def undo(value)
    payment_gateway.refund(value[:charge_id]) if value
  end
end
```

**Cascade undo with `use_cases`:** When a parent use case orchestrates children via `use_cases` and returns failure, each successfully-completed child has its `undo` called in reverse order:

```ruby
class Bookings::Create < RageArch::UseCase::Base
  use_cases :payments_charge, :slots_reserve, :notifications_send

  def call(params = {})
    charge = payments_charge.call(amount: params[:amount])
    return charge unless charge.success?

    reserve = slots_reserve.call(slot_id: params[:slot_id])
    return failure(reserve.errors) unless reserve.success?
    # If this fails, slots_reserve.undo and payments_charge.undo run automatically

    notifications_send.call(booking: params)
    success(booking: params)
  end
end
```

No DSL, no configuration. Just define `undo` where you need rollback.

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

**API controller example (JSON):**

```ruby
class Api::PostsController < ApplicationController
  def create
    run :posts_create, post_params,
      success: ->(r) { render json: r.value[:post], status: :created },
      failure: ->(r) { render json: { errors: r.errors }, status: :unprocessable_entity }
  end
end
```

---

### `RageArch::EventPublisher` — domain events

Every use case automatically publishes an event when it finishes. Other use cases subscribe to react. **Subscribers run asynchronously via ActiveJob by default:**

```ruby
class Notifications::SendPostCreatedEmail < RageArch::UseCase::Base
  deps :mailer
  subscribe :posts_create  # async by default

  def call(payload = {})
    return success unless payload[:success]
    mailer.send_post_created(payload[:value][:post])
    success
  end
end
```

**Synchronous subscribers** (opt-in):

```ruby
subscribe :posts_create, async: false
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
| `rails g rage_arch:resource Post title:string` | Like scaffold but without views (API-style controller) |
| `rails g rage_arch:controller Pages home about` | Thin controller + use case per action + routes |
| `rails g rage_arch:use_case CreateOrder` | Generates a base use case file |
| `rails g rage_arch:use_case orders/create` | Generates a namespaced use case (`Orders::Create`) |
| `rails g rage_arch:dep post_store` | Generates a dep class by scanning method calls in use cases |
| `rails g rage_arch:dep_switch post_store` | Lists implementations and switches which one is registered |
| `rails g rage_arch:dep_switch post_store PostgresPostStore` | Directly activates a specific implementation |
| `rails g rage_arch:mailer PostMailer post_created` | Rails mailer + dep wrapper (auto-registered) |
| `rails g rage_arch:job ProcessOrder orders_create` | ActiveJob that runs a use case by symbol |

---

## Testing

```ruby
# spec/rails_helper.rb
require "rage_arch/rspec_matchers"
require "rage_arch/rspec_helpers"
require "rage_arch/fake_event_publisher"

RSpec.configure do |config|
  config.include RageArch::RSpecHelpers  # auto-isolates each test
end
```

**Test isolation:** `RageArch::RSpecHelpers` wraps each example in `RageArch.isolate`, so dep registrations never bleed between tests.

**Manual isolation** (without the helper):

```ruby
RageArch.isolate do
  RageArch.register(:payment_gateway, FakeGateway.new)
  # registrations inside are scoped; originals restored on exit
end
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

## Configuration

```ruby
# config/application.rb or config/initializers/rage_arch.rb

# Disable automatic event publishing when use cases finish (default: true)
config.rage_arch.auto_publish_events = false

# Disable boot verification (default: true)
config.rage_arch.verify_deps = false

# Run all subscribers synchronously — useful for test environments (default: true)
config.rage_arch.async_subscribers = false
```

---

## Boot verification

At boot, `RageArch.verify_deps!` runs automatically and raises if it finds wiring problems. It checks:

- Every dep declared with `deps :symbol` is registered in the container (or auto-resolved for `_store` deps)
- Every method called on a dep is implemented by the registered object (via static analysis)
- Every use case declared with `use_cases :symbol` exists in the registry
- Warns if `use_case_symbol` doesn't match the convention-inferred symbol

Example error output:

```
RageArch boot verification failed:
  UseCase :posts_create (Posts::Create) declares dep :post_store — not registered in container and no AR model found
  UseCase :posts_create (Posts::Create) calls dep :post_store#save — Posts::PostStore does not implement #save
  UseCase :posts_notify (Posts::Notify) declares use_cases :email_send — not registered in use case registry
```

Disable with `config.rage_arch.verify_deps = false`.

---

## Instrumentation

Every use case emits `"rage_arch.use_case.run"` via `ActiveSupport::Notifications` with payload `symbol`, `params`, `success`, `errors`, `result`.

```ruby
ActiveSupport::Notifications.subscribe("rage_arch.use_case.run") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[UseCase] #{event.payload[:symbol]} (#{event.duration.round}ms) success=#{event.payload[:success]}"
end
```

---

## Documentation

- [`doc/GETTING_STARTED.md`](doc/GETTING_STARTED.md) — Getting started guide with common tasks
- [`doc/DOCUMENTATION.md`](doc/DOCUMENTATION.md) — Detailed behaviour (use cases, deps, events, config)
- [`doc/REFERENCE.md`](doc/REFERENCE.md) — Quick-lookup API reference (classes, methods, options)

## AI context

If you use an AI coding agent, point it to [`IA.md`](IA.md) for a compact reference of the full gem API, conventions, and architecture.

## License

MIT
