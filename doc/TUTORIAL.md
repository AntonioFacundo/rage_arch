# Rails vs Rails + RageArch: side-by-side tutorial

This tutorial builds the same app twice -- first with vanilla Rails, then with RageArch -- to show that you get clean architecture with almost the same effort.

The app: a simple **blog** with Posts (title, body) and full CRUD.

---

## Round 1: Vanilla Rails

```bash
rails new blog
cd blog
rails g scaffold Post title:string body:text
rails db:migrate
rails server
```

**4 commands.** You have a working CRUD at `localhost:3000/posts`.

### What you got

```
app/
  controllers/
    posts_controller.rb      # 7 actions, ~60 lines, all logic here
  models/
    post.rb                  # empty for now
  views/
    posts/                   # index, show, new, edit, _form, _post
```

The controller does everything: finds records, builds objects, saves, handles errors, redirects. The model is empty... for now.

### Where it breaks down

Your PM says: "send an email when a post is created." Vanilla Rails:

```ruby
# Option A: callback in the model (the Rails Way)
class Post < ApplicationRecord
  after_create :send_notification

  private

  def send_notification
    PostMailer.created(self).deliver_later
  end
end

# Option B: shove it in the controller
def create
  @post = Post.new(post_params)
  if @post.save
    PostMailer.created(@post).deliver_later   # added here
    redirect_to @post, notice: "Created."
  else
    render :new, status: :unprocessable_entity
  end
end
```

Both are bad. The model grows fat with callbacks. The controller becomes a dumping ground. Testing requires loading Rails. And when you need to create posts from a background job, an API, or a console script, the behavior is either duplicated or inconsistently triggered.

---

## Round 2: Rails + RageArch

```bash
rails new blog
cd blog
```

Add to `Gemfile`:

```ruby
gem "rage_arch"
```

```bash
bundle install
rails g rage_arch:install
rails g rage_arch:scaffold Post title:string body:text
rails db:migrate
rails server
```

**5 commands** (+ 1 line in Gemfile). Same working CRUD at `localhost:3000/posts`.

### What you got

```
app/
  controllers/
    posts_controller.rb      # 7 actions, thin — just delegates to use cases
  models/
    post.rb                  # clean — schema only, no callbacks
  use_cases/
    posts/
      list.rb                # Posts::List
      show.rb                # Posts::Show
      new.rb                 # Posts::New
      create.rb              # Posts::Create
      update.rb              # Posts::Update
      destroy.rb             # Posts::Destroy
  deps/
    posts/
      post_repo.rb           # Posts::PostRepo — wraps ActiveRecord
  views/
    posts/                   # same views as vanilla
config/
  initializers/
    rage_arch.rb             # event publisher wired, deps auto-registered
```

### The controller is thin

```ruby
class PostsController < ApplicationController
  def index
    run :posts_list,
      success: ->(r) { @posts = r.value[:posts]; render :index },
      failure: ->(r) { redirect_to root_path, alert: r.errors.join(", ") }
  end

  def create
    run :posts_create, post_params,
      success: ->(r) { redirect_to post_path(r.value[:post].id), notice: "Post was successfully created." },
      failure: ->(r) {
        new_result = run_result(:posts_new)
        @post = new_result.success? ? new_result.value[:post] : nil
        flash_errors(r)
        render :new, status: :unprocessable_entity
      }
  end

  # ...
end
```

No business logic. Just "run use case, handle result."

### The use case holds the logic

```ruby
module Posts
  class Create < RageArch::UseCase::Base
    deps :post_repo

    def call(params = {})
      item = post_repo.build(params)
      return failure(item.errors.full_messages) unless post_repo.save(item)
      success(post: item)
    end
  end
end
```

Clear, testable, isolated.

### The dep wraps persistence

```ruby
module Posts
  class PostRepo
    def initialize
      @adapter = RageArch::Deps::ActiveRecord.for(Post)
    end

    def build(attrs = {})  = @adapter.build(attrs)
    def find(id)           = @adapter.find(id)
    def save(record)       = @adapter.save(record)
    def update(record, attrs) = @adapter.update(record, attrs)
    def destroy(record)    = @adapter.destroy(record)
    def list(filters: {})  = @adapter.list(filters: filters)
  end
end
```

---

## Adding features: where the difference shows

### "Send an email when a post is created"

Generate the mailer and its dep wrapper in one command:

```bash
rails g rage_arch:mailer PostMailer post_created
```

This creates:
- `app/mailers/post_mailer.rb` (standard Rails mailer)
- `app/deps/post_mailer_dep.rb` (dep wrapper, auto-registered)

