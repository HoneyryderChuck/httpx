---
layout: post
title: Ruby 2 features, and why I really like refinements
keywords: ruby 2, refinements, extensions
---

This is my second entry in a series of thought-pieces around features and enhancements in the ruby 2 series, initiated in the Christmas of 2013, and now scheduled for termination in the Christmas of 2020, when ruby 3 is expected to be released. It's supposed to be about the good, the bad and the ugly. It's not to be read as "preachy", although you're definitely entitled not to like what I write, to what I just say "that's just my opinion", and "I totally respect that you have a different one".

But after "beating my stick" on keyword arguments, now it's time to talk about one of the things I've grown to like and find very useful in ruby.

Today I'm going to talk about refinements.

## Origin story

So, in its teenage years, ruby was bitten by a spider... superpowers yada-yada... and then Active Support.

The origins of refinements can be traced to Active Support, one of the components of Ruby on Rails. And Active Support is the origin story of our super-villain of today: the monkey-patch.

![Monkey Patch]({{ '/images/monkeypatch.jpeg' | prepend: site.baseurl }})

Ruby gives you many superpowers. The power to add methods to existing core classes, such as arrays. The power to change core class methods, such as `Integer#+`, if you so desire. It's part of what is known as meta-programming. It's that flexible. But that flexibility has a price. For instance, if you use an external dependency, code you don't own, that might rely on the original behaviour of that `Integer#+`, its usage might be compromised with your monkey-patch.

Of course, ruby being ruby, you can always "monkey-patch" that external dependency code you don't own. But this can happen more than once, and once the monkey-patch ball grows, you realized you were better off before you went down that monkey-patching road. With great power comes great (single-)responsibility(-principle).

