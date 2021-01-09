---
layout: post
title: 2020, a year in review
---

2020 has been an incredibly changing year for humanity. Being thrown head-on into a pandemic no one was prepared to deal with, we were forced to clumsily speed-up the transition into the digital age, being more and more dependent of digital identity, online shopping, remote work, and more gifs and memes than we could ever imagine could exist in the ether. Commuting fatigue was replaced by "notifications" fatigue. For all of its faults, the internet backbone managed to assimilate annd withstand way more activity than naysayers ever thought it was prepared for, and I can tell for a fact that I experience way less interruptions in video calls in 2020 than I used to in 2018. We were unfortunately forced to keep in touch with our loved ones at a "safety distance", in most cases a video chat. I just hope that, whenever we're done with this state of affairs, we can retain the good habits, while swiftly eliminating the bad.

For me, 2020 represented a lot of change as well. I moved mid-pandemic into a new apartment with my family, I also switched jobs, which has been refreshing due to the change in context (from "online crowdfunding" into "digital identity"), but also very challenging, as this has been the first time I onboarded remotely. My son grew from a baby into a pre-toddler. I've done significantly less travel than I was planning with my wife due to the restrictions, and this meant that my wife was unable to see her family this year. But on a positive note, we're fine, we're healthy, and good things shall eventually come. I've also attended my first Rubyconf, mostly due to it being remote (even without the pandemic, doing a short trip to the US would not have been within my plans).

The switch to working from home also meant that I gained roughly 2 hours back, from commuting, and I've been using it in some personal activities, but also in my OSS projects. I've also restructured the way I do my "free" work, though: I now tend to do "short bursts" of activity, instead of draining my energy for hours, which has been my way of avoiding "OSS fatigue". While this means that I take more days polishing something, I can use the intervals to evaluate what I have to do, making the time I spend in it much more valuable. I also don't get a lot of issue reports, which means I don't get overwhelmed with comms, so I'm thankful I'm not yet at the stage where I need to care more about "governance" than developing the products.

While there was a lot going on in existing projects, I also found the time to bootstrap new ones.

## [httpx](https://gitlab.com/honeyryderchuck/httpx)

`httpx`, being my main ruby library, still gets a lot of attention: the last version released in 2019 was 0.6.3, while currently we're at 0.10.2 .

I've also been able to use it more for non-conventional workloads since I switched jobs, which was the reason some new features landed. This also means I'm doing more "dogfooding" than before.

### Stability

A lot of effort has been put into increasing the test coverage. Although it's impractical to aim at 100% coverage (some error handling in network is almost impossible to replicate reliably), it's close to 97%, which is pretty good.

I've also decreased the number of `:nocov:` annotations, thanks to a [feature from simplecov I learned at work, .collate](https://github.com/simplecov-ruby/simplecov#merging-test-runs-under-different-execution-environments); previously, I was only showing real coverage numbers for the most recent supported version of ruby; now, I merge the coverage results of running tests with all supported ruby versions, which gives me more assurance about the workarounds and fixes I maintain for older rubies. I've seen copied this technique to all of my projects except one (more about that later).

The test environment setup became more complex, with an HTTP (squid) and SOCKS (3proxy) to test the `:proxy` plugins against, an HTTPS DNS server to test the `DoH` features, and a second deployment of `nghttp2`, to test `Alt-Svc` and HTTP/2 connection coalescing. Fortunately, docker-compose manages this complexity just fine.

This also meant I found some really nasty bugs in code not covered by tests, so I definitely found a correlation about test coverage and overall stability. I can therefore safely say that the latest versions are the most stable.

I can't really compare with other ruby http libraries in this regard though, as I don't know of any which makes coverage a priority, or a visible metric.

### Performance

Significant work was done for the 0.8 release to improve and diminish the frequency of IO operations, which greatly reduced the CPU consumption and put the performance of single requests on par with other ruby http libraries. This boost was a great lesson about the trade-offs and real impact of system calls and IO operations, and I'll take this lesson into future projects.

