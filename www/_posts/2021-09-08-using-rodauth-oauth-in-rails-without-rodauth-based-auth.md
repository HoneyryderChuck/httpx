---
layout: post
title: Build an OIDC provider with rodauth-oauth in rails, while keeping your authentication
keywords: rodauth-oauth, rodauth, rails, rodauth-rails, OAuth2, OIDC, OIDC Connect, tutorial
---

I've written before about rodauth-oauth and [how to use it to make an OAuth2 or OIDC Connect provider out of a rails application](https://honeyryderchuck.gitlab.io/httpx/2021/03/15/oidc-provider-on-rails-using-rodauth-oauth.html), and where I [built a rails demo app based out of Janko Mahronic's rodauth-rails demo app as a workable tutorial](https://gitlab.com/honeyryderchuck/rodauth-oauth-demo-rails). It shows well what rodauth accomplishes, how integrating it in a rails app became significantly simpler thanks to [rodauth-rails](https://github.com/janko/rodauth-rails), and how one can building an OAuth/OIDC provider using [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth) on top of that.

Recently, I got asked by a former co-worker what do I suggest for building an OAuth provider in a rails app. I suggested [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth). "But we already have our own authentication. Doesn't [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth) require that authentication is handled by [rodauth](https://github.com/jeremyevans/rodauth/)?".

I said "no, it does not, it just requires a few undocumented tweaks". And then I realized that it's not that obvious for anyone not familiar with the toolchain how this would get done, and how much of a barrier for adoption that is. A lot of Rails deployments rely on [devise](https://github.com/heartcombo/devise) or something else based on [warden](https://github.com/wardencommunity/warden) for authentication, and while it's certainly reasonable to "sell" [rodauth](https://github.com/jeremyevans/rodauth/) as a much better alternative to consider, buying into [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth) should not require a whole rewrite of the authentication system.

So if you'd like to try [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth) for OAuth and keep your authentication logic, this tutorial is for you.

## 1. Rails and Devise sitting in a tree

The first is having an example rails app to work with. In order to do so, I'll [follow what Janko used in his first rodauth post](https://janko.io/adding-authentication-in-rails-with-rodauth/) and use his blog bootstrapper example:

```bash
$ git clone https://gitlab.com/janko-m/rails_bootstrap_starter.git rodauth-oauth-devise-demo
$ cd rodauth-oauth-devise-demo
$ bin/setup
```

(This part was easier said than done. I have very little experience with `webpacker`, but it seems that everytime I need it, running a command will always seem to fail and send me in a journey searching for workarounds in google. This one landed [here](https://stackoverflow.com/questions/69046801/brand-new-rails-6-1-4-1-fails-with-webpack-error-typeerror-class-constructor), where I found out that latest-greatest `webpack` isn't compatible with `webpacker`. Always something...)

Now, I will use [devise](https://github.com/heartcombo/devise) for this tutorial.

(**NOTE**: I know there are other alternatives, but [devise](https://github.com/heartcombo/devise) provides me with a "quick to prototype" bootstrap experience for this demo, while the tweaks can apply to any other framework):

```bash
> bundle add devise
```

And run its initializers:

```bash
> bundle exec rails generate devise:install # adds initializers, configs...
> bundle exec rails generate devise User # creates the user model and migrations
# will use devise defaults
> bundle exec rails db:migrate
```

Now let's add some useful links in the navbar:

```erb
<!-- app/views/application/_navbar.html.erb -->
<!-- ... --->
<% if user_signed_in? %>
  <div class="dropdown">
    <%= link_to current_user.email, "#", class: "btn btn-info dropdown-toggle", data: { toggle: "dropdown" } %>
    <div class="dropdown-menu dropdown-menu-right">
      <%= link_to "Change password", edit_user_password_path, class: "dropdown-item" %>
      <div class="dropdown-divider"></div>
      <%= link_to "Sign out", destroy_user_session_path, method: :delete, class: "dropdown-item" %>
    </div>
  </div>
<% else %>
  <div>
    <%= link_to "Sign in", new_user_session_path, class: "btn btn-outline-primary" %>
    <%= link_to "Sign up", new_user_registration_path, class: "btn btn-success" %>
  </div>
<% end %>
<!-- ... --->
```

And lock the posts section for authenticated users:

```ruby
class PostsController < ApplicationController
  before_action :authenticate_user!
  # ...
```

![login-screen-1]({{ '/images/using-rodauth-oauth-devise-rails/login-screen-1.png' | prepend: site.baseurl }})

And that's it, we're set!

## 2. Install rodauth-rails (but not use it for authentication) and rodauth-oauth

Installing is accomplished simply by doing:

```bash
> bundle add rodauth-rails
> bundle add rodauth-oauth
```

First thing we do is to run `rodauth-rails` main initializers:

```bash
> bundle exec rails generate rodauth:install
      create  db/migrate/20210906132849_create_rodauth.rb
      create  config/initializers/rodauth.rb
      create  config/initializers/sequel.rb
      create  app/lib/rodauth_app.rb
      create  app/controllers/rodauth_controller.rb
      create  app/models/account.rb
      create  app/mailers/rodauth_mailer.rb
      create  app/views/rodauth_mailer/email_auth.text.erb
      create  app/views/rodauth_mailer/password_changed.text.erb
      create  app/views/rodauth_mailer/reset_password.text.erb
      create  app/views/rodauth_mailer/unlock_account.text.erb
      create  app/views/rodauth_mailer/verify_account.text.erb
      create  app/views/rodauth_mailer/verify_login_change.text.erb
```

As you can see from the output above, `rodauth-rails` expects that you'll start using `rodauth` for authentication. There are a few switches, such as `--json` or `--jwt`, but they're not very useful for our use-case, which is "just initializers please".

So now it's time to delete things :) Let's start by removing the files we won't need:

```bash
> rm -rf app/views/rodauth_mailer/
> rm app/mailers/rodauth_mailer.rb app/models/account.rb db/migrate/20210906132849_create_rodauth.rb
```

And then update the auto-generated config files:

```ruby
# lib/rodauth_app.rb
class RodauthApp < Rodauth::Rails::App
  configure do
    # List of authentication features that are loaded.
-    enable :create_account, :verify_account, :verify_account_grace_period,
-      :login, :logout, :remember,
-      :reset_password, :change_password, :change_password_notify,
-      :change_login, :verify_login_change,
-      :close_account
+    enable :base
  # ... delete every other default option
  end

  route do |r|
-    rodauth.load_memory # only useful for auth-driven rodauth
-
     r.rodauth # route rodauth requests
```

And now it's time to auto-generate `rodauth-oauth` files:

```bash
> bundle exec rails generate rodauth:oauth:install
      create  db/migrate/20210906134332_create_rodauth_oauth.rb
      create  app/models/oauth_application.rb
      create  app/models/oauth_grant.rb
      create  app/models/oauth_token.rb


> bundle exec rails generate rodauth:oauth:views --all
      create  app/views/rodauth/authorize.html.erb
      create  app/views/rodauth/oauth_applications.html.erb
      create  app/views/rodauth/oauth_application.html.erb
      create  app/views/rodauth/new_oauth_application.html.erb
```

Some changes will be required here as well before running the migrations, given that `devise` created a `users` table, not an `accounts` table like `rodauth` would have:

```ruby
# db/migrate/20210906134332_create_rodauth_oauth.rb
     create_table :oauth_applications do |t|
       t.integer :account_id
-      t.foreign_key :accounts, column: :account_id
+      t.foreign_key :users, column: :account_id
# ...
     create_table :oauth_grants do |t|
       t.integer :account_id
-      t.foreign_key :accounts, column: :account_id
+      t.foreign_key :users, column: :account_id
# ...
     create_table :oauth_tokens do |t|
       t.integer :account_id
-      t.foreign_key :accounts, column: :account_id
+      t.foreign_key :users, column: :account_id
```

And now you're good to go. Run the migrations:

```bash
> bundle exec rails db:migrate
```

And enable the respective `rodauth-oauth` plugins:

```ruby
# lib/rodauth_app.rb

# Declare public and private keys with which to verify the id_token
# PRIV_KEY = OpenSSL::PKey::RSA.new(File.read("path/to/privkey.pem"))
# PUB_KEY = OpenSSL::PKey::RSA.new(File.read("path/to/pubkey.pem"))

enable :oidc

# Make sure you hash the refresh tokens in the DB.
oauth_tokens_refresh_token_hash_column :refresh_token_hash

# list of OIDC and OAuth scopes you handle
oauth_application_scopes %w[openid email profile posts.read]

# default scopes to give to new applications, application-management specific
oauth_application_default_scope %w[openid email profile posts.read]

# by default you're only allowed to use https redirect URIs. But we're developing,
# so it's fine.
if Rails.env.development?
  oauth_valid_uri_schemes %w[http https]
end

# private key to sign ID Tokens with
oauth_jwt_key PRIV_KEY
# public key with which applications can verify ID Tokens
oauth_jwt_public_key PUB_KEY
oauth_jwt_algorithm "RS256"

# this callback is executed when gathering OIDC claims to build the
# ID token with.
# You should return the values for each of these claims.
#
# This callback is called in a loop for all available claims, so make sure
# you memoize access to to the database models to avoid the same query
# multiple times.
get_oidc_param do |account, param|
  @user ||= User.find_by(id: account[:id])
  case param
  when :email
    @user.email
  when :email_verified
    true
  when :name
    @user.name
  end
end
# ...
route do |r|
  r.rodauth # route rodauth requests
  rodauth.oauth_applications
  rodauth.openid_configuration
  rodauth.webfinger
end

# app/models/user.rb
class User < ApplicationRecord

  # dirty hack, so that user has a name.
  def name
    email.split("@").first # "john.doe@example.com" -> "John Doe"
  end
  # ...
```

```erb
<!-- app/views/application/_navbar.html.erb -->
<!-- ... --->
         <li class="nav-item">
           <%= link_to "Posts", posts_path, class: "nav-link" %>
         </li>
+        <% if user_signed_in? %>
+          <li class="nav-item <%= "active" unless current_page?(rodauth.oauth_applications_path) %>">
+            <%= link_to_unless_current "Client Applications", rodauth.oauth_applications_path, class: "nav-link" %>
+          </li>
+        <% end %>
```

Now, let's add some seed data we can test things with, such as a test user account:

```ruby
# db/seed.rb
User.create!(email: "john.doe@example.com", password: "password")
10.times do |i|
  Post.create!(title: "Post #{i}", body: "a story about post #{i}")
end
```

```bash
> bundle exec rails db:seed
```

Now we should be able to start registering our first OAuth application.

![logging-in]({{ '/images/using-rodauth-oauth-devise-rails/login-1.png' | prepend: site.baseurl }})

![logged-in]({{ '/images/using-rodauth-oauth-devise-rails/logged-in-1.png' | prepend: site.baseurl }})

Ok, now let's add a new OAuth Application.

![oauth-applications-error]({{ '/images/using-rodauth-oauth-devise-rails/oauth-applications-error-1.png' | prepend: site.baseurl }})

And here's it is: `rodauth-oauth` couldn't recognize the user is logged in. This is where we'll start tweaking the configuration.

## 4. User is account

The main thing here to stress out is that the default configuration is tailored for `rodauth`. However, it's highly **configurable**! The first thing was already done, namely defined `accounts_table` as the `:users` table where `devise` writes. Now we have to tell `rodauth` when the user is logged in. We do that by adding the following set of custom configs:

```ruby
# lib/rodauth_app.rb

  configure do
    # ... after everything else...

    # to tell rodauth where to redirect if user is not logged in
    require_login_redirect { "/users/sign_in" }

    # reuse devise controller helper
    logged_in? { rails_controller_instance.user_signed_in? }

    # tell rodauth where to get the user ID from devise's session cookie
    session_value do
      rails_controller_instance.session
        .fetch("warden.user.user.key", [])
        .dig(0, 0) || super()
    end
    # ...
```

Long story short, we hoist a couple of calls expecting a rodauth cookie session being defined, to determine whether user is logged in and which user that is, and we "route" those to `devise` entities (i.e. that `"warden.user.user.key"` cookie, which is where `devise` puts the user ID). And once we do that:

![oauth-applications-1]({{ '/images/using-rodauth-oauth-devise-rails/oauth-applications-1.png' | prepend: site.baseurl }})

Et Voilà, applications section unlocked. After filling up the form [exactly in the same way that was described in the previous blog post](https://honeyryderchuck.gitlab.io/httpx/2021/03/15/oidc-provider-on-rails-using-rodauth-oauth.html), I end up with the OAuth application we'll use for the following steps:


![oauth-application-1]({{ '/images/using-rodauth-oauth-devise-rails/oauth-application-1.png' | prepend: site.baseurl }})

## 5. Business as usual

Now it's time to hook our client application. For this purpose, we'll do the same as described in the [previous rodauth-oauth post](https://honeyryderchuck.gitlab.io/httpx/2021/03/15/oidc-provider-on-rails-using-rodauth-oauth.html), and [reuse the same OIDC client application](https://gitlab.com/honeyryderchuck/rodauth-oauth/-/blob/master/examples/oidc/client_application.rb), a single-file single-page app listing some books, fetched via an API request authorized via the ID token.

The same tweaks described there are applied, and the following script is ran for it:

```bash
> export RESOURCE_SERVER_URI=http://localhost:3000/posts
> export AUTHORIZATION_SERVER_URI=http://localhost:3000
> export CLIENT_ID=WJ5hWI_h050Rw0Ve4834lFK2H9Z01urcXiBIs27A5lQ
> export CLIENT_SECRET=owxhtwsruvcltsvhycamoqnmulvfqgdjgpdxappjgywamwnrqdkwpgdlqbonegdo
> bundle exec ruby scripts/client_application.rb
```


![client-application-1]({{ '/images/using-rodauth-oauth-devise-rails/client-application-1.png' | prepend: site.baseurl }})

And here we go:

![authorize-1]({{ '/images/using-rodauth-oauth-devise-rails/authorize-1.png' | prepend: site.baseurl }})

![authorize-error-2]({{ '/images/using-rodauth-oauth-devise-rails/authorize-error-2.png' | prepend: site.baseurl }})

The problem here is that access to posts controller is protected via the `authenticate_user!` before action from `devise`. After the OIDC authentication however, requests are authenticated via ID token, which `devise` doesn't know about. It's up to you now to provide a new set of before actions, or override the existing ones. For the sake of completeness, I'm going with the latter, but just bear in mind there are other ways to accomplish this.

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def authenticate_user!
    rodauth.session_value || super
  end

  def user_signed_in?
    super || rodauth.logged_in?
  end

  def current_user
    super || begin
      User.find(rodauth.session_value)
    rescue ActiveRecord::RecordNotFound
    end
  end

  # another helper which could be used to specifically filter access only to Tokens
  # with the right permission claims.
  def require_read_access
    rodauth.require_oauth_authorization("posts.read")
  end
end
```

Now let's do this again:

![authorize-1]({{ '/images/using-rodauth-oauth-devise-rails/authorize-1.png' | prepend: site.baseurl }})

![authorized-1]({{ '/images/using-rodauth-oauth-devise-rails/authorized-1.png' | prepend: site.baseurl }})

Success!

## 6. Conclusion

As the article proves, it is possible to use `rodauth-oauth` without actually using `rodauth` for authentication, with a few tweaks to the configuration. `devise` was used for demonstration purposes, but the same lessons can be replicated for any other authentication library (`sorcery`, `warden-rails`, plain `warden`...).

It's now up to the user to decide whether these tweaks are worth it, compared to the alternative frameworks for OAuth or OIDC.

And who knows, maybe you'll like `rodauth`'s approach so much so that you'll start migrating your authentication system to it :) .

You can find the demo app under [this gitlab repository](https://gitlab.com/honeyryderchuck/rodauth-oauth-devise-demo).
