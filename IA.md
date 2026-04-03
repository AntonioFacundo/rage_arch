# RageArch — AI context

RageArch is a Clean Architecture layer for Rails. Business logic lives in use cases, dependencies are injected by symbol, and controllers stay thin.

## Architecture

```
Controller → run(:symbol, params) → UseCase → deps (from Container) → Result (success/failure)
                                         ↓
                                   EventPublisher → subscriber use cases
```

## Result

```ruby
RageArch::Result.success(value)   # value = any object, commonly a Hash
RageArch::Result.failure(errors)  # errors = Array or Hash
result.success? / result.failure?
result.value    / result.errors
```

## Container

```ruby
RageArch.register(:symbol, instance_or_block)
RageArch.register_ar(:symbol, Model)  # AR adapter: build, find, save, update, destroy, list
RageArch.resolve(:symbol)
RageArch.registered?(:symbol)
```

## Use case

```ruby
class Orders::Create < RageArch::UseCase::Base
  deps :order_store, :notifications       # injected from container, available as private methods
  use_cases :payments_charge              # can call other use cases
  subscribe :some_event                   # react to events (no controller needed)
  skip_auto_publish                       # opt out of auto event on finish

  def call(params = {})
    order = order_store.build(params)
    return failure(order.errors) unless order_store.save(order)
    success(order: order)
  end
end
```

Build/run: `RageArch::UseCase::Base.build(:orders_create).call(params)` → returns `Result`.

## Controller

`include RageArch::Controller` in ApplicationController (done by install generator). All methods are private.

- `run(symbol, params, success:, failure:)` — builds use case, runs it, calls matching proc with Result
- `run_result(symbol, params)` — builds use case, runs it, returns Result directly
- `flash_errors(result)` — sets `flash.now[:alert]` to `result.errors.join(", ")`

```ruby
# HTML
run :orders_create, order_params,
  success: ->(r) { redirect_to order_path(r.value[:order].id) },
  failure: ->(r) { flash_errors(r); render :new, status: :unprocessable_entity }

# JSON
run :orders_create, order_params,
  success: ->(r) { render json: r.value[:order], status: :created },
  failure: ->(r) { render json: { errors: r.errors }, status: :unprocessable_entity }

# Direct
result = run_result(:orders_create, order_params)
```

## Events

Auto-publish on use case finish (event name = use case symbol). Payload hash received by subscribers:

```ruby
{
  use_case: :orders_create,        # source use case symbol
  params:   { title: "..." },      # params passed to call
  success:  true,                  # boolean
  value:    { order: #<Order> },   # result.value (nil on failure)
  errors:   nil                    # result.errors (nil on success)
}
# subscribe :all adds :event key with the event name
```

```ruby
# Setup (initializer, already done by install generator)
publisher = RageArch::EventPublisher.new
RageArch::UseCase::Base.wire_subscriptions_to(publisher)
RageArch.register(:event_publisher, publisher)

# Subscriber use case — receives payload hash in call()
class Audit::LogOrderCreated < RageArch::UseCase::Base
  use_case_symbol :log_order_created
  deps :logger
  subscribe :orders_create

  def call(payload = {})
    return success unless payload[:success]
    logger.info("Order created: #{payload[:value][:order].id}")
    success
  end
end

# Subscribe to multiple or all
subscribe :order_created, :order_updated  # multiple
subscribe :all                            # everything (payload has :event key)

# Manual publish inside a use case
deps :event_publisher
event_publisher.publish(:custom_event, key: value)
```

## Deps

A dep is any Ruby object. No base class. Files in `app/deps/` are auto-registered by convention at boot.

Files go in `app/deps/` under domain folders: `app/deps/orders/order_store.rb` → `Orders::OrderStore` → registered as `:order_store`.

For `_store` deps with no file in `app/deps/`, rage_arch auto-resolves the AR model (e.g. `:post_store` → `Post`).

AR adapter methods: `build(attrs)`, `find(id)`, `save(record)`, `update(record, attrs)`, `destroy(record)`, `list(filters: {})`.

## Generators

```bash
rails g rage_arch:install                          # initializer, dirs, controller mixin
rails g rage_arch:scaffold Post title:string       # full CRUD (model, use cases, dep, controller, views, routes)
rails g rage_arch:scaffold Post title:string --api # JSON only
rails g rage_arch:scaffold Post --skip-model       # skip model/migration
rails g rage_arch:use_case CreateOrder             # single use case
rails g rage_arch:use_case orders/create           # namespaced: Orders::Create
rails g rage_arch:dep post_store                   # dep with methods from use case analysis
rails g rage_arch:dep_switch post_store            # swap dep implementation
```

### Scaffold output

`rails g rage_arch:scaffold Post title:string body:text` generates:

- `app/models/post.rb` + migration
- `app/use_cases/posts/` — `index.rb`, `show.rb`, `create.rb`, `update.rb`, `destroy.rb`
- `app/deps/posts/post_repo.rb` (AR adapter, auto-registered by convention)
- `app/controllers/posts_controller.rb` (RageArch controller with `run`)
- Views: index, show, new, edit, _form (same as Rails scaffold)
- Routes: `resources :posts`

### Dep generator

`rails g rage_arch:dep post_store` scans `app/use_cases/**/*.rb` for all method calls on `:post_store` and generates a class with stub methods for each one. If the file already exists, only missing methods are added — existing code is not overwritten. Folder is inferred from symbol: `post_store` → `app/deps/posts/post_store.rb`.

### Install generator output

`rails g rage_arch:install` creates this initializer:

```ruby
# config/initializers/rage_arch.rb
Rails.application.config.after_initialize do
  # Register deps here:
  # RageArch.register(:order_store, Orders::OrderStore.new)

  publisher = RageArch::EventPublisher.new
  RageArch::UseCase::Base.wire_subscriptions_to(publisher)
  RageArch.register(:event_publisher, publisher)

  RageArch.verify_deps! unless ENV["SECRET_KEY_BASE_DUMMY"].present?
end
```

## Testing

```ruby
require "rage_arch/rspec_matchers"
require "rage_arch/fake_event_publisher"

# Register fakes
RageArch.register(:order_store, fake_store)
RageArch.register(:event_publisher, RageArch::FakeEventPublisher.new)

# Run
result = RageArch::UseCase::Base.build(:orders_create).call(params)

# Assert
expect(result).to succeed_with(order: a_kind_of(Order))
expect(result).to fail_with_errors(["Not found"])

# Events
expect(publisher.published).to include(hash_including(event: :orders_create))
publisher.clear
```

## Config

```ruby
config.rage_arch.auto_publish_events = false  # default: true
config.rage_arch.verify_deps = false          # default: true (checks wiring at boot)
```

## Boot verification

`RageArch.verify_deps!` runs at boot. Checks: all deps registered, all methods implemented, all use_cases symbols exist. Call manually at end of `after_initialize` block.

## Instrumentation

Event `"rage_arch.use_case.run"` via ActiveSupport::Notifications. Payload: `symbol`, `params`, `success`, `errors`, `result`.

## Conventions

- Use case files: `app/use_cases/` (auto-loaded and auto-registered by railtie)
- Dep files: `app/deps/<domain>/` (auto-registered by convention, symbol = class name without namespace)
- Symbol naming: `orders_create`, `posts_update` (domain_action) — inferred from class name
- `_store` deps with no file: auto-resolved to AR model (e.g. `:post_store` → `Post`)
- Registration: only needed for external adapters (Stripe, etc.) in `config/initializers/rage_arch.rb`
- Use cases return Result, never raise for business errors
- Models: schema + associations only, no callbacks for side effects
