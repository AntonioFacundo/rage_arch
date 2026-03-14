# Getting started with RageArch

Quick reference for the most common tasks. Controllers use `run(symbol, params, success:, failure:)` and `run_result`; use cases declare `deps`, `use_cases`, and `subscribe`; the event publisher is wired once in the initializer.

---

## Setup (once per app)

1. Add the gem and run `bundle install`, then `rails g rage_arch:install` to create `config/initializers/rage_arch.rb`, `app/use_cases`, and `app/deps`, and to add `include RageArch::Controller` to `ApplicationController`.

2. In `config/initializers/rage_arch.rb`, register deps and the event publisher:

```ruby
Rails.application.config.after_initialize do
  RageArch.register(:order_store, MyApp::Deps::OrderStore.new)
  # ... other deps ...

  publisher = RageArch::EventPublisher.new
  RageArch::UseCase::Base.wire_subscriptions_to(publisher)
  RageArch.register(:event_publisher, publisher)
end
```

Use cases are loaded automatically (railtie); you don't need to reference their class in the controller.

---

## 0. Full CRUD in one command (scaffold)

For a new resource (e.g. Post, Product), generate model, use cases, dep, controller, and routes in one shot:

```bash
rails g rage_arch:scaffold Post title:string body:text
```

Then run migrations and you have a full CRUD with HTML. To skip the model and migration (e.g. model already exists): `rails g rage_arch:scaffold Post --skip-model`. For **API only** (JSON, no views): `rails g rage_arch:scaffold Post title:string --api`.

---

## 1. Add a new use case and controller action

You need: **use case** + **controller** + **route** + (optional) **deps** and **event subscribers**.

### Steps

```bash
rails g rage_arch:use_case RefundOrder
# → app/use_cases/refund_order.rb
```

Edit the use case: set `use_case_symbol :refund_order`, add `deps :order_repo, :payment_gateway`, implement `call(params)` with `success(...)` / `failure(...)`.

```bash
rails g rage_arch:dep order_repo
rails g rage_arch:dep payment_gateway
# → app/deps/... with stubs
```

Implement the dep classes and register them in `config/initializers/rage_arch.rb`. Then add the controller and route:

```ruby
# app/controllers/refunds_controller.rb
class RefundsController < ApplicationController
  def create
    run :refund_order, refund_params,
      success: ->(r) { redirect_to order_path(r.value[:order].id), notice: "Refunded." },
      failure: ->(r) { flash_errors(r); render :new, status: :unprocessable_entity }
  end

  private

  def refund_params
    params.permit(:order_id, :reason).to_h.symbolize_keys
  end
end
```

```ruby
# config/routes.rb
post "refunds", to: "refunds#create"
```

---

## 2. Add a use case to an existing controller

Add a **new action** that runs a **new use case**.

```bash
rails g rage_arch:use_case Orders::ShipOrder
# → app/use_cases/orders/ship_order.rb
```

Edit the use case: `use_case_symbol :orders_ship_order` (or a symbol you’ll use in the controller), `deps :order_repo, :shipping_gateway`, implement `call`. Generate and register deps if new. Then add the action:

```ruby
# app/controllers/orders_controller.rb
def ship
  run :orders_ship_order, { id: params[:id] },
    success: ->(r) { redirect_to orders_path, notice: "Shipped." },
    failure: ->(r) { redirect_to orders_path, alert: r.errors.join(", ") }
end
```

```ruby
# config/routes.rb
resources :orders do
  member { post :ship }
end
```

---

## 3. Add a use case that reacts to an event (subscriber)

You want a use case to run when another use case finishes (or when a specific event is published). No controller or route needed.

1. Create the use case and declare **subscribe** to the event (use case symbol or custom event name):

```ruby
# app/use_cases/notifications/send_order_confirmation.rb
class Notifications::SendOrderConfirmation < RageArch::UseCase::Base
  use_case_symbol :send_order_confirmation
  deps :mailer
  subscribe :create_order   # runs when :create_order event is published (default: after that use case runs)

  def call(payload = {})
    return success unless payload[:success]
    mailer.order_confirmation(payload[:value][:order])
    success
  end
end
```

2. The event publisher is already wired in the initializer with `wire_subscriptions_to(publisher)`, so subscriptions are registered when the app loads. No extra step.

To react to **every** event (e.g. logging): use `subscribe :all`. The payload will include `:event` with the event name.

---

## 4. Orchestrate: call another use case from a use case

One use case calls another by symbol. Declare `use_cases` and invoke with `.call(params)`:

```ruby
class CreateOrderWithNotification < RageArch::UseCase::Base
  use_case_symbol :create_order_with_notification
  deps :order_store
  use_cases :orders_create, :send_order_confirmation

  def call(params = {})
    result = orders_create.call(params)
    return result unless result.success?
    send_order_confirmation.call(order_id: result.value[:order].id)
    result
  end
end
```

---

## 5. Change a dependency (add / remove / rename)

- **Add:** Add the symbol to `deps` in the use case, use it in `call`. Run `rails g rage_arch:dep notifications` if new, implement and `RageArch.register(:notifications, ...)` in the initializer.
- **Remove:** Remove the symbol from `deps` and all usages; optionally remove the dep class and registration.
- **Rename:** Change the symbol in `deps` and in the use case; rename the dep class/file and update `RageArch.register(:new_name, ...)`.

---

## 6. Swap a dep implementation (use case unchanged)

Change *who* implements a dep (e.g. API vs Active Record) without changing the use case.

1. Implement a new class that responds to the same methods (e.g. `get_all_items`).
2. In `config/initializers/rage_arch.rb`, change the registration:

```ruby
# RageArch.register(:items_service, ItemsServiceApi.new)
RageArch.register(:items_service, ItemsServiceActiveRecord.new)
```

Or use the generator to list and choose:

```bash
rails g rage_arch:dep_switch items_service
rails g rage_arch:dep_switch items_service ItemsServiceActiveRecord
```

---

## 7. Disable auto-publish or opt-out

- **Global:** In `config/application.rb` or an initializer: `config.rage.auto_publish_events = false`. Then no use case publishes automatically; only manual `event_publisher.publish(...)` where you have `deps :event_publisher`.
- **Per use case:** In the use case class add `skip_auto_publish` (e.g. for the logging use case so it doesn’t publish when it runs).

---

## Command cheat sheet

| Goal | Commands / actions |
|------|--------------------|
| Install RageArch | `bundle install` then `rails g rage_arch:install` |
| **Full CRUD (scaffold)** | `rails g rage_arch:scaffold Post title:string body:text` → model, migration, use cases, dep, controller, views, routes. Add `--api` for JSON-only. |
| New use case | `rails g rage_arch:use_case RefundOrder` or `rails g rage_arch:use_case Orders::ShipOrder` |
| New dep from use case | `rails g rage_arch:dep order_repo` |
| AR dep | `rails g rage_arch:ar_dep post_store Post` |
| Swap dep implementation | Edit initializer or `rails g rage_arch:dep_switch items_service [ClassName]` |

---

## Assumptions

- `ApplicationController` includes `RageArch::Controller` (done by `rails g rage_arch:install`), giving you `run`, `run_result`, and `flash_errors`.
- All deps used by use cases are registered in `config/initializers/rage_arch.rb` (inside `Rails.application.config.after_initialize`).
- The event publisher is created, wired with `RageArch::UseCase::Base.wire_subscriptions_to(publisher)`, and registered as `:event_publisher` if you use domain events or auto-publish.
- Use case files under `app/use_cases` are loaded by the railtie; you do not need to reference the use case class in the controller for it to be available by symbol.
