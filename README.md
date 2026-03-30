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

#### `ar_dep` — inline ActiveRecord dep

When a dep is a simple wrapper over an ActiveRecord model, declare it directly in the use case instead of creating a separate class:

```ruby
class Posts::Create < RageArch::UseCase::Base
  use_case_symbol :posts_create
  ar_dep :post_store, Post  # auto-creates an AR adapter if :post_store is not registered

  def call(params = {})
    post = post_store.build(params)
    return failure(post.errors.full_messages) unless post_store.save(post)
    success(post: post)
  end
end
```

If `:post_store` is registered in the container, that implementation is used. Otherwise, `RageArch::Deps::ActiveRecord.for(Post)` is used as fallback.

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

Register it in `config/initializers/rage_arch.rb`:

```ruby
RageArch.register(:post_store, Posts::PostStore.new)
```

#### ActiveRecord dep (generated)

For deps that simply wrap an AR model with standard CRUD, use the generator:

```bash
rails g rage_arch:ar_dep post_store Post
```

This creates `app/deps/posts/post_store.rb` with `build`, `find`, `save`, `update`, `destroy`, and `list` methods backed by `RageArch::Deps::ActiveRecord.for(Post)`.

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
| `rails g rage_arch:use_case orders/create` | Generates a namespaced use case (`Orders::Create`) |
| `rails g rage_arch:dep post_store` | Generates a dep class by scanning method calls in use cases |
| `rails g rage_arch:ar_dep post_store Post` | Generates a dep that wraps an ActiveRecord model |
| `rails g rage_arch:dep_switch post_store` | Lists implementations and switches which one is registered |
| `rails g rage_arch:dep_switch post_store PostgresPostStore` | Directly activates a specific implementation |

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

## Configuration

```ruby
# config/application.rb or config/initializers/rage_arch.rb

# Disable automatic event publishing when use cases finish (default: true)
config.rage_arch.auto_publish_events = false

# Disable boot verification (default: true)
config.rage_arch.verify_deps = false
```

---

## Boot verification

At boot, `RageArch.verify_deps!` runs automatically and raises if it finds wiring problems. It checks:

- Every dep declared with `deps :symbol` is registered in the container
- Every method called on a dep is implemented by the registered object (via static analysis)
- Every use case declared with `use_cases :symbol` exists in the registry

Example error output:

```
RageArch boot verification failed:
  UseCase :posts_create (Posts::Create) declares dep :post_store — not registered in container
  UseCase :posts_create (Posts::Create) calls :post_store#save — Posts::PostStore does not implement #save
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

- [`doc/REFERENCE.md`](doc/REFERENCE.md) — Full API reference with all options and examples
- [`doc/DOCUMENTATION.md`](doc/DOCUMENTATION.md) — Detailed behaviour (use cases, deps, events, config)
- [`doc/GETTING_STARTED.md`](doc/GETTING_STARTED.md) — Getting started guide with common tasks

## License

MIT
