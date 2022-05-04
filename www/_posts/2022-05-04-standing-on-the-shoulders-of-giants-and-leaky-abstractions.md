---
layout: post
title: Standing on the shoulders of giants and leaky abstractions
keywords: sequel, rodauth, roda, rails, activerecord, rodauth-oauth
---


Recently, a [blog post about how to use activerecord as a library was shared on r/ruby](https://old.reddit.com/r/ruby/comments/tqlhsw/how_to_use_activerecord_in_a_library/), which started an interesting discussion thread (where I was involved) from the premise "instead of using activerecord out of the rails, why not sequel"? While several arguments were made both for and against the premise, it felt that, at times, discussion deviated towards the merits of `sequel` vs. `activerecord`, rather than using or building a gem on top of them, as a dependency; and as usual in the social network sphere, comments may have been misunderstood, everybody went their separate ways, and the Earth completed another orbit around the sun.

While the topic of which of the ORMs [has better performance](https://samsaffron.com/archive/2018/06/01/an-analysis-of-memory-bloat-in-active-record-5-2), [more useful features](https://janko.io/ode-to-sequel/), [is more popular](https://ruby.libhunt.com/compare-sequel-vs-activerecord) or has more plugins, has been discussed *ad eternum*, most of them start from the premise of the ORM as a primary dependency, exposed to the application developer. This usually leads to less technical, more "pragmatic" discussions, given how usually, constraints around the choice of tech stack is established by "less technical more political" reasons, i.e. whatever the CTO likes more, or whatever the team is most familiar with, what can the company find more specialists for, or risk appettite in experimenting with alternative stacks.


But if you're building a library, then picking any DB library/ORM as a dependency which does not "leak" to the end user (or just a little sometimes), can make one weigh alternatives differently. What's the maintenance burden ratio gonna look like? How hard will it be to support the API as new versions come along? Will the API change a lot? Does it support all the features my library requires? Will it be community-friendly, will I get help maintaining it? These questions aren't limited to the case of relying on a db library, they're also valid when considering building on top of any 3rd party dependency, like a web framework or HTTP client.

So on the topic, I'll share my opinion on the matter based on my experience as an OSS maintainer building on top of `sequel` versus an alternative built for rails (and therefore, `activerecord`).

## rodauth-oauth vs doorkeeper

I'm the maintainer of [rodauth-oauth](https://honeyryderchuck.gitlab.io/rodauth-oauth/), the most complete and featureful OAuth/OIDC provider framework in the ruby ecosystem. This claim is backed by it being the ruby gem implementing the most OAuth 2.0 and OIDC RFCs.

It's far from the most popular though, which is [doorkeeper](https://github.com/doorkeeper-gem/doorkeeper). The huge gap between them in terms of popularity can be explained by `doorkeeper` having existed for +10 years and gone through the "ruby hype" years, whereas `rodauth-oauth` has only existed since 2020. But it's nonetheless the reference implementation in the OAuth provider space, and both [GitLab](https://gitlab.com/) and [Mastodon](https://mastodon.social/about) are known products using it in production.

Tech-wise, `rodauth-oauth` is built on top of the [rodauth](http://rodauth.jeremyevans.net/)/[roda](http://roda.jeremyevans.net/)/[sequel](http://sequel.jeremyevans.net/) stack, whereas `doorkeeper` is a rails-only gem, managed as a classic rails engine, just like [devise](https://github.com/heartcombo/devise).

Product-wise, `rodauth-oauth` has more features and covers more of the [OAuth](https://oauth.net/specs/) and [OpenID](https://openid.net/developers/specs/) specs (check [this feature matrix](https://gitlab.com/honeyryderchuck/rodauth-oauth/-/wikis/Home#comparisons)); these are shipped and can be tested together. The `doorkeeper` gem is not as comprehensive: it ships with support for opaque tokens only, the original 4 OAuth 2.0 grant flows (+ refresh code grant), and PKCE; it has a bigger community of both users and contributors, and some of the missing features are provided by the community as 3rd-party "entension" gems (which, as usual in such a setup, not always work well together. As an example, [doorkeeper-jwt](https://github.com/doorkeeper-gem/doorkeeper-jwt/blob/master/doorkeeper-jwt.gemspec#L25) and [doorkeeper-openid_connect](https://github.com/doorkeeper-gem/doorkeeper-openid_connect/blob/master/doorkeeper-openid_connect.gemspec#L28) don't even agree on which JWT library to use).

## Building for rails vs. building for rodauth

`rails` being the most used framework in the ruby ecosystem, you'll have a hard time getting your gem adopted if it doesn't work on rails.

Although built in a different stack, `rodauth-oauth` can be used with rails, thanks to [rodauth-rails](https://github.com/janko/rodauth-rails), which does the heavy lifting of providing a sane default configuration for rails, as well as a few handy rake tasks (the author published [a blog post recently about how sequel reuses activerecord connection pool in rodauth-rails](https://janko.io/how-i-enabled-sequel-to-reuse-active-record-connection/) which is very enlightening).

`doorkeeper` ships as a rails engine, and in a very similar way to `devise`: a `doorkeeper:install` generator to bootstrap config files and database migrations, a route helper to load `doorkeeper` routes, default views and controllers one may copy to app folders and costumize or not, and an initializer where most of the configuration happens. By using "vanilla rails" features, one can say that, at least from the "looking for an OAuth provider gem for my rails app" angle, that `doorkeeper` seems like the obvious choice.

That said, building a gem targeting rails first brings a lot of maintenance baggage with it.

### Release policy

Every year since 2004, there's a new major/minor version of rails which gets released to as much fanfare and enthusiasm by the people looking forward to new features, as well as dread and despair by the people in charge of upgrading the rails version in huge production apps. That's because rails upgrades tend to change a lot of APIs, often in a breaking way, which may require months of multiple developers time to upgrade. While one can argue about the point of a few of those changes, or just repeat that rails does not follow SemVer, that's just a fact. Which also impacts libraries built for rails.

`doorkeeper` covers a lot of rails API "surface", which means that, inevitably, it is affected by these changes, and a certain amount of time and energy has to be invested yearly in fixing and adapting them as well (this is not a `doorkeeper`-only phenomenom, any gem building on rails goes through the same).

Due to the simple and stable APIs and commmitment to backwards compatibility from the roda/sequel/rodauth stack, `rodauth-oauth` has not had to release a fix due to backwards-incompatible APIs yet. The rails integration bits have also been stable, although they cover less rails API "surface" in comparison (just generators and view templates).

(Take this analysis with a grain of salt, as `doorkeeper` blast radius is wider.)

### Community practices

A lot of rails "convention over configuration" culture is all over `activesupport`. And a lot of practices exposed via its public APIs become teaching subject of "how to do" in rails, also sometimes called the Rails Way. The practice I'll focus on is the "class to tag to class again", whereas, given a class, `ToothPick`, or an instance of it, certain operations (such as, i.e. calculating html tag ids) will automatically infer `"tooth_pick"` (or `:tooth_pick`) by applying a sequence of operations on the class name, namely `.demodulize` and `.underscore`, and in some other cases, such as deserialization, the inverse set of operations, i.e. `classify` and `constantize`, will be applied to infer the class from the string tag.

It's, for instance, how you do `form_for @tooth_pick`, and a `<form id="tooth_pick">` tag is automatically created. This blueprint can be found all over rails and rails-only gems.

Instead of telling what I find about this practice, I'll show an example where this creates limitations, namely, `doorkeeper` inability of supporting the [saml2 bearer grant](https://github.com/doorkeeper-gem/doorkeeper/issues/764), or any other assertion grant type [as defined by the IETF](https://datatracker.ietf.org/doc/html/rfc7521#section-4.1).

`doorkeeper` allows one to enable grant flows via an initializer option:

```ruby
# config/initializers/doorkeeper.rb
Doorkeeper.configure do
  grant_flows ["client_credentials"]
end
```

The `"client_credentials"` grant flow is implemented by many resources with `ClientCredentials` in its namespace: there's a `Doorkeeper::Request::ClientCredentials`, a `Doorkeeper::OAuth::ClientCredentials::Validator`, a `Doorkeeper::OAuth::ClientCredentials::Issuer`, and so on. All of these will be auto-inferred at some point in the execution of the program thanks to the sequence of the transformations explained above.

This works well when your grant flow is called `"client_credentials"`, but not when it's called `"urn:ietf:params:oauth:grant-type:saml2-bearer"`.

This situation is exacerbated by the refusal of `doorkeeper` maintainers of supporting any of these features themselves, instead suggesting the community to rather do it as "extension" gems (`devise` also does the same). This creates a problem of incentives, where a fundamental risky (and potentially breaking) change is required in the "base" gem for this extension to be unlocked, however the "base" gem gets little from it beyond burden of maintenance, so is thereby reluctant to commit the change, whereas someone willing to develop the extension gem may stop at the workarounds necessary to support an edge-case the "base" gem never considered, and the community gets nothing in the process.

None of the above apply to `rodauth-oauth`, given that grant flow identifiers do not have to map to anything internally (they're just literals), and oauth extensions ship and are tested together (shipping extra functionality as a standalone gem is certainly possible, but I encourage anyone to contribute to mainline as long as it's about OAuth).

If we move away from the macro perspective of "building on top of a web/auth framework" back to "building on top of ActiveRecord vs. Sequel", there are also interesting points to discuss.

### ActiveRecord vs. Sequel

A point that arguably needs little discussion is that `sequel` is the most flexible and featureful DB toolkit in ruby, whereas `activerecord` is certainly more popular and has more available plugins/extensions. And while the latter may turn the tables in favour of `activerecord` when it comes to supporting a particular use-case or feature, in most cases, when building a library with DB functionality abstracted away from your end user, one will tilt to the solution which allows one to write the most terse, simple and maintainable code. In most cases, that'd be `sequel`, and that's exactly the choice many libraries have made.

Except if you're building on top of rails, where it's probably best to stick to the defaults, and your default will be `activerecord`. `doorkeeper` falls in the latter case; it ships with support for `activerecord`, although there are other community-maintained extensions supporting [sequel](https://github.com/nbulaj/doorkeeper-sequel) or [couchbase](https://github.com/acaprojects/doorkeeper-couchbase) (how well do they work? No idea, but one of them as seen no updates in 6 years).

`rodauth-oauth` builds on top of `rodauth`, which uses `sequel` under the hood. However, what's worth mentioning here is that the ORM layer isn't used at all; instead, only the dataset API (aka `sequel/core`) is used. This has several performance benefits (lower memory footprint, faster by skipping *to-model* transformations), while also allowing the maintainer to focus on "required data for the functionality" data access patterns, and keeping the other advantages of building on top of a general db library rather than the db client adapters directly (i.e. [free support for a multitude of databases](http://sequel.jeremyevans.net/rdoc/files/doc/opening_databases_rdoc.html)).

Recently, a [performance-related issue](https://github.com/doorkeeper-gem/doorkeeper/pull/1542) was reported in the `doorkeeper` repo which got my attention.

In `doorkeeper`, one can avoid creating multiple access tokens for the same account/client application, by reusing an existing and valid access token, via the [reuse_access_token option](https://github.com/doorkeeper-gem/doorkeeper/issues/383). This works by performing a database lookup for an access token for the given account/client application which has not expired yet.

The version prior to the pull request shared above used a fairly naive heuristic: it would load all access tokens for the given account/client application (in memory, AR instances), then it would return the first one which hadn't expired. Hardly a problem while your tables are small, this could potentially grind your application to a halt as tables grow and a sufficiently ammount of access tokens have been emitted for each user.

The solution was clear: eliminate the expired access tokens from the returned dataset. Given access tokens store the `expires_in` seconds, this required reaching for SQL time-based operations to build a query which could accomplish that. There's just one problem: `activerecord` does not provide functions for that. So in order to fix the performance issue, `doorkeeper` had to [drop down to raw SQL, for all supported database engines](https://github.com/doorkeeper-gem/doorkeeper/blob/b67046ee2d81c1c1d5017d62b6550ca1d273e13e/lib/doorkeeper/models/concerns/expiration_time_sql_math.rb#L17):

```ruby
# mysql
Arel.sql("DATE_ADD(#{table_name}.created_at, INTERVAL #{table_name}.expires_in SECOND)")
# sqlite
Arel.sql("DATETIME(#{table_name}.created_at, '+' || #{table_name}.expires_in || ' SECONDS')")
# postgres
Arel.sql("#{table_name}.created_at + #{table_name}.expires_in * INTERVAL '1 SECOND'")
# and so on...
```

And so, in this way, some raw SQL just leaked.

`rodauth-oauth` also supports this feature, but it does not suffer from the same issue, for 2 key reasons. First, it uses a `sequel` plugin which [adds DSL to support SQL time-based math](http://sequel.jeremyevans.net/rdoc-plugins/files/lib/sequel/extensions/date_arithmetic_rb.html) for supported databases. No need to drop down to SQL, the ORM does it for e.

The second reason is, `rodauth-oauth` does not store the `expires_in` seconds, it instead calculates the expiration timestamp on `INSERT` (using the DSL mentioned above to perform a "current time + expires in" op), which is then used in subsequent queries as a simple and more optimizable filter (you can add indexes for it, which you can't in the `doorkeeper` variant, when the calculation happens on `SELECT`):

```ruby
# on insert
create_params[oauth_tokens_expires_in_column] = Sequel.date_add(Sequel::CURRENT_TIMESTAMP, seconds: oauth_token_expires_in)
db[oauth_tokens_table].insert(create_params)...
# on select
ds = db[oauth_tokens_table].where(Sequel[oauth_tokens_table][oauth_tokens_expires_in_column] >= Sequel::CURRENT_TIMESTAMP)
```

One could pick up this approach and implement it in `doorkeeper`, at the cost of some backwards-incompatibility, which means it would require a data migration. But the fact that such an optimization wasn't obvious from the get-go seems to arguably be a by-product of having the abstraction layer "obscuring" the generated SQL in a way that the costs aren't visible until late in the road, where the cost of "redoing it the right way" may outweigh it.

## Conclusion

This is not all to say that `rodauth-oauth` is better than `doorkeeper` ([Although I believe it is](https://honeyryderchuck.gitlab.io/rodauth-oauth/wiki/FAQ), after all, I maintain it :) ). `doorkeeper` can be objectively considered more mature, and if you're looking for a solution for rails and you don't require the extra features `rodauth-oauth` provides, no one ever got fired for buying IBM. I could have picked up the same discussion using [delayed_job](https://github.com/collectiveidea/delayed_job) as an example, but I don't maintain a similar database-backed background job framework, so any points made by me could be deemed as just "theoretical".

Bottom line, when it comes to how much the extra dependencies one builds on top of might influence its maintainability, overhead time spent on unrelated chores, and focus on building the best solution for whatever problem one wants to solve, `sequel` should definitely be up there in the consideration list.