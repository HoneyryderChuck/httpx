---
layout: post
title: 10 things a library needs
---

When I first started working on `httpx`, the mission was clear: make an easy-to-use open-source HTTP client that could support both legacy and future versions of the protocol, and all, or at least most, of its quirks.

However, developing a library which can potentially be used and improved by several people I'll never meet personally, all working on different setups and solving different problems and use-cases, it made me think about what would be the key aspects that could keep the level of community interest and participation high and levels of frustration low, while not causing me too much burden (remember, this is not my day job).

Having actively contributed to several open-source projects, I experienced the pain of creating reproducible scripts for my issues, building a project locally, having to reluctantly write in a project maintainer's preferred flavour or philosophy of the language, or getting significant contributions rejected for not getting the specifics of what the project goals were. A combination or all of these factors have contributed to the overall community decrease in interest, and in some cases eventual abandonment, by the community or the maintainer(s), of some of those projects I've contributed to.

(Disclaimer: I'm not saying that, by addressing all of these, your project will be immediately successful, but it will certainly be healthier).

Not having all the time in the world for maintaining `httpx`, or any other of my projects, I implemented a set of side-goals, with a focus on:

* Make project onboarding easy;
* User perspective first;
* Help the user communicate their issues with the right level of detail;
* Follow the standard style of the language (as unopinionated as possible);
* Set your main project goals, and stick to them;


Here's 10 things I did to accomplish these in `httpx`.


## 1. Test what the users will use.

As a veteran rubyist, I'm a big believer in TDD. However, that didn't help me much early on in the project's life, when I was still trying to figure out how to implement the internals of the library. Things changed so drastically, that if I'd TDD my early HTTP connection implementations, the effort in changing tests as I'd change the API would result in more redundant work, and instead of focusing on getting the right API, I'd be more concerned in reducing time spent on rewriting tests. For something which is private API.

So, it's clear that, although TDD is a valuable practice, one can't fall in the fallacy of "TDD all the things", rather one should test what one will really use, and make sure that these tests cover the internals in a way you'll feel pretty confident about the overall outcome.

My first "test" was actually a one-liner that you can still see in the project's main page:

```ruby
HTTPX.get("https://news.ycombinator.com")
```

This means that my approach was to use the `.get` call as my MVP, and after making it work (both for HTTP/1 and HTTP/2), I could start extending it to other HTTP verbs, different kinds of request bodies, etc., and make it work for all versions of the protocol and transport mode, support "100-continue" flows, and so on. So the bulk of `httpx` could be perceived on a first look as "integration tests", however the philosophy here is, if I can make it work for my tests, the user will most likely make it work as well.

Do make sure that your tests cover a significant amount of the code you wrote though, so make code coverage a variable of your CI builds.

## 2. Integration tests, predictable CI builds.

An HTTP client needs an HTTP server.

From my experience in maintaining or contributing to network-focused (also other HTTP) libraries, I identified that there were two kinds of test strategies for them: the ones that "mocked" network communication, and the ones that relied on the network. Both approaches have advantages, and both come with their own set of disadvantages:

You **mock the network because**:

* You use OS sockets, so your focus is not to them;
* You want to test only the particular things you implement (like encoding/decoding, error handling...);
* You want your tests to run quick;
* You want a predictable test build;

however, what you get is:

* Your code might not handle all network failure scenarios;
* Edgiest uses of your APIs will be very unreliable;
* Parsers might not handle incomplete payloads;
* Your tests might be quick, but they won't assure anyone in the big picture;

You **test with the network because**:

* You want to make sure that everything works end-to-end;
* You want to tackle most edge cases and failure scenarios;

however ,what you get is:

* [The network is not reliable](https://en.wikipedia.org/wiki/Fallacies_of_distributed_computing);
* You might get rate-limited, or worse, blocked by the peer you test against;
* Peer might be down (server down, DDoS from China...);
* Your CI will fail often, and you'll not take it seriously;


Mocking the network was never an option for `httpx`. I decided to go with the following method:

* `httpbin` to test most of HTTP features and quirks;
* `nghttp2.org` as a proxy to `httpbin` that could do HTTP/1, HTTP/2, server push and `h2c` negotiation.
* `www.sslproxies.org` to get an available HTTP or Connect proxy to `nghttp2.org`;
* `www.socks-proxy.net` with the same intent (but testing SOCKS proxy connections);

However, I knew that `nghttp2.org` could be down, DNS could fail, `httpbin` could change the endpoints, there could be no available proxy, proxies could timeout on handshake (when choosing random, sometimes they're on the other side of the world), and all sorts of possible combinations, that could make the CI builds fail well beyond 50% of the time due to one of these issues.

Alas, I wanted the CI builds to be reliable and reproducible. How could I do that and keep my integration tests? The answer I found was `docker`.

### docker to the rescue

A common use of `docker` setups is to expose service base images to avoid installing them locally, like databases. By adapting this approach, I could bake in all my external services in its own containers, link them through `docker-compose.yml` and run my tests inside the local docker bridge network.

This is how I came to the idea behind the CI pipeline which has been running the builds to this day. It took some time and tweaks to make it work reliably, but now my integration tests runs 99% of the time with no worries about network failures, peer availability or versioning. It was eventually extended to also deploy the project's main website. It's one the things I'm most proud of in the project.


P.S.: There are exceptions to the rule, of course. I couldn't test all HTTP features I wanted with `httpbin` (like `brotli` encoding), so I'm using available peers in the internet. And I'm also resorting to mocking to test the `DNS over HTTPS` feature, until I get some plan on how to use it as a service in this setup. On the other hand, I'm only testing the SSH tunneling feature when running inside docker, as it'd be otherwise pretty hard to set up. There's no free lunch.

Another nice benefit from this setup is: if contributors have `docker` and `docker-compose` installed, they can use the same setup to develop locally, which brings me to the next point...

## 3. Make development setup easy

One of the main reasons mentioned for not contributing to open-source projects, is that it takes a lot of effort to setup the development environment. For some, it comes with the job, i.e. [linux has a manual about its development tools](https://www.kernel.org/doc/html/latest/dev-tools/index.html).

Rails, to use an example from ruby, relies on a lot of services being installed and available for it to run its test suite, like DBs for `activerecord`, (`mysql`, `postgres`, ...), or `node`/`yarn`since webpacker became a thing (there are more). It [maintains a separate project](https://github.com/rails/rails-dev-box) to set up its development environment, which relies on vagrant (I assume this was made before docker became a thing). Without a doubt, Rails requires significant cognitive load from a potential contributor. Of course, as a "batteries included" project, there's not a lot Rails can do in that department.

Smaller projects, however, have their own set of requirements, i.e. a lot of them rely directly or indirectly on `gcc` being available to compile extensions, some require `git` or `bash` (even if they don't use `git` for more than `git ls`, blame `bundle gem` for that); some require network being available, even if they only calculate primes.

All of these things are potential hinderances to a first-time contributor, that might never come back after having tried and failed to contribute.

Always include a section in your wiki / manuals / documentation, describing how one can setup a development environment. Whenever possible, automate what the user has to do. Whenever necessary, explain the user why he needs it. [`httpx` provides such a section in the wiki](https://gitlab.com/honeyryderchuck/httpx/wikis/home#contributing).


## 4. Make style standard and hassle-free

If you're using `go`, this is not even a debate. Between its small set of features, limited (not limiting) API, and code not compiling until you `gofmt` format it, go projects seem to be programmed by the same guy.

Not ruby though. It's a very big language. `Object`, the base class of all ruby objects, has 56 instance methods. `Integer` adds 62 more. `Array` has 120 instance methods more. And that's just primitive types. A lot of them do the same thing. Ruby provides many ways to skin a cat, and everyone has a particular opinion about it. And they usually carry it to their particular and professional projects, being a point of friction when being onboarded into new projects, open source or not. Don't get me wrong, it's my language of choice, but it fails at preventing a lot of pointless discussions. I lost count of the times I've had contributions rejected because I used tabs instead of spaces, used `<<` instead of `concat`, used ternary operator instead of if/else...

So when I started created projects, I decided to do the exact same thing and implement my own flavor of ruby, until I realised, that's not how you build a community! So I went where other projects had gone before, to find some balance.

### rubocop

By now, all of you working with ruby have heard of `rubocop`. It's the de-facto ruby linter, and its features go beyond plain linting. It's default configuration follows the [ruby style guide](https://github.com/rubocop-hq/ruby-style-guide), and even if this is non-consensual (the ruby core team disputes this style guide as being truly standard), it's still a benchmark bringing some order to the chaos it is to develop ruby projects in a collaborative way.

And so I adopted it, and made a significant effort in not adding too many rules in my rubocop configs beyond the strictly necessary. By following the ruby style guide, no matter whether I agree with it personally, I'm reducing noise. And if contributors still have their preference, they can happily develop in their style, and then `rubocop -a` their way to a clean and mergeable change request I can work with.

## 5. Kill your dependencies

You might recognize this from [Mike perham's post of the same name](https://www.mikeperham.com/2016/02/09/kill-your-dependencies/). It's a cautious tale about the cost one incurs when adopting a dependency they don't own, and how hard it might be to pay that debt later. It's easier said than done (in some cases, building and maintaining a certain functionality might just be too big a burden compared to the publicly available alternative), but the own changelog of `sidekiq` is a story of the benefits one can potentially reap when going down this road.

As a former contributor to the `celluloid` ecosystem, I can still remember the disappointment I felt when `sidekiq` removed it as a core dependency, as I felt it was a disservice to the dependency that made celluloid viable in the first place.

Only as I matured, I realized what was going on: `celluloid` was holding `sidekiq` back, with its constant API breaking changes, lack of scope, subtle memory leaks and unstable features. Little by little, every code path dependent of a `celluloid` feature was rewritten, until the actor performing jobs was a glorified thread worker. The removal of this dependency was a great success, specially if you consider the current "abandonware" status of `celluloid`.

### HTTP parsers

`httpx` went through a similar discovery path: during its inception, both its HTTP/1 and HTTP/2 parser were external dependencies ([http_parser.rb](https://github.com/tmm1/http_parser.rb) and [http-2](https://github.com/igrigorik/http-2) respectively).

`http_parser.rb` was the first one to be removed. The decision to include it was because it seemed to be working fine as `httprb` parser, and I didn't want to write a parser from scratch. However, as I continued developing around its flaws, I've realized that 1) it was massively outdated (it was based on an old version of node's HTTP parser), 2) it didn't support all the features I wanted, 3) it was buggy, 4) there was no full parity between the C and Java HTTP parser (so I couldn't guarantee JRuby support), and 5) both `http_parser.rb` as the Java parser it was based one were barely maintained (the Java parser was pretty much abandonware by the time I started using it). By the time I was developing yet another workaround to a parser misfeature, I knew it was time to remove that dependency. So I built my own HTTP/1 parser from scratch. In pure ruby. supporting all the HTTP/1 quirks I wanted. And I never had to think about HTTP/1 parsing again.

(P.S.: `httprb` has since then dropped `http_parser.rb` due to the same reasons and the amount of issues it generated. pnly to replace it with another dependency called `http-parser`, an FFI binding for a more recent version of the same node HTTP parser. They still get parsing-related issues they can't easily fix by themselves.)

`http-2` should not be a dependency anymore by the time this post goes public. There are not a lot of HTTP/2 parsers available for ruby, and this pure ruby implementation has the benefit of being very readable and easily extensible, because duh!, it's ruby. I'd been an active contributor until recently, until activity in the main repo kind of stalled (one of the still open PRs in the project is mine, as of the publishing time of this article).

I started receiving bug reports which didn't seem to come from `httpx` itself. After some investigation, I came to the conclusion that the parser was the issue in some cases. Although a pretty interesting project, it never fully complied with the HTTP/2 spec, therefore I had to accept that `httpx` would probably break in different ways for a not-so-small amount of HTTP/2 compliant servers. Or do something about it.

So I decided to fork `http-2` and release it as `http-2-next` (no, I'm not writing an HTTP/2 parser from scratch, ahahahah). The result was a parser that passes all specs of the [`h2spec` suite](https://github.com/summerwind/h2spec). It's probably not gonna stop there, but it's pretty good for now.

So now I own own the runtime dependencies of `httpx` I started with, so a lot of worries I used to have about external dependencies (whether API breaks, bugs aren't fixed or project is abandoned) are not concerns anymore. 

## 6. Forwards compatibility

Not all dependencies are worth replacing, though.

Besides the already mentioned `rubocop`, `httpx` also depends on `minitest`, `simplecov` or `pry`, to name a few of the development/test dependencies I couldn't possibly maintain on my own. Some of the plugins come with their own set of dependencies (`brotli`, `http-cookie`, `http-form_data`, `faraday`...). Although valuable, they still bring with them the same risks mentioned in 5.: What if the API changes? What if there's a CVE reported? What if the project is abandoned?

But the main question is: how do I make sure that I stay compatible with newer versions of my dependencies? This is usually overlooked, as it's kind of expected of maintainers to keep track of latest changelogs and announcements, until something breaks in production, and suddenly quickfixing is your goal. Some of us might feel too overwhelmed. This might, dare I say, be another cause for maintainer burnout.

How can one make sure that all these changes won't catch up with the project? First, accept that you won't be able to control all of this. But in my experience, a strategy that works out pretty well is to limit your exposure to potential changes in a library's API. Thereby, you should limit the amount of features you are exposed to, and find a subset of APIs which have a higher probability of never being changed.

### minitest

Although it sells itself as a minimal test library, as in all things ruby, there's nothing minimal about it. It comes with the "test" and "spec" ways of writing your tests, it ships with [many assertion helpers](http://docs.seattlerb.org/minitest/Minitest/Assertions.html), and mocking is a very verbose task. So how do I limit my exposure?

Answer: just use `assert`.

Really, just use [assert](http://docs.seattlerb.org/minitest/Minitest/Assertions.html#method-i-assert). It powers all other (arguably) useless assert/refute methods polluting the namespace. Its API is simple enough to not ever change (boolean, error message). Its origin probably can be traced back to JUnit's `assertTrue`. All the cases you could fit any of the assert helpers can be deconstructed and stripped down to a call to `assert`. Update `minitest` in 5 years, and you're mostly likely guaranteed to have `assert` available with the same signature.

`assert` is all you need. So, define your own helper methods using `assert` under the hood, and own them.


(P.S.: I do exceptionally use other features, but this is not the rule).


Ruby itself is another example where you can keep it simple by using proven APIs that haven't changed in years. By limiting your exposure to experimental and controversial methods, you'll be ensuring stability of your project for years to come, as ruby upgrades (looking at you, lonely operator).


7. Help users give the right feedback


One of the hardest parts of maintaining a project is deciphering a user's error report.

A user of your library works in a completely different setup from you. Not only does he/she feel frustrated if your library doesn't work as expected, his/her patience will also be short. Most users will never report an issue, lest find your bug tracker. Therefore, the ones arriving at your inbox, are the ones who made it, and only a fraction of them will be able to articulate what went wrong in a meaningful way. How can you help the user give you a description of the problem you can actually work with? How can you avoid the ping-pong of question/answer that only makes the user more frustrated?

Github tried to solve this with templates. And most projects took them to a level of detail, that they've become a separate form no one has the time nor the desire to fill up. What version? What CPU? What browser? Templates can become just another filter limiting the pool of users who want to reach out to you.

Asking for a stacktrace from the get-go can be invaluable. Some users struggle, but most of them know how to get one. Asking for a reproducible script might help, but sometimes the error lies so deep in the logic of the user's application, that asking him to take it out of its context not only is an awful lot of work, it might even mask the error. 

Finding an error that happened to a remote user boils down to know 1) when the problem happened, and 2) what was the state of the world at the time. Stacktraces help with the former, but not with the latter.

`httpx` solves this with debug logs. Although a user-facing feature, you can also turn it on and define severity level by setting an environment variable, `HTTPX_DEBUG`. By asking the user to turn it on to "2" and rerun his example again, we'll get a detailed trace of HTTP request/response interactions, and in HTTP/2 case, frame traces. It's important to note that setting an environment variable is something a user can easily do, and the output is very valuable. In fact, this is how I found out that [`http-2` does not allow max frame size negotiation](https://gitlab.com/honeyryderchuck/httpx/issues/59#note_228923381).

It's also worth noting that `httpx` didn't invent the practice. verbose logs with different levels is also a feature of `ssh` or `curl`. The node community (afaik) also uses environment variables with library prefixes to turn on logs only for a subset of the dependencies.

8. Examples, tutorials, how-to's

Your library is useless if no one understands how to use it.

You can be pretty confident when announcing its release, and how much your piece of software will change the world, but if you don't post a code snippet with a disclaimer "insert this line to achieve greatness", you'll never get people to use it. In fact, if you don't actively use your library, you might never get that maybe people don't pick it up because of how complicated it is to use it. So use it, and write examples.

But don't write any examples. Write simple examples. Write exhaustive examples. Cover edge-cases. Write examples for things you would like to do, and if it doesn't work, write the code to make it work, and share the code as an example.

That's what I did to justify working on a `faraday` adapter; I wanted to be able to use the Stripe SDK gem using its faraday adapter (`stripe` has since moved away from `faraday`, oh well...). So I wrote an example of how it should look like. and then the feature came.

So now `httpx` has a README with examples, a wiki with examples, an `examples/` project folder, and also a cheatsheet!


9. Open for extension


This is ruby, and monkey-patching is king! If your objects aren't extensible, this is what'll happen: people will include module after module after overwritten method until it accomplishes the feature they want, barely (a sin I've been guilty of).

For all of the praises about its existence, metaprogramming can be a very sharp knife: wield it well, and you'll achieve great things, but the most likely outcome is that you'll cut a finger!

A problem ruby never figured out was how to make extending existing features and classes easy! Half of the times, I see most extensions corrupting the main module, often times not considering call order or whether there's already an extension extending that extended module, and then it's a big mess of wild proportions. Then ruby brought `Module#prepend`, and some (just some) sanity was brought into call orders.

Then refinements came. One of the most controversial features of ruby recently, not because of its potential, but because of its limitations. There are a wild array of scenarios where refinements works in non-obvious ways, or just won't work (try to refine a class method, or refine a module). Ruby just can't seem to solve this itself.

`httpx` implements a plugin pattern, where certain classes considered "core" can be extended in a sane way, without the core classes themselves being globally extended. Most of its features are implemented as plugins, actually. If this is familiar to you, it's because it's not a novel idea. I kind of stole this from both `sequel` and `roda`, both maintained by Jeremy Evans. Go read the source code, it's one of the finest examples of metaprogramming in ruby, and its best approach to the "open for extension, closed for modification" principle.


10. Backwards-compatibility is a feature!

A lot of people have heard about Linus Torvalds' email rants. He used to be quite aggressive when commenting on the quality of one's proposed changes to the linux source code, which was a consequence of his relentless drive for project stability. One of his most famous mantras was "never break user code". He was not wrong there.

In ruby, breaking upgrades are no news. Rails, its most famous gem, is the biggest outlier: every upgrade is guaranteed to break your application. Gems extending rails break accordingly. It's actually kind of amazing that rails managed to keep its popularity while constantly breaking the legs of its users. Chaos is a ladder.

The latest trend in the ruby world is to "stop supporting older versions of ruby", older versions being versions not officially supported anymore by the ruby core team. This trend not only ignores how ruby is distributed and used globally (not everyone uses rvm, mates), but in some (most?) cases, the API is already compatible with older versions, or would require minimal effort to do such.

But rails is the exception, not the rule. If you break compatibility constantly, you will alienate your user base. The ones that can abandon your project, will abandon your project. The ones that don't, they'll grunt. Python hard-broke compatibility from v2 to v3, and we're still talking about it after 10 years. The nodeJS ecosystem is defined by "always be breaking builds", to the point where this became an anecdote. The Facebook API changed so much since the first time I had to work with it (2010, perhaps), that I'd have to write everything from scratch if I had to go back to one of those projects. Googles discontinues developer products all the time. Angular broke compatibility from 1 to 2, and in a single blow delivered the frontend framework crown to React. None of these failed per-se (except Angular, maybe), but they generated a spiral of negativity that hovers around them, and no one's truly happy with it.

In my day job, we use Stripe for our payments processing. One of the small pleasures I have is to work with code around Stripe SDKs and APIs. Not only is their standard above everything else I've worked with, their approach to user compatibility is jaw-dropping: if you didn't upgrade your API since 2014, it still works as before. If you go to their documentation pages, you'll see code snippets for the API version you're with! They do go above and beyond to make you write the right code. The API upgrade strategy is also very easy to grasp. All endpoints can receive an API version header, which means you can migrate endpoint by endpoint to the latest version; by then, you just make the switch at the dashboard level, remove the API version headers, and you're migrated. An API like that is every developer's dream.


We also use AWS services in my day job. One of these days, I had to add a one-liner to an application running for months in a row on AWS lambda. The deploy failed: I was using a version of the `serverless-warmup-plugin`, a lambda to keep your lambdas warm, still using the node6.10 lambda configuration, and AWS is not supporting that node version anymore, so I had to spend some time to figure out how to upgrade that package.

Now pause for a second. Stripe. AWS. Both serve companies from all sizes. Both should not create friction with the companies working with them. Stripe is always accomodating our demands. AWS doesn't care. And it's not a question of money, I'd say.



## Conclusion

These 10 practices are not to be taken as commandments (I did mention when I couldn't follow them), but they help me maintaining a fairly wide and complex set of features with no budget. And that's the key aspect of this: Open Source projects are not just about writing code; in order to survive long term, they must excel at communication, collaboration, education. And that's the hardest task. 
