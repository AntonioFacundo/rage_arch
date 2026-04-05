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
  # symbol :audit_log_order_created is inferred automatically
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

For `_store` or `_repo` deps with no file in `app/deps/`, rage_arch auto-resolves the AR model (e.g. `:post_store` or `:post_repo` → `Post`).

AR adapter methods: `build(attrs)`, `find(id)`, `save(record)`, `update(record, attrs)`, `destroy(record)`, `list(filters: {})`.

## Generators

```bash
rails g rage_arch:install                          # initializer, dirs, controller mixin
rails g rage_arch:scaffold Post title:string       # full CRUD (model, use cases, dep, controller, views, routes)
rails g rage_arch:scaffold Post title:string --api # JSON only
rails g rage_arch:scaffold Post --skip-model       # skip model/migration
rails g rage_arch:resource Post title:string       # like scaffold but no views (API-style controller)
rails g rage_arch:controller Pages home about      # thin controller + use case per action + routes
rails g rage_arch:use_case CreateOrder             # single use case
rails g rage_arch:use_case orders/create           # namespaced: Orders::Create
rails g rage_arch:dep post_store                   # dep with methods from use case analysis
rails g rage_arch:dep_switch post_store            # swap dep implementation
rails g rage_arch:mailer PostMailer post_created   # Rails mailer + dep wrapper (auto-registered)
rails g rage_arch:job ProcessOrder orders_create   # ActiveJob that runs a use case by symbol
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

## Undo / cascade rollback

Define `def undo(value)` on any use case. If `call` returns failure, `undo` runs automatically. With `use_cases`, children are undone in reverse order:

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

## Test isolation

`RageArch::RSpecHelpers` wraps each example in `RageArch.isolate` — dep registrations never bleed between tests:

```ruby
# spec/rails_helper.rb
require "rage_arch/rspec_helpers"
require "rage_arch/rspec_matchers"
require "rage_arch/fake_event_publisher"

RSpec.configure do |config|
  config.include RageArch::RSpecHelpers  # auto-isolates each test
end
```

Manual isolation (without the helper):

```ruby
RageArch.isolate do
  RageArch.register(:payment_gateway, FakeGateway.new)
  # registrations inside are scoped; originals restored on exit
end
```

## Async subscribers

Subscribers run via `RageArch::SubscriberJob` (ActiveJob) by default. To run synchronously:

```ruby
subscribe :orders_create, async: false           # per subscriber
config.rage_arch.async_subscribers = false        # global (recommended for test environments)
```

## Project structure

```
app/
├── controllers/         # thin controllers with include RageArch::Controller
├── deps/                # dependency implementations (auto-registered)
│   └── orders/
│       └── order_store.rb
├── models/              # AR models — schema + associations only
└── use_cases/           # business logic (auto-registered)
    └── orders/
        ├── create.rb
        ├── update.rb
        └── destroy.rb
config/
└── initializers/
    └── rage_arch.rb     # event publisher wiring, manual registrations, verify_deps!
spec/
└── use_cases/           # test each use case with fake deps
```

## Key internal classes

| File | Class | Purpose |
|------|-------|---------|
| `lib/rage_arch/result.rb` | `RageArch::Result` | Typed success/failure result object |
| `lib/rage_arch/container.rb` | `RageArch::Container` | Global dependency registry |
| `lib/rage_arch/use_case.rb` | `RageArch::UseCase::Base` | Base class for all use cases |
| `lib/rage_arch/controller.rb` | `RageArch::Controller` | Mixin for thin Rails controllers |
| `lib/rage_arch/event_publisher.rb` | `RageArch::EventPublisher` | Domain event pub/sub |
| `lib/rage_arch/auto_registry.rb` | `RageArch::AutoRegistry` | Auto-registers use cases and deps at boot |
| `lib/rage_arch/dep_scanner.rb` | `RageArch::DepScanner` | Static analysis of dep method calls |
| `lib/rage_arch/subscriber_job.rb` | `RageArch::SubscriberJob` | ActiveJob for async subscriber dispatch |
| `lib/rage_arch/railtie.rb` | `RageArch::Railtie` | Rails integration (autoload, config, verify) |
| `lib/rage_arch/deps/active_record.rb` | `RageArch::Deps::ActiveRecord` | Generic AR adapter (build, find, save, etc.) |
| `lib/rage_arch/rspec_helpers.rb` | `RageArch::RSpecHelpers` | Test isolation via `isolate` |
| `lib/rage_arch/rspec_matchers.rb` | — | `succeed_with` and `fail_with_errors` matchers |
| `lib/rage_arch/fake_event_publisher.rb` | `RageArch::FakeEventPublisher` | Records events for test assertions |

## Conventions

- Use case files: `app/use_cases/` (auto-loaded and auto-registered by railtie)
- Dep files: `app/deps/<domain>/` (auto-registered by convention, symbol = class name without namespace)
- Symbol naming: `orders_create`, `posts_update` (domain_action) — inferred from class name
- `_store` or `_repo` deps with no file: auto-resolved to AR model (e.g. `:post_store` or `:post_repo` → `Post`)
- Registration: only needed for external adapters (Stripe, etc.) in `config/initializers/rage_arch.rb`
- Use cases return Result, never raise for business errors
- Models: schema + associations only, no callbacks for side effects
- Controllers never contain business logic — only `run`/`run_result` calls
- Deps have no base class — any Ruby object that responds to the expected methods works
- One use case per business action (create, update, refund, etc.)

## Common patterns

### Use case with validation
```ruby
class Posts::Create < RageArch::UseCase::Base
  deps :post_repo

  def call(params = {})
    return failure(["Title is required"]) if params[:title].to_s.strip.empty?
    post = post_repo.build(params)
    return failure(post.errors.full_messages) unless post_repo.save(post)
    success(post: post)
  end
end
```

### Orchestrating multiple use cases with rollback
```ruby
class Bookings::Create < RageArch::UseCase::Base
  use_cases :payments_charge, :slots_reserve

  def call(params = {})
    charge = payments_charge.call(amount: params[:amount])
    return charge unless charge.success?

    reserve = slots_reserve.call(slot_id: params[:slot_id])
    return failure(reserve.errors) unless reserve.success?
    # If reserve fails, payments_charge.undo runs automatically

    success(booking: params)
  end
end
```

### API controller
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

## Using this file with AI agents

If you use Claude Code or another AI coding agent, you can create a **custom skill** (slash command) that loads this context automatically when working on a RageArch project. This avoids having to point the agent to this file manually each time.

### Claude Code skill setup

Create a file at `.claude/commands/rage.md` in your project (or `~/.claude/commands/rage.md` for global access):

```markdown
---
description: Load RageArch gem context for AI-assisted development
---

Read the file IA.md in the project root for the full RageArch API, conventions, and architecture. Use it as context for all code generation, reviews, and refactoring in this project.

Key rules:
- Always use RageArch conventions (use cases, deps, Result, thin controllers)
- Use generators when creating new components (`rails g rage_arch:...`)
- Never put business logic in controllers or models
- Use cases return Result, never raise for business errors
- Prefer convention-based auto-registration over manual `RageArch.register`

The user's request is: $ARGUMENTS
```

Then invoke it with `/rage <your request>` — e.g. `/rage create a use case for refunding an order`.
