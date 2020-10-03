---
layout: post
title: Ramblings about initial design decisions, internals, and devise
---

Yesterday I was reading [this twitter thread](https://twitter.com/jankomarohnic/status/1286640026588151808), where [Janko Marohnić](https://twitter.com/jankomarohnic), the maintainer of [Shrine](https://github.com/shrinerb/shrine), who has recently [integrated rodauth in Rails](https://github.com/janko/rodauth-rails) and is preparing a series of articles about it, describes the internals of [devise](https://github.com/heartcombo/devise), the most popular authentication gem for Ruby on Rails, as "making every mistake in the book", claiming that [rodauth](https://github.com/jeremyevans/rodauth), the most advanced authentication framework for ruby, is much better because its internals are "easier to understand", thereby sparking some controversy and replies, with some people taking issue with these claims, and also with his approach of criticizing another gem because of "look how awful its internals look like".


Although Janko does "mea culpa" on his tone, the claim and subsequent comments made me think about it. Is the state of the internals a reliable factor when picking a gem? Does it hamper its future development? Is it actually a goal, to further develop it?  Is it possible to extend it, or support newest protocols and standards? Is it feature-complete, according to its initial goals? And what if a project isn't maintained anymore by its original author, can the community decide it's not feature-complete, and easily fork it away?


Let me just start by saying that, although I think that "internals" don't matter much when evaluating a robust and community-approved solution such as `devise`, recommending it does sound like "no one ever got fired for buying IBM". And while, as a user of a library, public API, documentation and ease of integration is way more important, as a contributor, quality of internals directly impacts my ability to quickly fix bugs and add features.


In retrospect, the state of the internals of [the http gem](https://github.com/httprb/http) was the reason that led me to develop [httpx](https://gitlab.com/honeyryderchuck/httpx).


Taking that into consideration, I'll just reinterpret Janko's claim as "all you guys there struggling to maintain legacy `devise`, keep calm and join the `rodauth` community".


Does he have a point though?


## Early design decisions


Most libraries start being developed with simple goals, and then evolve from it. Sometimes you want to "scratch a hitch". Sometimes you want to prove a point. Sometimes you want to play around with a new programming language, and reimplement something in it. Sometimes you start building something for yourself, and then you extract the "plumbing" and share it with the mob.

And sometimes, you're not happy with the existing tools, and you think that you can (and want to) do better.

Many popular libraries started that way. `sidekiq`, for example, positioned itself early-on as a "better Resque", long before it started charging for extra features.

And so did `devise`.

In the "BD" (Before Devise) era, there were other gems solving authentication in Rails: there was `acts_as_authenticatable`, there was `authlogic`, and others I can't remember well enough (2009's been a long time ago). They had a lot of things in common: a lot of intrusive configuration in Active Record (it's 2020 and it's still happening), required significant boilerplate, and lacked a lot of important features, defaults and extension points. Building authentication in 2009 was certainly not easy nor fun.


`devise` was developed inside [Plataformatec](https://www.plataformatec.com/), the brazilian company which gave the Rails core team 3 (or 4?) ex- or current core team members. Its author is José Valim (a huge ruby contributor at the time, before [Elixir](https://elixir-lang.org/)), and maintenance of the project has been mostly taken over by company employees (although it receives contributions from a large community). It was initially developed **for** Rails 3. In fact, I'd go as far as saying that `devise` was built to showcase what could be achieved with Rails 3, as it was the first popular demonstration of a rails engine.


The first time I tried it, it was a breath of fresh air: no handmade migration/model DSL setup (there was a generator for that); "pluggable" modules; default routes/controller/views to quickly test-drive authentication and signup; everything "just worked (tm)". It was so much better than the alternatives!


I always felt that `devise` was made to better integrate the then-standard form-based email/password authentication and signup in Rails 3. The main goals, it seemed to me, were:

* Quick integration in a rails 3 application (increase adoption);
* Provide better email/password account authentication defaults (commoditization);
* Become a rails engine success story (community);

All of the goals were successfully reached. It's one of those gems that always drops in the conversation when "how we'll do authentication" comes in the conversation for a new project. There is a big community using and fixing outstanding issues. It was so ubiquitous at one point, that there was a subset of the community who thought it should be added to `rails`, which fortunately never happened, as not all projects need authentication (not all projects need file uploads and a WYSIWYG text editor as well, by the way).


So why are people making a case against it? Why go with `rodauth` instead?

## Welcome to the desert of the real

![Desert of the real]({{ '/images/desert-real.gif' | prepend: site.baseurl }})


The vision for `devise` was fully accomplished by 2010: a no-friction email/password authentication add-on for Ruby on Rails. 

In hindsight, I don't think that anyone in 2009 could anticipate today's practices: microservices, SPAs, Mobile applications, cross-device platforms... and authentication also evolved: phone numbers instead of email accounts, multi-factor authentication, SMS tokens, JWTs, OTPs, OpenID, SAML, Yubikeys, Webauthn... and stakes are higher, especially since [Edward Snowden and PRISM proved that theoretically breaking into accounts isn't so theoretical after all](https://en.wikipedia.org/wiki/PRISM_%28surveillance_program%29).


Probably everyone was anticipating an ecosystem of "extensions" to flourish around the core library. And eventually, the "extensions" came to be, although the quality, stability and inter-operability of the bunch left a lot to be desired. And some of it had to do with the foundations `devise` built on top of.




A Rails engine is, in a nutshell, a way to add a "sub-app" to a rails app. It was a feature introduced in Rails 3 (a "patch" to circumvent a limitation of rails apps being singletons). You can add controllers, views, models, helpers, initializers, etc... to it, while not "polluting" your main app.

`devise` does all that and more, which works great for vanilla `devise` when extending yout application. But extending an engine is different. There isn't an agreed-upon way on how to extend another engine, and `devise` suffers from this by proxy. Go ahead and take a look at [the existing extensions](https://github.com/heartcombo/devise/wiki/Extensions). Here are some highlights:

* there are two `oauth2` integrations (none of them has been updated in the last 8 years), one does it through more controllers/models, the other just adds a new `devise module;
* there is an openid authenticatable extension, and then there are a lot of provider-specific (twitter, google, facebook) sign-in extensions, which implement OpenID or OAuth internally;
* there is a `devise-jwt` integration, surprisingly still being maintained (most of the extensions I click on this list haven't gotten an update in 5 years or more!), which lists a lot of caveats around session storage, mostly because `devise` defaults to using the session and doesn't support tranporting authentication information in an HTTP header without a few workarounds;


So, although it's easy to customize and extend `devise` from within your application, extending it through another library is a non-trivial exercise of rails engine-hackery, as it's not clear where your extension should go, which will make it end up all over the place.


(The state of `devise` extensions maintenance, at least judging by the ones advertised in the Wiki, doesn't look solid either.)

And then there's `rails` itself.

Looking at the [CHANGELOG](https://github.com/heartcombo/devise/blob/master/CHANGELOG.md), `rails` integration and upgrades have also been the main story since 2016. See the [strong_parameters integration in the README](https://github.com/heartcombo/devise#strong-parameters), or how `devise` major version bumps are usually associated with a new rails version support.


 It does seem that the main concern has been on stability rather than new features. Which I can relate, breaking other people's integration does suck. But is this by design? Is `devise` feature-complete? Did it achieve all its intended initial goals, that nothing is left beyond maintaining it for the community? Is the refactoring of its internals necessary to build new features? Would less logic in models and less AR callbacks help develop new features? I guess only the core maintenanceship can answer that.


But it does feel that `devise` is legacy software. 


## To infinity... and beyond!



![Buzz Lightyear]({{ '/images/to-infinity-and-beyond.jpg' | prepend: site.baseurl }})



OK, so all our tools are irreparably broken, it's a sad state of affairs, and the end is nigh. Should we all just migrate to `rodauth`?


The answer is a resounding "it depends...".

Boring, right?


`devise` is probably a legacy project, but guess what, so are a lot of rails apps out there. There's a sunk cost there, after one adopts, integrates and patches all of these tools together, to the point that, when it works, it might be just good enough, and although it sounds like "the grass is greener on the other side", the unknowns might be too many, making you stick with "the devil you know". So, until someone devises (pun intended) a tool to auto-migrates an application from `devise` to `rodauth`, thereby reducing the migration cost (there's an OSS idea there), I don't think that'll happen, regardless of internals.


However, if you're starting a project in 2020, you should definitely give `rodauth` a try. It states "security", "simplicity" and "flexibility" as design goals [right there at the beginning of the README](https://github.com/jeremyevans/rodauth#design-goals-). It still sees active development beyond plain maintenance, and supports all of those mentioned modern authentication features that should be a must in 2020. Its internals aren't perfect, but Janko is right, they are easier to understand and work with, so much so that I [made a library to build OAuth/OpenID providers with it](https://gitlab.com/honeyryderchuck/rodauth-oauth/).


It lacked in documentation and guides, so I'm definitely looking forward to those upcoming Rodauth articles!


What about you, how do you value a library's internals?
