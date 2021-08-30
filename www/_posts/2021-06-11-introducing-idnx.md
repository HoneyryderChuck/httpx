---
layout: post
title: Introducing idnx
keywords: new gem, idnx, IDNA, IDNA 2008, punycode, libidn2, windows, winAPI, mac OS, linux
---


I've just published the first version of [idnx](https://github.com/HoneyryderChuck/idnx) to Rubygems. `idnx` is a ruby gem which converts Internationalized Domain Names into Punycode. The gist of it is:

```ruby
require "idnx"

Idnx.to_punycode("bücher.de") #=> "xn--bcher-kva.de"
```

That's it! That's the announcement!

## Why yet another idn gem?

Let me spare you the work: here's the [ruby toolbox link](https://www.ruby-toolbox.com/search?q=idn). Yes, there have been many IDN-related gems over the years. Why yet another one?

While researching on how to better support IDN domain names for `httpx`, I asked myself, "what does cURL do?". After a session of "look at the source", I found out that cURL uses [libidn2](https://github.com/libidn/libidn2) in Unix environments, while it uses [the winAPI IdnToAscii](https://docs.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-idntoascii) on Windows.

After that, I searched for a ruby library that would support at least one of the above. To my surprise, I didn't find any. In fact, I found out that most of the idn-related gems from that ruby toolbox list haven't received much attention for years, and most of them use [libidn](https://www.gnu.org/software/libidn/), the predecessor of `libidn2`, which does not support IDNA 2008 Punycode protocol. Also, none of them supports Windows.

So I decided to roll my own, the cURL way: provide bindings for `libidn2`, while using Windows APIs for Windows, all via FFI, so that it'd transparently works with JRuby.

## Why no punycode-to-idn translation?

The short answer is: because I don't need it. If you do though, I'll welcome a Pull Request introducing it.

## Why doesn't ruby provide this?

I've previously [discussed in the ruby bugs board](https://bugs.ruby-lang.org/issues/17309) about the lack of support for punycode, and that breaking the "principle of least astonishment" when using standard library APIs like `uri` or `resolv`. I understand that doing so would require `ruby` to be dependent on `libidn2` (at least in Linux/BSD systems), and the core team has been pretty resistant when it comes to had more dependencies to the runtime. I understand that this'll never happen, unless someone makes a convincing argument that satisfies the core team.

Until then, you can use this gem, which, in case the day will come, can hopefully work as a template.

## Will I need idnx to use httpx?

No. `idnx` will be a "weak" dependency, i.e. you'll have to install it yourself, and `httpx` will hook on it if available. It'll otherwise fallback to a [pure ruby punycode implementation imported from another ruby gem](https://gitlab.com/honeyryderchuck/httpx/-/blob/master/lib/httpx/punycode.rb) (it doesn't support IDNA2008 however, so make sure to use `idnx` if you require it).


----

That's it. Happy hacking!