---
layout: post
title: RBS, duck-typing, meta-programming, and typing at httpx
keywords: RBS, type checking, duck typing, type syntax, runtime type checking
---

Ruby 3 is just around the corner, and with the recent release candidate, there's been some experimentation in the ruby community, along with the usual posts, comments and unavoidable rants.

Ruby 3 has 3 major features:

* JIT (since 2.6 in experimental mode)
* Ractors
* `Thread.scheduler`, aka autofibers
* Gradual typing (via [rbs](https://github.com/ruby/rbs))

*(aaaaand we're off by one)*

From the point of view of `httpx`, JIT is implicit, and Ractors won't do much for it (although I have to make sure if calls can be made across ractors). The autofibers feature seems to be interesting, and will be experimented with at some point.

But typing is where, IMO, a library like `httpx` can immediately get the most benefit from.

Typing is a very controversial topic in the Ruby community. Most of us started our journey as Ruby developers by running away from statically-typed languages (mostly Java), and fell in love with the quick feedback loop and fast prototyping that Ruby, and its lack of typing, enabled. Over time, we've crossed the ["Peak of inflated Expectations" all the way into the "Through of Disillusionnment"](https://en.wikipedia.org/wiki/Hype_cycle), where the monolithic codebases most of us find ourselves working in, fail in the most unpredictable ways due to runtime errors out of the happy path (`NoMethodError`s everywhere), and the act of simply updating external dependencies, let alone big refactorings, introduces so much risk, that most businesses prefer to halt upgrades indefinitely, until it's 2020 and you're still running Rails 2 in production.

Different cults rose around the one true solution for the conundrum, TDD being the most famous of them all. The belief was that, through industrious unit testing, functional testing, contract testing, load testing, E2E testing, migration testing, and some more, code will be resilient enough. At the cost of a ratio of 100 lines of test code per 1 line of actual code. But still, those pesky `NoMethodError`s keep meddling in our affairs.

So we've gone full-circle and typing will save us all from this disaster, just like it does all of those Java projects we ran away from years ago!

How can we have our cake, and eat it too? Matz & co. don't want to do Java. They want Ruby to be Ruby. How could Ruby be Ruby and have types? It took some time, but the result is here: [rbs was announced in July 2020](https://developer.squareup.com/blog/the-state-of-ruby-3-typing/). I won't bother you with details you can read in the linked articles, but in short, `rbs` is the "typing language format", whereas other tools (such as [https://github.com/soutaro/steep](https://github.com/soutaro/steep) or [sorbet, Stripe's type checker](https://sorbet.org/) will use it to perform type analysis. It caught my attention as soon as I got the guarantee that "duck typing" wasn't going to be left behind. So I started analysing whether I'd need it.

Does a ruby HTTP library benefit from typing? Based on my experience maintaining it, I guess one can make that argument. Public API is a particular example where some strictness can be beneficial both for the end user, and for the maintainer (example: troubleshooting a bug report, where one can ask the reporter to run the example with type check enabled). It can also work well as extra documentation, and can potentially help me avoid some weird bugs in certain edge cases which can't sadly be fully overlooked when writing a test.

But Ruby is a hard language to type. At any point, a random anonymous class can be created. An existing class can be modified. Also, I love "duck typing". Any typing I'll use has to take that into consideration. Also, there's the [coercion](https://blog.dnsimple.com/2016/12/ruby-coercion-protocols-part-1/) [protocols](https://blog.dnsimple.com/2017/01/ruby-coercion-protocols-part-2/), implicit and explicit. And then there are the ["common" interfaces](https://honeyryderchuck.gitlab.io/httpx/2019/10/30/enumerable-io.html). How can I stay true to Ruby, keep my developer happiness and not go full Java?


So I've decided to start integrating it. Not go full-types yet. At first as an expirement, to see whether I can "bend" type declarations to my will, while also finding limitations early in the process, and potentially contribute some feedback to the `rbs` team.

This is the chronicle of that journey.

## Start me up

`rbs` type definitions are done in a separate file than the source code being typed. The convention seems to be that, while your code goes to `lib/`, signatures go to `sig/` (this is at least what the core team has been doing with the stdlib gems). There's some controversy about maintaining signatures in separate files, but bear in mind that, if you care about backwards-compatibility, that this way, your code can also be run in ruby 2.x free of modifications. More on that later.

My first step was integrating type-checking in the project, and the most obvious process is the test suite. I've decided to not go full-blown static analyzer yet, so I'm using [plain `rbs` runtime signature checks](https://github.com/ruby/rbs/blob/master/docs/sigs.md#testing-signatures). This will instrument method calls and check whether they're compliant with the corresponding signature. This strategy only covers the code you run, or in this case, my tests run. You can activate it defining the following environment variables:

```bash
# the first if you're using bundler, the second because you need to load it
> export RUBYOPT='-rbundler/setup -rrbs/test/setup'
# raise an exception when there's a type check violation
> export RBS_TEST_RAISE=true
# control log verbosity of rbs
> export RBS_TEST_LOGLEVEL=error
# point where the definitions are. Also, require the stdlib modules whose interfaces you'll use (in my case, uri and json)
> export RBS_TEST_OPT='-Isig -ruri -rjson'
# which namespaces will be checked
> export RBS_TEST_TARGET='HTTPX*'
```

Then I picked up a class to type check, `HTTPX::Session` (do start with things your users use), and I [prototyped](https://github.com/ruby/rbs/blob/master/docs/stdlib.md#generating-prototypes) it:

```bash
> bundle exec rbs prototype runtime -rhttpx HTTPX::Session > sig/session.rbs
```

And then I started the "type - run tests - fix or refactor" loop.

## First impressions

My initial work was mostly aided by the [guides](https://github.com/ruby/rbs#guides), which are very sparse right now (hopefully there'll be some improvement there). It's a good starting point, nevertheless.

The syntax grammar is a bit more restrictive than plain ruby. For instance:

* interfaces must be prefixed with "_" (ex: `interface _Sweet`);
* composite types must start with lower-case (ex: `type candybar`);

I've learnt this the hard way, by interpreting the errors being raised while my tests were running, and scratching my head hard at the error messages.

Method signatures also have their quirks. For instance, optional types have a `?` suffix. For instance, `Integer?` means "an integer or nil". However, in parameters, it's the other way round, as the suffix `?` has a different meaning:

```ruby
# a(1) #=> valid
# a(nil) #=> valid
# a() #=> invalid
def a(?Integer size) -> Integer

# a() #=> now it's also valid
def a(?Integer? size) -> Integer

# and this return integer or nil
def a(?Integer? size) -> Integer?

# optional kwarg :size, can be integer or nil
def a(?size: Integer?) -> Integer
```

This was rather confusing at first, and again, error messages didn't help.

The "module function" method signatures are also confusing, as they again rely on the `?` suffix for `self`, which feels like the wrong token to convey meaning:

```ruby
# this is how you define a signature for
# a module function
# module Math
#   module_function
#   def sqrt
#     ...
def self?.sqrt: (Numeric) -> Numeric
```

After some time around these concepts, I started moving forward, and all started making more sense.

## Plateau of productivity

If you have some experience with type checking, you'll find a lot of the familiar concepts in `rbs`, albeit named differently. You get classes, interfaces, Unions, Intersections, Tuples, type and method alias, literals, Type variables, you name it.

Then you have a few "ruby-related" definitions, such as ivar definitions, singletons, mixins, visibility (only `public` and `private`, another nail in the `protected` coffin), Proc/block signatures, and a few more interesting concepts.

### Quacking like a type

Your first though will be to sign a method with class types. You'll find yourself looking at:

```ruby
def log(message)
  puts "log: #{message}"
end
```

and you'll define it as:

```ruby
def log: (String) -> void
```

However, in theory you'll want to log anything, aka its string representation. In "duck typing" lingo, "anything that quacks `#to_s`". So you'll define something like:

```ruby
interface Stringable:
  def to_s () -> String
end
def log: (Stringable) -> void
```

Bam, interfaces ftw. But hold on, this is a pretty common interface! Surely `rbs` figured that out already! Well, [yes it did](https://github.com/ruby/rbs/tree/master/stdlib/builtin)! It's not widely documented yet (let's hold for the official release), but there are common interfaces already defined for you, along with aliased types, which is what `rbs` uses in its own stdlib definitions. For instance, for our example above, [there's already a `_ToS` interface, and a `string` type joining the `_ToStr` interface (implements `#to_str`) with the `String` class](https://github.com/ruby/rbs/blob/master/stdlib/builtin/builtin.rbs):

```ruby
def log: (string) -> void
```

(There are analogous `int` and `real` types, and probably more will follow.)

This also helped me deal with my own definitions. For instance, `httpx` request methods receive a `uri` parameter. It's not very clear from the documentation, but besides a string, a `URI` object can also be passed as an argument. So my signature for a uri became:

```ruby
type uri = URI::HTTP | URI::HTTPS | string
```

Also, a lot of methods receive headers or options, which can be instances of `HTTPX::Headers` or `HTTPX::Options`, but also plain hashes and arrays. So I've also done this:

```ruby
# for headers
type headers_value = string | Array[string]
type headers_hash = Hash[String | Symbol, headers_value]
type headers = Headers | headers_hash
# for options
type options = Options | Hash[Symbol | String, untyped]
```

A combination of these strategies and judicious use of existing and custom interfaces allowed me to continue using "duck-typing".

### Learnings from go

`httpx` makes heavy use of common IO-related implicit interfaces. For instance, instances of classes defined under `lib/httpx/io` , and both request and response bodies, can be used with stdlib methods like `IO.select` or `IO.copy_stream`, by implementing `#read`, `#write` and/or `#to_io`.


These have all been implicit until now, but we can now make them explicit, by defining their interfaces. This would be very similar to how [go defines the Reader and Writer types](https://medium.com/@xeodou/understanding-golang-reader-writer-2c855eae0a94), both very simple, but with a lot of intrinsic meaning. go's structural typing have actually been referenced as an example of "duck-typing done right".

`rbs` didn't have them implemented like that though, [but work is underway](https://github.com/ruby/rbs/pull/428) to make them a reality come ruby 3.

Until then, `httpx` defines these interfaces internally.


## Under construction

![Under Construction]({{ '/images/under-construction.png' | prepend: site.baseurl }})

There's still work to be done, though. Ruby is not Java, and is certainly not Javascript, so one can't just get away with "importing" what these type systems can do; `rbs`-novel ways have to be figured out to express advanced meta-programming. For instance, what can we do with runtime-level module includes, or even anonymous classes? Any complete ruby type system will have to deal at some point with those.

Also, `rbs` runtime check module is very recent, so there are a lot of rough edges. I've been communicating some of my findings via issue, feature or merge requests to the `rbs` team. This is [my personal wishlist for Christmas 2020](https://github.com/ruby/rbs/issues/created_by/HoneyryderChuck).


### Better error messages

This is what happens if a function returns an object from the incorrect type:

```ruby
# rbs
def bytesize: () -> String
# then your code does smth:
buffer.bytesize

#RBS::Test::Tester::TypeError: TypeError: [HTTPX::Response::Body#bytesize] ReturnTypeError: expected `::string` but returns `3`
#    /rbs/lib/rbs/test/tester.rb:156:in `call'
#    /rbs/lib/rbs/test/observer.rb:8:in `notify'
#    /rbs/lib/rbs/test/hook.rb:146:in `bytesize__with__RBS_TEST_c7b28f'
#    test/response_test.rb:78:in `test_response_body_read'
```

This is when a definition for a type isn't found:

```ruby
def bytesize: () -> integer

# RuntimeError: Unknown name for expand_alias: integer
#     /rbs/lib/rbs/definition_builder.rb:1154:in `expand_alias'
#     /rbs/lib/rbs/test/type_check.rb:304:in `value'
#     /rbs/lib/rbs/test/type_check.rb:93:in `return'
#     /rbs/lib/rbs/test/type_check.rb:47:in `method_call'
#     /rbs/lib/rbs/test/type_check.rb:23:in `block in overloaded_call'
#     /rbs/lib/rbs/test/type_check.rb:22:in `map'
#     /rbs/lib/rbs/test/type_check.rb:22:in `overloaded_call'
#     /rbs/lib/rbs/test/tester.rb:150:in `call'
#     /rbs/lib/rbs/test/observer.rb:8:in `notify'
#     /rbs/lib/rbs/test/hook.rb:146:in `bytesize__with__RBS_TEST_0d7e38'
#     test/response_test.rb:78:in `test_response_body_read'
```

This is a syntax error in a signature definition:


```ruby
def bytesize: () - Integer

# parser.y:1380:in `on_error': parse error on value: #<RBS::Parser::LocatedValue:0x0000559907a84418 @location=#<RBS::Location:1860 @buffer=sig/response.rbs, @pos=971...972, source='-', start_line=44, start_column=23>, @value="-"> (tOPERATOR) (RBS::Parser::SyntaxError)
#         from (eval):3:in `_racc_do_parse_c'
#         from (eval):3:in `do_parse'
#         from parser.y:1110:in `parse_signature'
#         from /rbs/lib/rbs/environment_loader.rb:134:in `block in each_decl'
#         from /rbs/lib/rbs/environment_loader.rb:132:in `each'
#         from /rbs/lib/rbs/environment_loader.rb:132:in `each_decl'
#         from /rbs/lib/rbs/environment_loader.rb:147:in `load'
#         from /rbs/lib/rbs/environment.rb:130:in `block in from_loader'
#         from <internal:kernel>:90:in `tap'
#         from /rbs/lib/rbs/environment.rb:129:in `from_loader'
#         from /rbs/lib/rbs/test/setup.rb:41:in `<top (required)>'
#         from /usr/local/bundle/bin/bundle:in `require'
```

(the right definition is `def bytesize: () -> Integer`.)

What's wrong? Well, they're just plain exception backtraces. They give you enough information for you to know what and where went wrong (except in the second case, I have `grep` to find that keyword), but they're not user-friendly. A proper type-checker (even a runtime one) will have to do much better than that.

[Elm became renowned for the compiler errors UX](https://elm-lang.org/news/compiler-errors-for-humans), so much that [Rust made it a goal to reach its standard](https://blog.rust-lang.org/2016/08/10/Shape-of-errors-to-come.html). I know that it's still early days, but I think that `rbs` can get there too.

### Runtime require support

([Reported](https://github.com/ruby/rbs/issues/452))

Signatures are loaded at boot time, and break if the typed class/module isn't available yet. I had to patch this behaviour by loading all plugins ahead of time when `rbs` is available, which is obviously something I'd like to avoid.

### () -> void alias

([Reported](https://github.com/ruby/rbs/issues/423))

```
def do_that: () -> void
```

This'll be a very repeated, albeit pointless, method signature, which begs to be aliased into something shorter. In the spirit of "DRY", here's hoping the `rbs` team figures out a way to put all of these definnitions in one basket.

### Exceptions

As of the time of writing this post, there is not yet a way to declare that a function may raise an exception (or `throw` something). This is particularly important in methods that seem harmless, but may fail unexpectedly, such as  `TCPSocket#close`, which most of times just closes the socket, but may fail with an `Errno`, such as when sending the `FIN` packet fails. (is it `Errno::ECONNRESET`? Can't remember.)

Although not off the table, [it seems that such a feature won't make it to ruby 3.0](https://github.com/ruby/rbs/issues/421).

### Delegated methods

Ruby has a [few](https://ruby-doc.org/stdlib-2.5.1/libdoc/delegate/rdoc/Delegator.html) [ways](https://github.com/ruby/delegate) to [delegate](https://www.google.com/url?client=internal-element-cse&cx=011815814100681837392:wnccv6st5qk&q=https://ruby-doc.org/stdlib-2.5.1/libdoc/forwardable/rdoc/Forwardable.html&sa=U&ved=2ahUKEwjzxoS21cvsAhUEqXEKHRdSBN4QFjAAegQIBBAB&usg=AOvVaw03OhWMctaxQ40OPJolrZZk) methods to another object (usually an instance variable). This is a very common ruby idiom, and will need an easy way to signal these delagations.

Here's my "napkin" proposal:

```
class House
  @owner: Person

  define_from @owner
  # or
  define_from @owner, first_name, last_name
  ...
```

### method_missing

([Reported](https://github.com/ruby/rbs/issues/422))

How do you type a `method_missing` handler? It's a bit difficult, as we're in "shit happens" territory.

In most cases though, `method_missing` just dynamically codes delegation to instance variables based on runtime rules. So if using the technique described above could work (we should anyway define `respond_to_missing?` along, so we know what methods are accepted most of the times), I'd be a happy dev already.

### Subclasses

([I really wish this one makes it to ruby 3.0.](https://github.com/ruby/rbs/issues/448))

In `rbs`, one uses `singleton(MyClass)` to refer to the `MyClass` class. For example, if a method returns that class, the signature would be:

```
def get_class: () -> singleton(MyClass)
```

However, there's no way to declare a subclass of `MyClass`.

And this is just a small part of my biggest wish for `rbs`.

(`sorbet` implements this as `T.attached_class`).

### Dynamic Classes

[Probably the most difficult and the most ambitious of my "wish" features](https://github.com/ruby/rbs/issues/429), dynamic classes will be a challenge to type, once we (hopefully) get a proposal off the ground.

[httpx plugins rely on a heavy dose of meta-programming](https://gitlab.com/honeyryderchuck/httpx/-/blob/master/lib/httpx/session.rb#L221-251), with `HTTPX` core classes being extended in runtime in a contained way, using anonymized subclasses and mixins. I came up with a "clunky" way of typing them, but it's a bit limited.

If you think that such meta-programming is rare, I'll disclaim here that I didn't come up with this design myself, as I "borrowed" it from `sequel`, `roda`, `rodauth` and `shrine`, all of them very popular gems.

I'm not getting my hopes up with this one for the ruby 3.0 release though. I can recognize a difficult task when I see one.

## Quick wins

A question I did to myself while typing `httpx` was "what do you expect to gain now?". I mean, `rbs`, and typing in Ruby, is a seed, and it'll take months (years?), until the community reaps tangible benefits. The standard library will have to be fully typed (it's an ongoing effort as of the time of writing this post, and [they need your help](https://github.com/ruby/rbs/blob/master/docs/CONTRIBUTING.md)), the baseline / most common transitive libraries will have to as well, and one day, the "ripple effect" engulfs us in a sea of typed ruby. So why not wait it out?

I decided to go ahead and **type now**. Here's what I found out.

### Unknown bugs

Type checking evangelists always mention the necessity of having an ultra-comprehensive test suite in an untyped language, because you just don't know how your APIs are going to be (ab)used. I always thought there was some truth in this statement, and I build a pretty comprehensive test suite around `httpx` public APIs.

And yet, [a bug slipped through the cracks](https://gitlab.com/honeyryderchuck/httpx/-/commit/f0895f05d34113442fe84f4971e832c8284613d7): `HTTPX::Session#build_requests` was handling 2 or 3 arguments the same way, although the iteration block clearly only handled 2. Besides that, the second parameter should accept any object implementing `#each`. No unit test was ever written for this, so I never noticed.

Sure, both cases were probably best considered "edge cases", and to this day no one complained, so probably the APIs aren't being abused just yet (or everybody's "partying hard", if you know what I mean). Nevertheless, I'm left thinking how would such an error be described by a confused user of the library, and how typing just eliminated that conversation altogether.

### Interface segregation

Although APIs in Ruby are notoriously "bloated", that doesn't mean your library needs to be. And in fact, I make "keeping APIs frugal" an over-arching goal of the project, and forego the "magic human readable method fatigue", so pervasive in a lot of ruby libraries in general, HTTP clients in particular (looking at you, all libraries implementing a `response.ok?`).

Internally, particular implicit interfaces, such as the `Encoder/Decoder` concept, or the several IO "ducks", were designed with this goal in mind. And they mostly worked. However, while type-checking, [I found out that somehow the abstraction leaked](https://gitlab.com/honeyryderchuck/httpx/-/commit/b8c776abb27d1d1e06d7d9718747e4cf29341b86).

In the process of building the `:compression` plugins, I reused the `Encoder/Decoder` APIs internally, and during the implementation process, I let some accidental complexity leak. This can be seen by how the `compression/brotli` encoder turned out: `finish` and `close` methods were defined just because they were needed for the `gzip` and `deflate` compression plugins, which came first, and these didn't work around the `zlib` APIs.

While typing, it became clear that deferring to the `zlib` APIs wasn't right. So:

* compression plugins now implement the `_Deflater` and `_Inflater`, which implement only `inflate` and `deflate`;
* bookkeeping of the "inflating" process does not leak to the `Response` anymore;

### Clean out the trash

In the process of typing, I just found out that [some methods were needlessly defined](https://gitlab.com/honeyryderchuck/httpx/-/commit/d84aa2380866662413f01e6555cc8d8b4564afe9). In internal structures, there was no registered use of them. In more "public" data structures, they were just not adding any value, and were neither tested nor documented.

Given that the cost of maintaining unused code just raised (I now have to keep the implementation **and** the type signature), it made me think about whether it was worth keeping it.

So I just removed them altogether.

## Conclusion

`httpx` isn't fully typed yet (and neither is the standard library), and `rbs` still has a few rough edges. There's also not a lot of tooling around to make the experience even more productive (I've defined all the signatures in Sublime Text without a proper syntax highlighting plugin). There will probably be a few iterations until there's sufficient community buy-in and we start to see the compounding benefits paying off.

All that being said, I'm pretty satisfied with this experiment. I've extracted enough value from it to make it worthwhile, and can estimate further benefits of typing even more code.


## What about Sorbet?

Recently, [Brandur Leach from Stripe wrote a post](https://brandur.org/nanoglyphs/015-ruby-typing#ruby-typing) about `rbs` and Ruby 3.0, where he expresses some disappointment for [`sorbet`, Stripe's ruby type checker and type syntax language](https://sorbet.org/), not having been officially adopted for Ruby 3.

Diversity of opinions is a good thing, and I'll try my best to expose why I don't agree with some of the statements made in the post. And although I've only known `rbs` for the last 2/3 weeks, that's more experience than I have using `sorbet`, so feel free to correct me somewhere in the internet where this might get shared.

### .rbs files

>  Instead, developers specify type signatures in separate *.rbs files that mirror the declarations of a companion "*.rb" file...

> You can probably tell by now that I think this is a mistake of fairly colossal proportion...

The first issue the author has with `rbs` is defining the signatures in a separate file. It's a fair argument, as it's definitely a deviation from the more standard way of typing.

However, "separate signature files" is not a novelty: `sorbet` also supports `rbi` files, which is the recommended way to type a 3rd-party gem you don't control and has no type annotations (check [sorbet-typed](https://github.com/sorbet/sorbet-typed) for a collection of types for popular libraries). In the post, `*.d.ts` Typescript files are also mentioned, as a way to do the same for 3rd party Javascript code. And although this is suggested "only for code you don't control", there are other examples in the wild of holding signatures in two separate files. Like Java Interfaces. Or C header files. Both of them to serve different use cases from one another and from the "rbi/d.ts" case. Not using the examples as "good standards", just mentioning that `rbs` didn't invent it.

In the `rbs` case, keeping signatures separate allows for code to run in older versions of ruby. IF you've been following Matz's talks in the last years, you know he wants to avoid a Python 2-to-3 catastrophe. And personally, I'd like to avoid using a "transpiler" to distribute ruby 2 compatible code (a whole different discussion).

Considering this, is it wrong about keeping those signatures separate?

### Humans reading types

> And while static analysis is great, we shouldn’t forget that type signatures are for people too. Being able to see what the expected types of any particular variable or method while reading code is a huge boon for comprehension.

I guess every person will see this differently. While the author claims that people want to see the types, lots has been written about how type annotation verbosity makes code very hard to read (see [this](https://blog.jooq.org/2014/12/11/the-inconvenient-truth-about-dynamic-vs-static-typing/) or [this](https://instil.co/2019/10/17/static-vs-dynamic-types/)). I guess the truth lies in the middle, and maybe humans want to see type information when it's relevant to them.

And when is that? I'd argue that function type information gives the most value when one uses it, more than when one reads it; AKA the "Ctrl + Space" feature from most IDEs. And `rbs` will deliver on that, same as `sorbet` already does. Text editors will also have to catch up.

(it might make code harder to write, or make IDEs more needed. Or you just don't type.)

### python vs. ruby

> ...it’s disappointing to see it fall yet another step behind its sister language, Python. Along with better performance, much better documentation, a concurrency model, and an ever growing popularity disparity in Python’s favor, Python can now definitively boast the better type system, despite Ruby having had more than five years longer to think about its design and implementation.

I don't even know where to start. I do a lot of python daily as part of my day-job, and I don't get on what these bold claims are based on.

Regarding performance, it is known that both languages aren't very fast, that [ruby caught up with python in most synthetic benchmarks](https://benchmarksgame-team.pages.debian.net/benchmarksgame/fastest/yarv-python3.html) since 2.0, [that python in fact regressed from 2.7 to 3](https://mail.python.org/pipermail/speed/2016-November/000472.html), only having recovered recently.

Type hinting has been around since v3.5 (released in 2015). Due to the less "elastic" nature of python, is probably easier to understand. However, types aren't that widespread in that community: popular packages such as [requests](https://github.com/psf/requests/search?q=typing) or [boto3](https://github.com/boto/boto3/search?q=typing) still don't ship with type hinting (is it because signatures are done in the same file, and they still support older python versions?) Also, type hinting support for `async` functions is still limited (can't type async generators yet). We also prefer not to type at work.

(in 5 years, ruby might be here.)

Regarding documentation, I can't really provide numbers to back the claim. I guess one finds good examples in both ecosystems(?).

But the claim that got my attention the most was "... a concurrency model", linking to an `asyncio` page. I maintain both `asyncio` and standard python at work, and I can say that, if someone would move me away from the `asyncio` projects, I'd be a lot happier. Its completely different execution model and reliance on `async/await` keywords makes it look like a language within a language, and in fact it originated an ecosystem within an ecosystem, as networked libraries have to be duplicated for both IO models (`requests/aiohttp`, or `boto3/aioboto`, are some examples). [This article](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/) perfectly summarizes the problems with `asyncio`.

Sorry, nothing to do with types, but I had to take this out of my chest. Moving on.

### Type syntax

Although `sorbet` seems to fit Stripe's requirements in regards to the health of its codebase, it is verbose, and not so easy to read.

Compare `T.nilable(String)` to `String?`. Or `sig {params(name: String).returns(Integer)}` to `def meth: (String) -> Integer`.

It also doesn't seem to support coercion, or at least no one bothered yet to define what `rbs` calls the built-in types.

On the other hand, it already supports subclasses. And supports inlining (via `T.let`). And the UX of the static analyzer error messages seem very friendly to me. And their static analyzer is very fast, according to what I read.

### Stripe <3

I love Stripe (everyone who worked with me can attest my respect for what the company achieved), and I received `sorbet` positively;  it deserves credit for moving the type-checking discussion forward in the ruby community.

But even Brandur agrees that (quote) "As nice as Sorbet is, an officially endorsed solution that the entire community can rally around is far preferable to one being developed by a single company on the side".

When `rbs` eventually supports the `rbs` syntax, all the community will be better for it.
