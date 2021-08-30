---
layout: post
title: Ruby 2 features, and why I avoid keyword arguments
keywords: ruby 2, keyword arguments, inconsistencies
---

Some politician one day said "may you live in interesting times". Recently, it was announced that the next ruby release will be the long-awaited [next major ruby version, ruby 3](https://github.com/ruby/ruby/commit/21c62fb670b1646c5051a46d29081523cd782f11). That's pretty interesting, if you ask me.

As the day approaches, it's a good time to take a look at the last years, and reminisce on how ruby evolved. There have been good times, and there have been bad times. I can single-out the 1.8-1.9 transition as the worst time; the several buggy releases until it stabilized with 1.9.3, a part of the community pressuring for removal of the Global Interpreter Lock and getting frustrated when it was not, the API breaking changes...  yes, it was faster, but people forget that it actually took years (2 to 3) until the community started ditching ruby 1.8.7 . True, not a Python 2-to-3 schism, but it fractured the community in a way never seen since.

Ruby 2 was when this all changed: upgrades broke less, performance steadily increased, several garbage collector improvements... ruby became adult. Matz stressed several times how important was not to break existing ruby code. Companies out of the start-up spectrum adopted ruby more, as they perceived it as a reliable platform. Releases generated less controversy.

With the exception of new language additions.

I can't remember the last addition to the language that didn't generate any controversy. From the lonely operator (`.&`), to refinements, all the way up to the recent pattern-matching syntax, every new language feature stirred up debate, opinions and sometimes resentment. Some features have been received so negatively, that they've been removed altogether (such as the "pipeline" operator).

The ruby community and the ruby core team still don't have a way to propose and refine language changes, and the latter prefers to release them with the "experimental" tag. Interest hasn't developed in adopting standards from other programming languages (such as python PEPs, or rust RFCs), as the core team, or Matz, are still wary of the consequences of "designed by committee" hell, but the current approach of "let me propose new feature and wait for Matz's approval, and then let's release and see what people think" hasn't worked in ruby's favour lately. Here's hoping to a solution coming up for this conundrum someday.

Of course, "controversial" means that some people will love them, some people will hate them. Although it kinda feels that way, I'm not against all changes, I did like some of them. This is my blog after all, so expect opinions of my own, and if you don't like it, feel free to comment about it (perhaps constructively), somewhere in the internet.  I'll also write in the future about features I love that came from the ruby 2 series. But that won't be today. Today is about a feature I've grown to abandon.

Today is about keyword arguments.

## Where they came from

Keyword arguments were introduced in Ruby 2.0.0.p0, so they're ruby 2 OG. They're a result of an old usage pattern in ruby applications, which was to pass a hash of options as the last argument of a method (shout out [extract_options!](https://apidock.com/rails/v6.0.0/Array/extract_options%21)). So, pre-2.0.0, you'd have something like this:

```ruby
def foo(foo, opts={})
  if opts[:bar]
  # ...
  # ...
end

foo(1, bar: "sometimes you eat the bar")
```

Usage of this method signature pattern was widespread, and things generally worked.

There were a few drawbacks of such an approach though, such as proliferation of short-lived empty hashes (GC pressure), lack of strictness (for   example, what happens if I pass `foo(1, bar: false)`? is `foo(1, bar: nil)` the same as `foo(1)`? How should that be handled?), and primitives abuse (let's face it, Hashes are to ruby what the Swiss Army Knife is to MacGyver; Sharp tools).

The core team decided to address this usage pattern in the language. They took a look at existing approaches, most notably python keyword arguments, and proposed a more ruby-ish syntax.

And on Christmas day 2013, keyword arguments were born.

So, where did it go wrong?

### Lack of support for hash-rocket

One of the additions in ruby 1.9 was JSON-like hash declarations. This was, and still is, a very controversial addition to the language. Not because it does not look good or because it's fundamentally flawed, but mostly because its limitations do not allow the deprecation of the hash-rocket syntax. You see, JSON-like hash declarations only allow having symbols as keys:

```ruby
{ a: 1 } #=> key is :a
{ "a" => 1 } #=> key is "a", and you can't write it any other way
{ a => 1 } #=> key is whatever the variable holds. must also use hash rocket
```

So you get many ways to slice the pie. How can you convince your teammates? How can you spend more time producing, and less time debating what is the correct way to write hashes in ruby?

For keyword arguments, the core team went up a notch and decided to only support the JSON-like hash.

```ruby
kwargs = { bar: "bar" }
foo(1, **kwargs) # works
kwargs = { :bar => "bar" }
foo(1, **kwargs) # still works, but hard to reconcile with signature
kwargs = { :bar => "bar", :n => 2 }
foo(1, **kwargs) #=> ArgumentError (unknown keyword: :n)
kwargs = { :bar => "bar", "n" => 2 }
foo(1, **kwargs) # ArgumentError (wrong number of arguments (given 2, expected 1; required keyword: bar))
```

This is confusing: you can create hashes in two ways, for certain type of keys there's only one way, but then keyword arguments only support the other way, but they're not hashes, so they're you go... I can't even...

[The `httprb` team has refused pull requests in the past changing all internal hashes from rocket to JSON-like and introducing keyword arguments](https://github.com/httprb/http/pull/342), because they don't see the benefits in maintaining this inconsistency. They avoided keyword arguments.

### It's a hash, it's not a hash

The 3rd example above shows what one loses when adopting keyword arguments: suddenly, an options "bucket" can't be passed down without filtering it, as all keys have to be declared in the keyword arguments signature.


There is some syntactic sugar to enable this, though:

```ruby
def foo(foo, bar: , **remaining)
  # ...
```

However this approach creates an extra hash; although `bar` is a local variable, `remaining` is an hash. A new hash. And more hashes, more objects, more GC pressure.

The pre-2.0.0 hash-options syntax has the advantage of passing the same reference downwards, and you can always optimize default arguments. You can improve resource utilization by avoiding keyword arguments.


### Performance

Due to some of the things talked about earlier, particularly around keyword splats (the `**remaining` above), performance of keyword arguments can be much slower when compared to the alternative in some cases.

Take the following example:

```ruby
# with keyword arguments
def foo(foo, bar: nil)
  puts bar
end
# without keyword arguments
def foo(foo, opts = {})
  puts opts[:bar]
end
```

Using keyword arguments here is faster than the alternative: arguments aren't contained in an internal structure (at least in more recent versions), and there is no hash lookup cost to incur.

However, in production, you're probably doing more of this:

```ruby
# with keyword arguments
def foo(foo, bar: nil, **args) # or **
  puts bar
end
```

And here, a new hash has to be allocated for every method call.

So if you think you're incurring the maintenance cost for some performance benefit, you might be looking at the wrong feature. You can solve it by avoiding keyword arguments.

Don't think I came up with this by myself, [Jeremy Evans, of sequel and roda, mentioned this in a very enlightening Rubyconf Keynote](https://youtu.be/RuGZCcEL2F8?t=634). He also avoids keyword arguments, and came up with [a strategy to keep allocations down while using old-school options hash](https://github.com/jeremyevans/sequel/blob/065c085c5e4b0ebb3b2cb7a1abf8425dd192106f/lib/sequel/database/transactions.rb#L31).

### It's not quite like python keyword arguments

Although they're not everyone's cup of tea for pythonistas, keyword arguments make more sense there. Let me give you an example:

```python
# given this function
def foo(foo, bar):
    pass
#  you can call it like this
foo(1, 2)
foo(bar=2, foo=1)
```

This is a contrived example, but you get the idea: you can refer to the arguments positionally, or doing it out-of-order if you so prefer.

In ruby-land, keyword arguments were a solution for the specific usage pattern already described above, and they will probably never become what we see in python. But the flexibility and consistency of the keyword arguments in python is one of the 2 features I'd welcome in ruby (the other being `import`. Still not a fan of global namespace).

### That ruby 2.7 upgrade

If you upgraded your gems or applications to ruby 2.7, you already know what I'm talking about.

If you don't, the TL;DR is: Ruby 2.7 deprecates converting hashes to keyword arguments on method calls, and all the historical inconsistencies that came along ([official TD;DR here](https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/)), and will discontinue it in ruby 3.

The reasoning behind it is sound, of course. But 7 years have passed. A lot of code has been written and deployed to production since then, significant chunks of it using keyword arguments. Some of this code is silenty failing, some of it worked around the issues. And now all of that code is emitting those pesky warnings, telling you about the deprecation. All of that open source code you don't control, some of it abandoned by its original author.

[Github recently upgraded to ruby 2.7](https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/), and singled out the keyword arguments deprecation as the main challenge/pain. "We had to fix over 11k warnings", they say. A lot of it in external libraries, some of which github provided patches for, some of which were already abandoned and github had to find a replacement for.

I do understand the benefit of making your code ready for ruby 3, or the advertised performance benefits, but I can't help to think how business looks at the amount of resource spent yak-shaving and not delivering customer value.

This could all have been avoid, had github and its external dependencies avoided using keyword arguments.

### YAGNI

Keyword arguments are a niche feature: they're a language-level construct to solve the problem of "how can I pass an optional bucket of options" to a certain workflow. They were never meant to fully replace positional arguments. They were meant to enhance them (although I've been making the point that they don't fully accomplish the goal).

However, what you got was a sub-culture that only uses keyword arguments. Why? Because they can. Did you ever see a one-argument method, where that one argument is a keyword argument? Congratulations, one of your co-workers belongs to that sub-culture.

I've seen this happen for Active Job declarations, which support keyword argument signatures. Sidekiq Workers don't, but Active Job takes care of the conversion: it converts hashes of options, symbolizes all keys, and passes them at keyword arguments. More hashes, more objects, more GC pressure.

Do keyword argument-only method signatures get more maintainable? I guess you'll get different answers from different people. But the benefit of it isn't clear.


## Conclusion

![Keep calm]({{ '/images/keep-calm-and-use-kwargs.jpg' | prepend: site.baseurl }})

Reality check time: keyword arguments aren't going anywhere any time soon. They're a language feature now. Some people like it, inconsistencies notwithstanding. And let's face it, where's the value in removing keyword arguments from your projects? Code is running. Don't change it! I know I didn't. [ruby-netsnmp, a gem I maintain, still uses keyword arguments](https://github.com/swisscom/ruby-netsnmp/blob/master/lib/netsnmp/client.rb#L26), and that ain't gonna change, not by my hand at least.

But if you're authoring a new gem in 2020, or writing new code in the application you work at daily, do consider the advice: avoid keyword arguments. Your future upgrading self will thank you.