Then create a subscriber use case:

```ruby
# app/use_cases/notifications/send_post_created_email.rb
class Notifications::SendPostCreatedEmail < RageArch::UseCase::Base
  deps :post_mailer
  subscribe :posts_create  # runs async after Posts::Create finishes

  def call(payload = {})
    return success unless payload[:success]
    post_mailer.post_created(payload[:value][:post])
    success
  end
end
```

Done. No changes to the controller. No changes to the model. No callbacks. The event is published automatically when `Posts::Create` succeeds.

### "Also log every use case that runs"

```ruby
# app/use_cases/audit/logger.rb
class Audit::Logger < RageArch::UseCase::Base
  skip_auto_publish
  subscribe :all

  def call(payload = {})
    Rails.logger.info "[Audit] #{payload[:event]} success=#{payload[:success]}"
    success
  end
end
```

One file. Logs everything. No changes anywhere else.

### "Rollback the post if the notification fails"

Add `undo` to the create use case:

```ruby
module Posts
  class Create < RageArch::UseCase::Base
    deps :post_repo

    def call(params = {})
      item = post_repo.build(params)
      return failure(item.errors.full_messages) unless post_repo.save(item)
      success(post: item)
    end

    def undo(value)
      post_repo.destroy(value[:post]) if value&.dig(:post)
    end
  end
end
```

### "Switch from ActiveRecord to an external API"

```bash
rails g rage_arch:dep_switch post_repo
# Lists available implementations, choose one
```

Or create a new dep in `app/deps/posts/` that calls your API, and the use case stays untouched.

---

### "Process posts in the background"

```bash
rails g rage_arch:job ProcessPost posts_create
```

Generates `app/jobs/process_post_job.rb`:

```ruby
class ProcessPostJob < ApplicationJob
  queue_as :default

  def perform(**params)
    result = RageArch::UseCase::Base.build(:posts_create).call(params)

    unless result.success?
      Rails.logger.error "[ProcessPostJob] Use case :posts_create failed: #{result.errors.inspect}"
    end

    result
  end
end
```

No business logic in the job. It just delegates to the use case.

### "Add static pages (home, about, contact)"

In vanilla Rails: `rails g controller Pages home about contact` -- generates a controller with empty actions. You still write the logic inline.

With RageArch:

```bash
rails g rage_arch:controller Pages home about contact
```

Generates a thin controller with `run` calls + a use case for each action:

```ruby
# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
    run :pages_home,
      success: ->(r) { render :home },
      failure: ->(r) { flash_errors(r); redirect_to root_path }
  end

  def about
    run :pages_about,
      success: ->(r) { render :about },
      failure: ->(r) { flash_errors(r); redirect_to root_path }
  end

  def contact
    run :pages_contact,
      success: ->(r) { render :contact },
      failure: ->(r) { flash_errors(r); redirect_to root_path }
  end
end
```

Plus `app/use_cases/pages/home.rb`, `about.rb`, `contact.rb` -- ready to fill with logic.

### "Add an API resource without views"

In vanilla Rails: `rails g resource Product title:string price:decimal` -- generates model, empty controller, routes.

With RageArch:

```bash
rails g rage_arch:resource Product title:string price:decimal
```

Generates model, migration, CRUD use cases, dep, API-style controller, and routes -- all wired. No views.

---

## The scoreboard

| | Vanilla Rails | Rails + RageArch |
|---|---|---|
| **Commands to CRUD** | 4 | 5 (+1 line in Gemfile) |
| **Working app** | Yes | Yes |
| **Business logic location** | Controller or model | Use cases |
| **Model callbacks** | Yes (grows over time) | None |
| **Testable without Rails** | No | Yes (inject fake deps) |
| **Add email notification** | Edit model or controller | `rage_arch:mailer` + 1 subscriber file |
| **Add background job** | Write job with inline logic | `rage_arch:job` -- delegates to use case |
| **Add static pages** | `rails g controller` + inline logic | `rage_arch:controller` -- use case per action |
| **Add API resource** | `rails g resource` + write actions | `rage_arch:resource` -- full CRUD wired |
| **Add audit logging** | Custom middleware or concern | Add 1 file (subscribe :all) |
| **Swap persistence** | Rewrite controller + model | Swap dep, use case unchanged |
| **Automatic rollback** | Manual | Define `undo`, automatic cascade |

---

## Summary

One extra command. Same working app. But when requirements grow, vanilla Rails forces you to choose between fat models and fat controllers. RageArch gives you a place for every piece of logic from day one -- and each new feature is just a new file, not a change to existing code.
