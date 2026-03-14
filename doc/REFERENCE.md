# RageArch

Clean Architecture Light for Rails: use cases with dependency injection, domain events, orchestration, and Result objects. Keeps controllers thin, models free of callbacks, and business logic in testable use cases.

## Installation

Add to your `Gemfile`:

```ruby
gem "rage_arch"
```

Then:

```bash
bundle install
rails g rage_arch:install
```

This creates `config/initializers/rage_arch.rb`, the `app/use_cases` and `app/deps` directories, and adds `include RageArch::Controller` to `ApplicationController`. The initializer includes the event publisher (create, wire subscriptions, register) so you can use `subscribe` in use cases right away. Existing files are skipped.

### Scaffold (full CRUD in one command)

Generate a resource with model, migration, use cases, dep, controller, and routes in one shot — same speed as Rails scaffold, with Clean Architecture:

```bash
rails g rage_arch:scaffold Post title:string body:text
rails g rage_arch:scaffold Product name:string price:decimal --skip-model   # skip model/migration if already exists
rails g rage_arch:scaffold Item name:string --api   # API only: controller responds with JSON, no views
```

Creates: model + migration, use cases, dep, controller (RageArch), **views from Rails' scaffold_controller** (index, show, new, edit, _form), routes, and injects `register_ar`. Run migrations and you have a full CRUD with HTML. Same views as `rails g scaffold`; only the controller is replaced with the Rage one.

## Usage

### Result

```ruby
result = RageArch::Result.success(order)
result.success? # => true
result.value    # => order

result = RageArch::Result.failure(["Validation error"])
result.failure? # => true
result.errors   # => ["Validation error"]
```

### Container and registering deps

```ruby
# In config/initializers/rage_arch.rb or your composition root
RageArch.register(:order_store, MyApp::Deps::OrderStore.new)
RageArch.register(:notifications, MyApp::Deps::EmailNotifications.new)

# For a dep that is just Active Record for a model, use the readable form:
RageArch.register_ar(:user_store, User)   # instead of RageArch.register(:user_store, RageArch::Deps::ActiveRecord.for(User))

# Resolve
RageArch.resolve(:order_store)
```

### Use case

```ruby
class CreateOrder < RageArch::UseCase::Base
  use_case_symbol :create_order
  deps :order_store, :notifications

  def call(params = {})
    order = order_store.build(params)
    return failure(order.errors) unless order_store.save(order)
    notifications.notify(:order_created, order)
    success(order)
  end
end
```

### Calling other use cases (orchestration)

Use cases in the same layer can call other use cases by symbol. Declare them with `use_cases` and invoke with `.call(params)`:

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

Each declared symbol (e.g. `orders_create`) is a runner that responds to `.call(*args, **kwargs)` and returns the other use case's `Result`.

### Event publisher (domain events)

**By default**, every time a use case runs, the framework publishes an event (the use case symbol) with payload `use_case`, `params`, `success`, `value`, `errors`. You don't need to add `event_publisher.publish` in every use case. Reaction logic lives in use cases that **subscribe** to events.

**Setup** in `config/initializers/rage_arch.rb`:

```ruby
publisher = RageArch::EventPublisher.new
RageArch::UseCase::Base.wire_subscriptions_to(publisher)  # subscriptions declared in use cases
RageArch.register(:event_publisher, publisher)
```

**In a use case that reacts** (just declare which event to subscribe to):

```ruby
# app/use_cases/notifications/send_post_created_email.rb
class Notifications::SendPostCreatedEmail < RageArch::UseCase::Base
  use_case_symbol :send_post_created_email
  deps :mailer
  subscribe :posts_create   # when :posts_create event is published, this use case runs

  def call(payload = {})
    return success unless payload[:success]
    mailer.send_post_created(payload[:value][:post])
    success
  end
end
```

**Multiple events or `:all`** (e.g. logger that reacts to everything):

```ruby
subscribe :post_created, :post_updated
# or
subscribe :all   # payload includes :event with the event name
```

**Opt-out of auto-publish** for a use case (e.g. the one that does logging):

```ruby
skip_auto_publish
```

**Global config** (optional):

- `config.rage.auto_publish_events = false` — don't publish when each use case finishes; only publish manually where you use `deps :event_publisher` and `event_publisher.publish(...)`.
- Default is `true`: all use cases publish when they finish (if `:event_publisher` is registered).
- `config.rage.verify_deps = false` — skip boot verification. Default is `true`: `RageArch.verify_deps!` runs after all initializers load and raises if any dep, method, or use case reference is unregistered.

**Manual publish** in the middle of a flow (extra event in addition to the automatic one):

```ruby
deps :post_store, :event_publisher
def call(params = {})
  post = post_store.save(...)
  event_publisher.publish(:post_created, post_id: post.id, user_id: post.user_id)
  success(post: post)
end
```

Handlers for `:all` receive the payload with `:event` indicating which event was published.

### Build and run

```ruby
use_case = RageArch::UseCase::Base.build(:create_order)
result = use_case.call(reference: "REF-1", total_cents: 1000)
```

### Controller (thin controllers)

With `include RageArch::Controller` in your `ApplicationController` (injected by `rails g rage_arch:install`):