Active Support is a [big ball of monkey patching in ruby core classes](https://github.com/rails/rails/tree/master/activesupport/lib/active_support/core_ext), and then some more. All of these "core extensions" have legimitate usage within Rails code, so they weren't born out of nothing; they're an early example of a philosophical approach, of individuals taking over and extending a language and its concepts. In Rails-speak, this is also called the "freedom patch". It's a catchy name.

The gospel of Active Support grew along with ruby. The community adopted it and made its word its own. Gems included Active Support as a dependency, where they used a very small subset (sometimes only one function) of these patches. Some maintainers understood the trade-off of carrying this huge dependency forward. Some of them copied the relevant code snipped to its codebase, and conditionally loaded it when Active Support wasn't around (a long time ago, [Sidekiq used this approach](https://github.com/mperham/sidekiq/blob/2-x/lib/sidekiq/core_ext.rb)). Others suggested porting these patches to ruby itself. One notable example is `Symbol#to_proc` (once upon a time, writing `array.map(&:to_s)` was only possible with Active Support).

Monkey-patched core classes became bloated; it caused many subtle errors, and made projects hard to maintain. Gems monkey-patching the same method, when loaded together, completely broke.

The core team took notice, and aimed at proposing a way to enhance core classes in a safe manner. Refinements were released in ruby 2.0.0 .

## How

Refinements are a way to scope patches. Want to change `Integer#+`? Then do it without changing `Integer#+` everywhere else:


```ruby
module Plus
  refine Integer do
    def +(b)
      "#{self}+#{b}"
    end
  end
end

module Refined
  using Plus
  1 + 2 #=> "1+2"
end
1 + 2 #=> 3
```


## Release

When refinements were annnounced, [they weren't a flagship feature](https://www.ruby-lang.org/en/news/2013/02/24/ruby-2-0-0-p0-is-released/). In fact, the core team wasn't even sure whether it would be well received, and marked the feature as "experimental". And reception was certainly cold: the rails core team refused to rewrite Active Support using refinements; the JRuby core team strongly disapproved them, and considered not implementing refinements at all (JRuby has since then implemented refinements, and although Active Support is still refinement-free, usage of refinements can already be found in Rails).

There were real limitations in refinements since the beginnning, and although some have been addressed, some are still there (can't refine a class with class methods, only instance methods), but the negative backlash from ruby thought-leaders at its inception seems to have slowed experimenting with it, to the point that, around 2015/2016, a lot of "Nobody is using refinements" blog posts started popping up. In fact, it's still perceived as some sot of "black sheep" feature, only there to be scorned at.

I was once in that bandwagon. And then, slowly, the sowing gave way to reaping.

## Signs

In time, refinement-based gems started popping up. The first example coming into my attention was [xorcist](https://github.com/fny/xorcist), which refined the String class with the `#xor` byte stream operation. Then I noticed that [sequel](https://github.com/jeremyevans/sequel/blob/4e6dfaea238a63058ddf7a1ebe5fe406aa0c4df6/lib/sequel/extensions/core_refinements.rb) also began adopting refinements.

At some point, I started considering using refinements for a specific need I had: forwards-compatibility.

## Loving the alien

Something started happening around the release of ruby 2.2. I don't remember how it started, but suddenly, prominent ruby gems started dropping support for EOL rubies. The idea seemed to be, following the same maintenance policy as the ruby core team would drive adoption of more modern rubies.

Upgrades don't happen like that, for several reasons. Stability is still the most appreciated property of running software, and upgrades introduce risk. They also introduce benefits and hence should obviously happen, but when they do, they happen gradually, in order to reduce that risk.

Deprecating "old rubies" interfered with this strategy; suddenly, you're stuck between keeping your legacy code forever and ignore the CVE reports, or do a mass-dependency upgrade and spend months in QA. You know what businesses will do when they are presented with the options: if it ain't broke, don't fix it. [Just ask Mislav](https://twitter.com/mislav/status/1301508711005982726), or think why you're still maintaining a ruby 2.2 monolith at work. It's 2020, and the most used ruby version in production is version 2.3 .

Me, I prefer "planned obsolence". It works for Apple. Is your code littered with `string.freeze` calls, and you want the ruby 2.3 frozen string literal feature? Do it. Older rubies will still run the code, just their memory usage will not be optimal. Users will eventually notice and upgrade. Want to compact memory before forking? Go ahead. Code still runs if there's no `GC.compact`. I know, it'll go slower. Just don't break user code.

Want to use new APIs? Well, there used to be [backports](https://github.com/marcandre/backports). But now you have something better: Refinements.

## Backwards compatibility is forwards compatibility

In life, you must pick your battles.

In all the gems I maintain, I start with these two goals: set a minimum ruby version and alwayw support it (aspirational goal); also, I want to use new APIs whenever it makes sense.

How do I choose the minimum version? It depends. [ruby-netsnmp supports 2.1 and higher](https://github.com/swisscom/ruby-netsnmp#features-1) because I didn't manage to make it work with 2.0 at the time using "celluloid"; [httpx supports 2.1 and higher](https://gitlab.com/honeyryderchuck/httpx#supported-rubies) because the HTTP/2 parser lib sets 2.1 as its baseline, and although I maintain my fork of it, there hasn't been a strong reason to change this; [rodauth-oauth supports 2.3 and higher](https://gitlab.com/honeyryderchuck/rodauth-oauth/#ruby-support-policy) mostly because it started in 2020, so I don't need to go way back; also, 2.3 is still the most used ruby version, so I want to encourage adoption.

In all of them, I use refinements. I use the `xorcist` refinement in `ruby-netsmp`; [in rodauth-oauth, I refine core classes in order to use methods widely used in more modern ruby versions](https://gitlab.com/honeyryderchuck/rodauth-oauth/-/blob/master/lib/rodauth/features/oauth.rb#L20).

But the refinement usage I like the most, is the one from [httpx](https://gitlab.com/honeyryderchuck/httpx/-/blob/master/lib/httpx/extensions.rb). There, not only I implement slighty-less performant versions of modern methods to keep seamless support for older rubies, I also enhance the concept of `URI`, and add the concept of `origin` of `authority`. The implementation is very simple, so here it is:

```ruby
refine URI::Generic do
  def authority
    port_string = port == default_port ? nil : ":#{port}"
    "#{host}#{port_string}"
  end

  def origin
    "#{scheme}://#{authority}"
  end

  # for the URI("https://www.google.com/search")
  # "https://www.google.com" is the origin
  # "www.google.com" is the authority
end
```

Why do I like it? Because the concept of what a URI ["origin"](https://httpwg.org/specs/rfc7230.html#rfc.section.2.7.1) or ["authority"](https://tools.ietf.org/id/draft-abarth-origin-03.html#rfc.section.2) are, is well defined and written about in RFCs. The HTTP specs are filled with references to a server "authority" or "origin". Everybody heard and used the HTTP ":authority" header (formerly "Host" header), or CORS (the O stands for "Origin").

And yet, the ruby URI library doesn't implement them. Yet. Should it? Maybe. I could definitely contribute this to ruby. Maybe I will. But I still have to support older rubies. So my refinements ain't going nowhere. This refinement is the present's forwards compatibility and the future's backwards compatibility. It keeps my code consistent. And by making it a refinement, I don't risk exposing it to and breaking user code.

This is refinements at its finest.

## Conclusion

Refinements are a great way to express your individuality and perception of the world, while not shoveling that perception of the world onto your users; a safe way for you to experiment; and a great way to keep backwards compatibility, and by extension, your end users happy.

Unfortunately they will never accomplish its main goal, which was to "fix" Active Support. But maybe Active Support was never meant to be fixed, and that's all right. Refinements have to keep moving forward, and so do we. Hopefully away from Active Support.