### Features

`httpx` gained some new plugins this year:

* the `:expect` plugin, for handling `Expect: 100-continue` scenarios reliably and retries when the server doesn't support it, a la cURL (this plugin might be even loaded by default in a future breaking version);
* the `:stream` plugin, for handling streaming responses from a server, where we might want do deal with the payloads in chunks, rather than buffering them.
* the `:rate_limiter` plugins, which supports easy retrying on server which rate-limit you;

Also, [sending multiple requests with a body](https://honeyryderchuck.gitlab.io/httpx/wiki/Make-Requests#multiple-requests) (such as POST requests) became not only possible, but also easier, due to several improvements done on the core requests API.

### Forwards compatibility

As soon as ruby 3 preview was available, I've made sure that `httpx` runs it.

I've also planned to prepare for its release, and looked at `rbs` in order to improve the stability of the library by using type checking. While typing the code, several bugs and missing features have been reported and contributed upstream, and it was refreshing to contribute to a project I believe will be critical in the years to come.

The runtime type checking layer, which runs alongside the tests, helped fix some critical issues as well.

Since v0.10.0, `httpx` ships with `rbs` type signatures. 

The tests also run in "GC auto compact" mode.

### Going forward

A lot has been happening in `httpx`; nevetheless, there's still work to do. Several people asked for support in popular introspection and test libraries (`webmock`, for example). `httpx` not being as popular as other projects, it won't benefit from "community" contributions as much as other libraries, creating a common (in OSS) "chicken or egg" situation (can't use `httpx` because it doesn't support my favourite mocking library, won't integrate my favourite mocking library because don't use `httpx`). The good news is, I've been personally feeling the need of those, so I've started the working of [integrating with both `webmock` and `ddtrace`, datadog's SDK](https://honeyryderchuck.gitlab.io/httpx/wiki/home.html#adapters). Hopefully these examples will provide a good enough template for the next potential contributoor.

A reason I believe less people contribute to `httpx`, is the project being hosted in gitlab rather than github; and although mirroring is enabled and I am open to contributions via Github, github has since "broken" gitlab's mirroring, so I'll have to wait before having it available in github again (TL;DR: Github disabled Basic Auth for API authentication, so now it's on Gitlab to provide an alternative Authentication strategy).

Overall, I'd like to achieve two ambitious goals: reduce all dependencies not maintained by me to 0; and support ALPN negotiation in Jruby to enable HTTP/2 (which on the other hand means a different TLS stack). I'd also like to start thinking about what a potential v1 would look like, but I'm not expecting it to become a reality this year.


## [http-2-next](https://gitlab.com/honeyryderchuck/http-2-next)

`http-2-next` was [my fork of the `http-2` gem](https://github.com/igrigorik/http-2) from igvita. I did it because I wanted complete h2spec compliance, along with missing HTTP/2 extension efforts such as the `ORIGIN` frame, and I felt that the owner didn't have much interest in these initiatives, and or time for the project itself. I did it, knowing that if the situation would change, I could come back to it, so I didn't make significant API changes. But 1 year has passed, and it's clear that the upstream project isn't actively maintained anymore, so I'm happy about my decision.


### Stability

After a few initial bumps (including an issue that involved a report to the AWS Cloudfront team), H2spec compliance was achieved, so I can actually tell for a fact that `http-2-next` is the only complete implementation of the HTTP/2 protocol. These specs are run as part of the CI, so future changes don't break the status quo.

**EDIT**: It was brought to my attention that [protocol-http2](https://github.com/socketry/protocol-http2) also ships with an h2spec-compliant HTTP/2 parser.

### Features

Support for the `ORIGIN` frame was added. It was a bittersweet endeavour though, as, such as the `ALTSVC` frame before it, no known public server seems to use it yet, so it can't even be tested. Bummer.

### Improvements

Support for more recent rubies, including preparing for ruby 3 and RBS signatures, has been added. Overall, this library tries to use more performant ruby APIs than its parent project, although, to be fair, it'll never compare to a C parser such as `nghttpx`. 

### Going forward

Improving the performance will still be the main task here. The library is mostly "feature complete" (i.e. it implements the spec), so we can move from "make it work" and "make it work correctly" into "make it work fast".

## [rodauth-oauth](https://gitlab.com/honeyryderchuck/rodauth-oauth)

One of the last projects I was involved in before switching jobs, was an OAuth provider. As that product was a Rails shop, the POC was done using `doorkeeper`, a Rails-only solution. Nevertheless, when the time came to think about on how to build the actual solution, I thought that it would be a good opportunity to showcase `rodauth` to my colleagues, and all the features it provided.

But sadly, OAuth wasn't one of them.

Being proficient with the `rodauth` codebase, having contributed previously, I though "screw it, I'll do it myself".

And so `rodauth-oauth` was born.

Initially, my goal was to implement the strictly necessary to support the project I was starting. I was wary that the managers all wanted to stick with `rails`, so I wanted to be sure it would integrate well. Fortunately, at the same time, [Janko Marohnic started working on rodauth-rails](https://github.com/janko/rodauth-rails), and I immediately started incorporating it in the test suite.

After the initial version, my focus was to research OAuth as a protocol, and implement what I thought could be a feature rich annd security-focused OAuth provider toolkit. Being built on the `roda-sequel` stack, I knew I had a solid foundation. So I started, RFC by RFC, implementing them one by one. PKCE, check. Implicit Grant, optionally, check. JWT tokens, check.

And then, I thought that it was a good idea to support OIDC on top of it as well. Check.

I'm pretty happy that, although I'm not using it all in production, I was able to research so much about OAuth and able to implement it, and what came out was a very simple DSL that enables it all, courtesy of `rodauth`. Part of its success is exactly this foundation, and Jeremy Evans, the maintainer of not only `rodauth`, but also `roda` and `sequel`, deserves part of the credit.

Sadly, the project I was supposed to build this for got cancelled due to the pandemic.

### Going forward

Having implemented most, if not all of the OAuth 2.0 family of RFCs, and being compliant with most of the recommendation of the OAuth 2.1 RFC, it's safe to say that there's not much more to do (unless you believe OAuth 3 will ever be more than vaporware).

I think I'll do some community support for now. People have been using and reporting issues, and being this a young project, some rough edges will have to be dealt with. But it being thoroughly tested (97% coverage) certainly helps.

I'd also like to type-check it with `rbs` at some point. Don't know exactly how, due to the dynamic nature of `rodauth` plugins, though.

## [rodauth-select-account](https://gitlab.com/honeyryderchuck/rodauth-select-account)

While developing the OIDC layer of `rodauth-oauth`, I realized that `rodauth` doesn't support a "change account" feature for logged in users, the way you can have multiple accounts logged-in to Google, and be able to switch across them. I'm not sure if it's a limitation of `rodauth` or just not that big of a use-case, as I don't know of any other gem supporting it.

So I decided to roll my own.

`rodauth-select-account` is definitely less complex than my other gems, and that shows in lines of code, and even in test coverage (99%).

But it does the job right, and comes with a bootstrap-enabled GUI to show what you can do with it.

### Going forward

I don't have manny plans for it, as I consider this gem feature-complete. So, beyond the mandatory maintenance, I think that the only thing left to do is be able to run it against `rodauth` tests to ensure it doesn't break other plugins.

## [ruby-netsnmp](https://github.com/swisscom/ruby-netsnmp)

My oldest OSS project, still under the Github orga from the company I developed it for, it's been the one requiring less of my attention over the years, due to the stability of the feature set it provides.

In fact, there was no commit between Nov 2019 and Sep 2020.

Ruby 3 brings significant kwargs breaking changes, which `ruby-netsnmp` uses abundantly (not the greatest of decisions), which, surprise, broke its usage.

And so the obligatory maintenances fixes came, along with the RBS signatures, until...

### Travis

By now, everyone following Github projects is tired of the "move from Travis to Github Actions" pull-request parade. It's the biggest exodus since the Hebrew slaves were fred from Egypt. Which brings me to the other "not the greatest of decisions" moment.

Having started the project in 2016, Github was still a relatively friendly OSS bazaar, and all projects I followed used this "Travis" platform to integrate CI in their projects. The UI was a bit janky, but it was dynamic, and a big departure from those Jenkins pages everyone was accostumed to. And the builds ran "in the cloud", which was not as widespread at the time, and those YAMLs were, well, still YAML. But most important of all, it was free for OSS projects.

I didn't see any reason not to do as my peers were, and when I proposed my manager to go "open source", I requested him to put me in touch with the Swisscom team managing the Github orga, and I asked them to create a repo for myself.

It was the last project I primarily hosted at Github. Since then, I've become a Gitlab power user, as I liked having private repositories to develop ideas in quiet before deciding whether to release them (Github caught up with private repos recently). I found out Gitlab CI and was sold: being vertically integrated, I didn't need to integrate with a 3rd-party CI platform. In fact, I've become so happy and productive with my gitlab flow, that I recommend it whenever I can. And given everything that's happened, it was a decision that aged well: Github being acquired by Microsoft and the biggest Gitlab signup party ever had, Github contracts with dubious agencies, the `youtube-dl` story...

And now, "Travis".

"Travis" has been bought by Idera, a software corporate company, which proceeded to laying off a lot of its staff. There was a feeling in the air that greed would take the platform away from open source. And finally, it was announced: [Travis would no longer provide free minutes to OSS projects](https://blog.travis-ci.com/oss-announcement). And so it began.

Far away in my Gitlab-sponsored throne, I laughed and scorned at the mob running on top of each other, crying in despair, asking the community for a hand and a PR to migrate their CIs to either "Circle CI", showing that they didn't learn the lesson, or "Github Actions", the recently released Gitlab CI clone.

And then it came to me. "Oh, crap, ruby-netsnmp".

Given that it's not up to me to move this project to Gitlab this time, I released a howl of resignation and moved on reluctantly.

### Github Actions

Coming from Gitlab CI, Github Actions is confusing, and rather limited. You have workflows, you gotta eat more of that YAML, you have this "step" thing, which "runs" this other thing, which is usually a 3rd-party versioned... "setup-r"? "prepare-r"? Dunno what to call it. Is there one of those for docker? Humm, apparently docker is already there...

It was a bit hard, but I managed to replicate the multi ruby version matrix I use to run tests.

And then I wanted to merge coverage results. Except, you can't. So, you have this "workflow_run" tag to run workflows after a state transition in a previous workflow, but somehow, that doesn't work for matrix tasks.

So while I did manage to take a page from all those PRs and migrate the tests, I still don't have a worthy coverage report to show for.

[I asked for help in a community forum, since Github makes it so hard to ask for help or questions](https://github.community/t/workflow-run-not-triggering-for-matrix-job/150204). Still waiting for a reply though. 

All in all, Github Actions seems to fit application flows better (test-build-deploy) than libraries. So yeah, stick to Gitlab if you don't want to dea so much with the "side-stuff".

### Going forward

So, although I'd like to, moving out of Github is not an option. So I'll keep reluctantly ranting from time to time, until the situation improves.

A thing I've been working in is [a MIB parser]|(https://github.com/swisscom/ruby-netsnmp/pull/39), as I'd like to do some experimentation at home using SNMP, and the lack of MIB support is blocking me. This was the main unfinished business I left before leaving the company, so someone there will be happy to see this one sorted out soon.



That's it folks. Stay healthy!