- **`run(symbol, params, success:, failure:)`** — runs the use case and calls the success or failure block with the `Result`.
- **`run_result(symbol, params)`** — runs the use case and returns the `Result` (useful inside a failure block to get form data from another use case).
- **`flash_errors(result)`** — sets `flash.now[:alert]` to `result.errors.join(", ")`.

Example in a controller:

```ruby
def create
  run :users_register, register_params,
    success: ->(r) { session[:user_id] = r.value[:user].id; redirect_to root_path, notice: "Created." },
    failure: ->(r) { flash_errors(r); render :new, status: :unprocessable_entity }
end
```

### Generator

```bash
rails g rage_arch:use_case CreateOrder
rails g rage_arch:use_case Orders::CreateOrder  # with module
```

Generates `app/use_cases/create_order.rb` (or `app/use_cases/orders/create_order.rb`) with the base structure.

### Dep generator (from use cases)

Write your use case and call methods on deps without implementing them. Then generate the dep class with the methods the scanner found:

```bash
rails g rage_arch:dep post_store
rails g rage_arch:dep post_store MysqlPostStore   # custom class name
```

The generator scans `app/use_cases/**/*.rb` for `dep(:symbol)` and `deps :a, :b`, then finds all method calls on those deps. The **folder is inferred from the symbol first** so the dep lives with its domain (e.g. `post_store` → `app/deps/posts/`, `like_store` → `app/deps/likes/`). If the symbol has no clear entity, the folder is taken from the use cases that reference it. **If the target file already exists** (e.g. `rails g rage_arch:dep post_store CsvPostStore` and `app/deps/posts/csv_post_store.rb` is already there), the generator only adds stub methods that are missing (detected from use cases but not yet in the class); it does not overwrite the file.

- `:post_store` → dep in `app/deps/posts/post_store.rb` (`Posts::PostStore`) even if only referenced from `app/use_cases/likes/*.rb`
- `:like_store` → dep in `app/deps/likes/like_store.rb` (`Likes::LikeStore`)
- `:email_sender` (no entity in name) → folder from use cases that reference it, e.g. `app/deps/notifications/email_sender.rb` (`Notifications::EmailSender`)

Register with the full constant: `RageArch.register(:like_store, Likes::LikeStore.new)`. Flat files in `app/deps/*.rb` (no subfolder) are still supported by `dep_switch` for backward compatibility.

### AR dep generator (Active Record wrapper)

To add a dep that simply wraps an existing Active Record model (build, find, save, update, destroy, list):

```bash
rails g rage_arch:ar_dep post_store Post
rails g rage_arch:ar_dep user_store User
```

Creates `app/deps/posts/post_store.rb` with a class that delegates to `RageArch::Deps::ActiveRecord.for(Post)`. Register in the initializer: `RageArch.register(:post_store, Posts::PostStore.new)`. Same folder logic as `rage:dep` (inferred from symbol first, then from use case path).

## Testing

Optional RSpec matchers and a fake event publisher make tests more readable.

**In `spec/spec_helper.rb` or `spec/rails_helper.rb`:**

```ruby
require "rage_arch/rspec_matchers"
```

**Result matchers:**

```ruby
result = RageArch::UseCase::Base.build(:create_post).call(title: "Hi")
expect(result).to succeed_with(post: a_kind_of(Post))
expect(result).to succeed_with(post: post)   # when value is a hash with :post key

result = RageArch::Result.failure(["Not found"])
expect(result).to fail_with_errors(["Not found"])
expect(result).to fail_with_errors(include("Not found"))
```

**Fake event publisher** (to assert that events were published without running real handlers):

```ruby
# spec/rails_helper.rb or in a support file
require "rage_arch/fake_event_publisher"

# In your test: swap the real publisher
publisher = RageArch::FakeEventPublisher.new
RageArch.register(:event_publisher, publisher)
# ... run use case ...
expect(publisher.published).to include(hash_including(event: :post_created, payload: hash_including(post_id: kind_of(Integer))))
publisher.clear   # optional: reset between examples
```

## Boot verification

`RageArch.verify_deps!` runs automatically after all initializers load (Railtie). It raises a `RuntimeError` listing every problem found:

- A dep declared with `deps :symbol` that is not registered in the container (unless it uses `ar_dep`, which has an AR fallback).
- A method called on a dep (detected by static analysis) that the registered implementation does not respond to.
- A use case symbol declared with `use_cases :symbol` that is not in the registry.

```ruby
# Disable globally if needed:
config.rage.verify_deps = false
```

## Instrumentation

Every use case `call` emits an `ActiveSupport::Notifications` event `"rage.use_case.run"` with payload: `symbol`, `params`, `success`, `errors`, `result`.

```ruby
ActiveSupport::Notifications.subscribe("rage.use_case.run") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[UseCase] #{event.payload[:symbol]} (#{event.duration.round}ms) success=#{event.payload[:success]}"
end
```

## Documentation

- **[doc/DOCUMENTATION.md](doc/DOCUMENTATION.md)** — Detailed API and behaviour (use cases, deps, events, controller, config, generators).
- **[doc/GETTING_STARTED.md](doc/GETTING_STARTED.md)** — Getting started guide with common tasks (new use case, subscriber, orchestration, swap dep).

## License

MIT
