---
layout: post
title: How to build an OIDC provider using rodauth-oauth on Rails
keywords: rodauth-oauth, rodauth, rails, rodauth-rails, OAuth2, OIDC, OIDC Connect, tutorial
---

One of my most recent ruby open-source projects is [rodauth-oauth](https://honeyryderchuck.gitlab.io/rodauth-oauth), a rack-based toolkit to help easily build OAuth and OpenID Connect providers, built on top of [rodauth](http://rodauth.jeremyevans.net/) (the most advanced authentication provider library for ruby). I summarized my [initial motivation for "rolling my own" in the project Wiki](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki/FAQ), namely the lack of a decent framework-agnostic alternative (I didn't want to have to use Rails), and what I perceived as the limitations of the "de-facto" OAuth provider Rails extension, "doorkeeper".

One less known "feature" of `rodauth-oauth`, given the initial motivation, is that it can be used with Rails. In fact, around the same time I started working on `rodauth-oauth`, [Janko Mahronic started rodauth-rails](https://github.com/janko/rodauth-rails), which aimed at making the integration of `rodauth` in rails as seamless as any other rails-friendly authentication gem. So after I got my early proof-of-concept, I made supporting `rodauth-rails` a priority. Both gems have grown since then.

Although there's enough documentation on how to set it up with Rails, I've never got to write any free-form HOW-TO guides. [Janko has been actively releasing articles about rodauth-rails](https://janko.io/adding-multifactor-authentication-in-rails-with-rodauth/), so I think it's time I should do the same as well.

So, what does it take to start an OpenID Connect Provider on Rails using `rodauth-oauth`?

Our first step would be to bootstrap a Rails app, integrate `rodauth` (via `rodauth-rails`), add some basic CRUD/resources and authentication... sounds like a lot of work. Fortunately, [Janko already did the work of providing such a demo app](https://github.com/janko/rodauth-demo-rails), that I will use as my starting point. It's a very simple app, which manages posts behind some authentication-driven authorship.

For more information about this example app, make sure to read:

* [Adding Authentication in Rails 6 with Rodauth](https://janko.io/adding-authentication-in-rails-with-rodauth/)
* [Adding Multifactor Authentication in Rails 6 with Rodauth](https://janko.io/adding-multifactor-authentication-in-rails-with-rodauth/)

In order to make this more interesting, this app will also be a "resource server" (in OAuth "parlance"), given access to user posts via the "posts.read" scope.

So let's get this started with!

## 1. rodauth-rails

After cloning the project, I ran the following commands:

```
> bundle install
> bundle exec rails db:create (make sure you have "postgresql" installed)
> bundle exec rails db:migrate
> bundle exec rails server
```

And my app is running under "http://localhost:3000". I open my browser and:

![Rails Error]({{ '/images/rodauth-oauth-rails/rails-error.png' | prepend: site.baseurl }})

Oh, bummer. I guess I need more "wheels" for rails 6. Thanks, rails.

After a couple of searches about the topic, I run:

* `bundle exec rails webpacker:install`
* `bundle exec bin/webpack-dev-server`

I have another look at the browser:

![Rails Success]({{ '/images/rodauth-oauth-rails/rails-success.png' | prepend: site.baseurl }})

And we're up and running! I create and verify a Tester acccount then:

![Logged In]({{ '/images/rodauth-oauth-rails/logged-in.png' | prepend: site.baseurl }})

And we're up and running!

## 2. install rodauth-oauth

In order to integrate `rodauth-oauth` in rails, we're going to add the gem to our Gemfile and follow the [instructions from the wiki](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki/Rails).

```ruby
# Gemfile
gem "rodauth-oauth"
```

### 2.1. run the db-level generator

Next we run the following command:

```
> bundle exec rails generate rodauth:oauth:install
create  db/migrate/20210316141438_create_rodauth_oauth.rb
create  app/models/oauth_application.rb
create  app/models/oauth_grant.rb
create  app/models/oauth_token.rb
```

This generator creates all the following resources: the OAuth Token, Grant and Application models, and a single migration file to create all the related database-level resources. One is supposed to tweak this migration depending of the features to enable, so this is what a DB schema for an OIDC provider would look like:

```ruby
# db/migrate/20210316141438_create_rodauth_oauth.rb
class CreateRodauthOAuth < ActiveRecord::Migration[6.1]
  def change
    create_table :oauth_applications do |t|
      t.integer :account_id
      t.foreign_key :accounts, column: :account_id
      t.string :name, null: false
      t.string :description, null: false
      t.string :homepage_url, null: false
      t.string :redirect_uri, null: false
      t.string :client_id, null: false, index: { unique: true }
      t.string :client_secret, null: false, index: { unique: true }
      t.string :scopes, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    create_table :oauth_grants do |t|
      t.integer :account_id
      t.foreign_key :accounts, column: :account_id
      t.integer :oauth_application_id
      t.foreign_key :oauth_applications, column: :oauth_application_id
      t.string :code, null: false
      t.datetime :expires_in, null: false
      t.string :redirect_uri
      t.datetime :revoked_at
      t.string :scopes, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      # for using access_types
      t.string :access_type, null: false, default: "offline"
      # uncomment to enable PKCE
      # t.string :code_challenge
      # t.string :code_challenge_method
      # uncomment to use OIDC nonce
      t.string :nonce
      t.index(%i[oauth_application_id code], unique: true)
    end

    create_table :oauth_tokens do |t|
      t.integer :account_id
      t.foreign_key :accounts, column: :account_id
      t.integer :oauth_grant_id
      t.foreign_key :oauth_grants, column: :oauth_grant_id
      t.integer :oauth_token_id
      t.foreign_key :oauth_tokens, column: :oauth_token_id
      t.integer :oauth_application_id
      t.foreign_key :oauth_applications, column: :oauth_application_id
      t.string :refresh_token_hash, token: true, unique: true
      t.datetime :expires_in, null: false
      t.datetime :revoked_at
      t.string :scopes, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      # uncomment to use OIDC nonce
      t.string :nonce
    end
  end
end
```

Then I run `bundle exec rails db:migrate` one more time.

### 2.2. Configure oauth/oidc options

Again, you should adjust this to the features you want to enable. This is an example of what I consider a "good enough" connfiguration for this tutorial:

```ruby
# in lib/rodauth_app.rb
#
# Declare public and private keys with which to verify the id_token
# PRIV_KEY = OpenSSL::PKey::RSA.new(File.read("path/to/privkey.pem"))
# PUB_KEY = OpenSSL::PKey::RSA.new(File.read("path/to/pubkey.pem"))

enable :create_account, :verify_account, ....., :oidc

# ...


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
  @profile ||= Profile.find_by(account_id: account[:id])
  case param
  when :email
    account[:email]
  when :email_verified
    account[:status] == "verified"
  when :name
    @profile.name
  end
end

# ...

route do |r|
  ...
  r.rodauth # route rodauth requests
  rodauth.oauth_applications # oauth application management dashboard
  # OpenID specific, enable service discovery
  rodauth.openid_configuration
  rodauth.webfinger
```

Consider reading the [security recommendations at this point as well](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki/Security-Considerations).

### 2.3. Generate the views

Now I run the following command:

```
> bundle exec rails generate rodauth:oauth:views -a
create  app/views/rodauth/authorize.html.erb
create  app/views/rodauth/oauth_applications.html.erb
create  app/views/rodauth/oauth_application.html.erb
create  app/views/rodauth/new_oauth_application.html.erb
```

I ran it with `-a` because I'll be integrating [Oauth Applications management, which is optional](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki/OAuth-applications-and-token-management). If you prefer to bootstrap creating the OAuth Applications yourself via the command line, you are free to do so, in which case, only the Authorization Form will be initiated.


## 3.a Make OAuth Applications Management available (optional)

At this point, your users should be able to navigate to the oauth applications management page, which means, there should be a link somewhere. Given that the demo app has a navbar, I'll just add it there:

```diff
</li>
+ <% if rodauth.logged_in? %>
+   <li class="nav-item <%= "active" unless current_page?(rodauth.oauth_applications_path) %>">
+     <%= link_to_unless_current "Client Applications", rodauth.oauth_applications_path, class: "nav-link" %>
+   </li>
+ <% end %>
```


And voilà!

![applications navbar]({{ '/images/rodauth-oauth-rails/applications-navbar.png' | prepend: site.baseurl }})

And when I follow the link:

![applications empty]({{ '/images/rodauth-oauth-rails/applications-empty.png' | prepend: site.baseurl }})

Looks weird, I know. But hey, we have a dashboard for our test user's oauth client applications. So let's start filling it up:

![application form]({{ '/images/rodauth-oauth-rails/application-form-1.png' | prepend: site.baseurl }})

Some things to pay attentionn to in this form:

* "Name" and "Description" fields can be used in the Authorization Form, to inform the user on which application is requesting which permissions.
* "Homepage URL" and "Redirect URL" are URLs from the client application being registered, the second being the URL the user will be redirected to after authorizing the client application. In production, as per the configuration notes, these URLs **must** be https. However, for demonstration purposes, we'll be using a client application running in *http://localhost:9293*.
* "Secret" is an input. By default, `rodauth-oauth` doesn't generate a client secret for client applications, as this requires the OIDC provider to know how these are generated, thereby making it less secure (it's the same as storing a password in plaintext). So, you'll have to introduce yours, and keep it somewhere safe.

So, I fill up the form:

![application form filled]({{ '/images/rodauth-oauth-rails/application-form-2.png' | prepend: site.baseurl }})

And I submit:

![application page]({{ '/images/rodauth-oauth-rails/application-page.png' | prepend: site.baseurl }})

![applications with 1]({{ '/images/rodauth-oauth-rails/applications-with-1.png' | prepend: site.baseurl }})

And we have our first Client Application. Success!

### 3.b Manage clients via the manager

Ok, dashboards are nice, but sometimes you want to provide some "quick to market" OIDC provider solution, without going through the hassle of tinkering on the "self-serve" part of oauth application manangemennt, because you have no designer availability, there's a short initial set of clients to integrate with, and you have account managers, who can collect the data offline and handover the credentials. That's fine. You can skip 2.4 altogether, and write your own command line ruby script:

```ruby
client_id = SecureRandom.urlsafe_base64(32)
client_secret = SecureRandom.urlsafe_base64(32)
client_account = Account.find(CLIENT_ID) # you should know this one

OauthApplication.create!(
  account: client_account,
  client_id: client_id,
  client_secret: BCrypt::Password.create(client_id),
  name: "Client Posts App",
  description: "A app showing my posts from this one",
  redirect_uri: "http://localhost:9293/auth/openid_connect/callback",
  homepage_url: "http://localhost:9293",
  scopes: "openid email profile books.read",
)
```

And decide how you want to pass the credentials to your costumers.

And now, time to integrate with a client!

# 4. Client Integration

Now we need that "Client Posts App" client to integrate with our OpenID provider. How shall we do this? Fortunately, I've got this covered: [rodauth-oauth ships with some examples for all supported scenarios](https://gitlab.com/honeyryderchuck/rodauth-oauth/-/tree/master/examples), so in this case, I'll [just reuse the OIDC client application](https://gitlab.com/honeyryderchuck/rodauth-oauth/-/blob/master/examples/oidc/client_application.rb), which is a single-ruby-file single-page app listing some books, fetched via an API request authorized via the ID token. The OIDC integration is done via the [omniauth-openid-connect gem](https://github.com/jjbohn/omniauth-openid-connect).

A few tweaks need to be done though, so that this "book app" becomes a "posts app".

```diff
 AUTHORIZATION_SERVER = ENV.fetch("AUTHORIZATION_SERVER_URI", "http://localhost:9292")
-RESOURCE_SERVER = ENV.fetch("RESOURCE_SERVER_URI", "http://localhost:9292/books")
+RESOURCE_SERVER = ENV.fetch("RESOURCE_SERVER_URI", "http://localhost:9292/posts")
# ...
             crossorigin="anonymous"></link>
-      <title>Rodauth Oauth Demo - Book Store Client Application</title>
+      <title>Rodauth Client Posts App</title>
# ...
           <div class="main px-3 py-3 pt-md-5 pb-md-4 mx-auto text-center">
-            <h1 class="display-4">Book Store</h1>
+            <h1 class="display-4">Posts</h1>
# ...
+                 @posts = json_request(:get, RESOURCE_SERVER, headers: { "authorization" => "Bearer #{token}" })
                  <<-HTML
-                  <div class="books-app">
+                  <div class="posts-app">
                     <ul class="list-group">
-                      <% @books.each do |book| %>
-                        <li class="list-group-item">"<%= book[:name] %>" by <b><%= book[:author] %></b></li>
+                      <% @posts.each do |post| %>
+                        <li class="list-group-item"><%= post[:title] %>: <i>"<%= post[:body] %>"</i> %></b></li>
                       <% end %>
# you get the gist...
```

After adding the necessary dependencies to the Gemfile, I can run it simply as:

```bash
> export RESOURCE_SERVER_URI=http://localhost:3000/posts
> export AUTHORIZATION_SERVER_URI=http://localhost:3000
> export CLIENT_ID=fLI0lAIjswWG0z4XpB0FCOPfC7Dr15d2kWErlgwQLds
> export CLIENT_SECRET=dbjounabeequtxrtrslabkrvtcfpjswgdnntzmjtcmdacpxqwnhmjlbjpfvxqegi
> bundle exec ruby scripts/client_application.rb
```

(**NOTE**: If you run this with ruby 3, make sure you bundle `webrick`, or some other rack server, as well).

And then I browse "http://localhost:9293":

![client application 1]({{ '/images/rodauth-oauth-rails/client-application-1.png' | prepend: site.baseurl }})

As you see, nothing much to click around besides that top-right big "Authenticate with OpenID" button. When you click it, you are then redirected to our OpenID provider authorization flow, which looks like:

![authorization form]({{ '/images/rodauth-oauth-rails/authorization.png' | prepend: site.baseurl }})

And here we have it: the name of the Client Application, the requested permissions, and the "Authorize" and "Cancel" buttons. Let's authorize!

![client application 2]({{ '/images/rodauth-oauth-rails/client-application-2.png' | prepend: site.baseurl }})


And you've just been authenticated via OpenID Connect, congratulations! There's your OIDC provider username on the top-right corner. And there's the list of posts authored by you in the posts resource provider.


That's it. Simple, right?

## Leveraging rodauth

The beauty of standing on the shoulders of `rodauth` is that most security and compliance extensions around authentication you'll ever need are already built-in. Let's say that your enterprise customers want to have users 2-factor-authenticated before granting access.

No problem:

```ruby
# in rodauth_app.rb
before_authorize do
  # at this point they're already logged in
  require_two_factor_authenticated
end

```

So now I setup TOTP in my test account:

![manage MFA]({{ '/images/rodauth-oauth-rails/manage-mfa.png' | prepend: site.baseurl }})

Then I logout and login again with email and password. I go back to my client application:

![client application 1]({{ '/images/rodauth-oauth-rails/client-application-1.png' | prepend: site.baseurl }})

I press "Authenticate with OpenID":

![auth MFA]({{ '/images/rodauth-oauth-rails/auth-mfa.png' | prepend: site.baseurl }})

I get requested for my TOTP code. I introduce it:

![authorization MFA]({{ '/images/rodauth-oauth-rails/authorization-form-mfa.png' | prepend: site.baseurl }})

And I'm back to the Authorization form. It just worked!

## Conclusion

It was a very positive experience to put myself on "the other side" and test-drive the integration. I actually ended up discovering a bug or two, which have been fixed in `rodauth-oauth` v0.5.1 . But overall, it felt good to see the integration unfold in a straightforward way.

I hope that this tutorial delivered the promise of a simple introduction to building OAuth/OIDC providers in rails apps; using generators to "import" models and templates to your project, providing you with a starting point you can build up from, while also providing multiple knobs for oauth.related advanced features (check the [project's wiki](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki) for that).

You can find the demo app under [this gitlab repository](https://gitlab.com/honeyryderchuck/rodauth-oauth-demo-rails).
