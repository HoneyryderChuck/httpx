---
layout: post
title: Falacies about HTTP
---

When I first started working on `httpx`, I wanted to support as many HTTP features and corner-cases as possible. Although I wasn't exhaustively devouring the RFCs looking for things to implement, I was rather hoping that my experience with and knowledge about different http tools (cURL, postman, different http libraries from different languages) could help me narrow them down.

My experience working in software development for product teams also taught me that most software developers aren't aware of these corner cases. In fact, they aren't even aware of the most basic rules regarding the network protocols they use daily, and in fact, many just don't care. When your goal is to get shit done before you go home to your family, these protocols are just a means to an end, and the commoditization of "decent-enough" abstractions around them resulted in the professional devaluation of its thorough knowledge.

Recently, the explosion of packages in software registries for many open source languages/platforms also led to the multiplication of packages which solve the same problem, but just a little bit differently from each other to justify its existence. [awesome-ruby](https://github.com/markets/awesome-ruby#http-clients-and-tools), a self-proclaimed curated list of ruby gems, lists 13 http clients as of the time of writing this article. And this list prefers to omit `net-http`, the http client available in the standard library (the fact that at least 13 alternatives exist for a library shipped in the standard library should already raise some eyebrows).

Some of these packages were probably created by the same developers mentioned above. And the desire to get shit done while ignoring the fundamentals of how the network and its protocols work, led to this state of mostly average implementations who have survived by cheer popularity or "application dependency ossification" (this is a term I just clammed together, meaning "components which use too many resources inefficiently but accomplish the task reasonably, and whose effort to rewrite is offset by the amount of money to keep this elephant running"). This list of falacies is for them.


1. 1 request - 1 response

One of the most spread-out axioms of HTTP is that it is a "request-response" protocol. And in a way, this might have been the way it was designed in the beginning: send a request, receive a response. However, things started getting more complicated.

First, redirects came along. A request would be thrown, a response would come back, but "oh crap!", it has status code 302, 301, the new "Location" is there, so let me send a new request to the new request. It could be quite a few "hops" (see how high level protocols tend to re-use concepts from lower level protocols) until we would get to our resource with a status code 2XX. What is the response in this case? 

But this is the simplest bending of "request-response". Then HTTP started being used to upload files. Quite good at it actually, but people started noticing that waiting for the whole request to be sent to then fail on an authentication failure was not a great use of the resources at our disposal. Along came: 100 Continue. In this variant, a Request would send the Headers frame with the "Expect: 100-continue" header, wait on a response from the server, and if this had status code 100, then the Body frame would be sent, and then we would get our final response. So, I count two responses for that interaction. Nevermind that a lot of servers don't implement it (cURL, for instance, sends the body frame if the server doesn't send a response after a few seconds, to circumvent this). 

Or take HTTP CONNECT tunnels: In order to send our desired request, we have to first send an HTTP Connect request, receive a successful response (tunnel established) then send our request and get our response. 

But one could argue that, for all of the examples above, usually there is a final desired response for a request. So what?

Well, along came HTTP/2 Push. And now, whenever you send a request, you might get N responses, where N - 1 is for potential follow-up requests.

All this to say that, although it looks like a "request-response" protocol, it is actually more complex than that.

Most client implementations choose not to implement these semantics, as they may perceive them as of little value for server-to-server communications, which is where the majority is used.

2. Write the request to socket, Read response from socket

As many of the examples described here, this is a legacy from the early days of TCP/IP, where TCP sockets were always preferred and less complex message interactions were privileged in favour of ease-of-use. As SMTP before it, so did the first versions of HTTP have these semantics built in: open socket, write the full request, receive the full response, close the socket, repeat for next.

However, things started getting complex really fast: HTML pages required multiple resources before being fully rendered. TCP handshake (and later, SSL/TLS) got so much of getting stuff to the end user, that "user hacks" were developed to limit the number of connections. A big chunk of the following revision of HTTP (1.1) revolved around re-using TCP connections (aka "Keep-Alive") and stream data to the end user (aka "chunked encoding"), improvements which were widely adopted by the browsers and improved things for us, browser users. HTTP proxies, the "Host" header, Alt-Svc, TLS SNI, all of them were created to help decrease and manage the number of open/close intermediate links.

Other things were proposed that were good in theory, but hard to deploy in practice. HTTP pipelining was the first attempt at getting multiple responses at once to the end user, but middlebox interference and net gains after request head-of-line blocking meant that this was never going to be a winning strategy, hence there were very few implementations of this feature, and browsers never adopted this widely.

And along came HTTP/2, and TPC-to-HTTP mapping was never the same. Multiple requests and responses multiplexed over the same TCP stream. Push Promises. And maybe the most important, connection coalescing: If you need to contact 2 hosts which share the same IP and share the same TLS certificate, you can now safely pipe them through the same TCP stream!

Many of these improvements have benefitted browsers first and foremost, and things have evolved to minimize the number of network interactions necessary to render an HTML page. HTTP/2 having decreased the number of TCP connections necessary, HTTP/3 will aim at decreasing the number of round-trips necessary. All of this without breaking request and response semantics.

Most of these things aren't as relevant when all you want is send a notification request to a third-party. Therefore, most client implementations choose not to implement most of these semantics. And most are fine implementing "open socket, write request, read response, close socket". 

Ruby's `net-http` by default closes the TCP socket after receiving the response (even sending the `Connection: close` header). It does implement keep-alive, but this requires a bit more set-up.

3. Network error is an error, HTTP error is just another response

HTTP status codes can be split into 4 groups:

* 100-199 (informational)
* 200-299 (successful)
* 300-399 (redirection)
* 400-499 (client errors)
* 500-599 (server errors)

In most server-to-server interactions, your code will aim at handling and processing "successful" responses. But in order for this to happen, checking the status code has to happen, in order to ensure that we are getting the expected payload.

In most cases, this check has to be explicit, as 400-599 responses aren't considered an error by clients, and end users have to recover themselves from it.

This is usually not the case for network-level errors. No matter whether the language implements errors as exceptions or return values, this is where network errors will be communicated. A 404 response is a different kind of error, from that perspective. But it is still an error.

This lack of consistency makes code very confusing to read and maintain. 429 and 424 error responses can be retried. 503 responses can be retried. DNS timed-out lookups too. All of these represent operations that can be retried after N seconds. All of them require different error handling schemes, depending of the programming language.

A very interesting solution to handle this can be found in python `requests` library: although network-level errors are bubbled up as exceptions, a 400-599 response can be forced to become an exception by calling `response.raise_for_status`. It's a relative trade-off to reach error consistency, and works well in practice.

However, this becomes a concern when supporting concurrent requests: if you recover from an exception, how do you know which request/response pair caused it? For this case, there's only one answer: prefer return errors than raising errors. Or raise exceptions only after you know whom to address them.

But one thing is clear: Network errors and HTTP errors should be handled at the same level.

4. You send headers, then you send data, then it's done

Earlier, we talked about the "open socket, write request, receive response, close socket" fallacy. But what is "write a request, receive a response" exactly?

HTTP requests and responses are often described as composed of headers and data frames (not to be confused with the HTTP/2 frames). Most of the examples and use cases show header being sent first, then data. This is one of HTTPs basic semantics: no data can be sent before sending headers (again, this might have come from SMTP, if I had to bet).

Things have become a bit more complicated than that. When HTTP started being used for more than just sending "hypertext", other frame sub-sets started showing up.

Along came multipart uploads. Based on MIME multipart messages, which were already being used to transfer non-text data over e-mail (SMTP, again), it created a format for encoding payload-specific information as headers within the HTTP data frame. Here's an example of an 3-file upload request:

```
# from https://stackoverflow.com/questions/913626/what-should-a-multipart-http-request-with-multiple-files-look-like
POST /cgi-bin/qtest HTTP/1.1
Host: aram
User-Agent: Mozilla/5.0 Gecko/2009042316 Firefox/3.0.10
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
Accept-Language: en-us,en;q=0.5
Accept-Encoding: gzip,deflate
Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7
Keep-Alive: 300
Connection: keep-alive
Referer: http://aram/~martind/banner.htm
Content-Type: multipart/form-data; boundary=----------287032381131322
Content-Length: 514

------------287032381131322
Content-Disposition: form-data; name="datafile1"; filename="r.gif"
Content-Type: image/gif

GIF87a.............,...........D..;
------------287032381131322
Content-Disposition: form-data; name="datafile2"; filename="g.gif"
Content-Type: image/gif

GIF87a.............,...........D..;
------------287032381131322
Content-Disposition: form-data; name="datafile3"; filename="b.gif"
Content-Type: image/gif

GIF87a.............,...........D..;
------------287032381131322--
```

Later, an addition to HTTP was made: Trailer headers. These are defined as headers which are sent by the peer **after** the data has been transmitted. Its main benefits are beyond the scope of this mention, but this fundamentally changed the expectation of what an HTTP message looks like: after all, headers can be transmitted before and after the data.


A lot of client implementations re-use an already existing HTTP parser. Others write their own. I've seen very few supporting trailer headers. I don't know of any, other than `httpx`, that does (and `httpx` only reliably supports it since ditching `http_parser.rb`, ruby bindings for an outdated version of the node HTTP parser). I also don't know of any in python. Go's `net/http` client supports it. 

5. HTTP Bytes are readable

This was particularly talked about during the SPDY days and the initial HTTP/2 draft, when it was decided that the new version was going to adopt binary framing. A lot of different stakeholders voiced their opposition. One of the main arguments was that HTTP plaintext-based framing was a key factor in its adoptions, debuggability and success, and losing this was going make HTTP more dependent of the main companies driving its development (the Googles of this planet).

They were talking about the "telnet my HTTP" days, where due to its text-based nature, it was possible to use the telnet to open a connection to port 80 and just type your request, headers/data, and see the response come in your terminal.

This hasn't been as black-and-white for many years. Due to better resource management, there are time constraints in terms of how much time that "telnet" connection will be kept open by the server (in many cases, if servers don't receive anything within 15 seconds, connection is terminated). HTTPS and encoding negotiation also made telnet-based debugging less efective.

Also, better tooling has showed up that has taken over this problem space: Wireshark has been able to debug HTTP/2 almost since day one, and will be able to debug HTTP/3 in no time.

To sum it up, this fallacy has been a remaining legacy from the old TCP/IP initial protocol days (surprise: you can also send SMTP messages over telnet!). No one should use telnet in 2019 (and I know for a fact that many network providers do). Better tooling has come up for this problem space. Network and system administrators of the 20 years past, just raise the bar.

A hole in a lot of http clients is that they don't provide introspection/debug logging, and one has to resort to network-level tools to inspect payload (`net-http` actually does, however). Maintainers, that should be an easy problem to fix.

6. Response is an IO stream

Some features introduced during the HTTP/1.1 days, like chunked encoding or the event stream API, introduced streaming capabilities to the protocol. This might have given the wrong idea that an HTTP connection was itself streamable, a concept that has "leaked" to a few client implementations.

Usually, in these interactions, You create an HTTP connection (and its inherent TCP/TLS connection), and there is an API that returns the next stream "chunk", after which you can perform some operation, and then loop to the beginning.

Besides the implicit socket-to-HTTP-connection here, which has been debunked a few fallacies ago, there's also the fact that "draining" the connection is only performed when acquiring the next chunk. If your client is not consuming payload as fast as possible, and the server keeps sending, many buffers along the way will be filled waiting for you to consume it. You might just caused "bufferbloat".

If there are timing constraints regarding network operations, there is no guarantee that you'll require the next chunk before the TCP connection itself times out and/or peer aborts. Most of these constraints can be controlled in a dev-only setup, and such interactions will result in "production-only" errors which can't be easily reproduced locally. Surprise, you might just have programmed a "slow client".

This is not to say that you should not react on data frames sent, but usually a callback-based approach is preferred and causes less unexpected behaviour, provided you keep your callbacks small and predictable. But whatever happens, always consume data from the inherent socket as soon as possible.

Besides, if you're using HTTP/2, there is no other chance: unless you can guarantee that there's only one socket for one HTTP/2 connection, you can't just read chunks from it. And even if you can, reading a data chunk involves so much ceremony (flow control, other streams, etc...) that you might as well end up regretting using it in the first place.

Client implementations that map a 1-to-1 relationship between socket and HTTP connection are able to provide such an API, but won't save you from the trouble. If connections hang from the server, time out, or you get blocked from accessing an origin, consider switching. 


7. Using HTTP as a transport "dumb pipe"

According to the OSI model, HTTP belongs to layer 7, to the so called application protocols. These are perceived as the higher-level interfaces which programs use to communicate among each other over the network. HTTP is actually a very feature-rich protocol, supporting feature like content-negotiation, caching, virtual hosting, cross-origin resource sharing, tunneling, load balancing, the list goes on. 

However, most client use HTTP as a dump pipe where data is sent and received, as if it were a plain TCP stream.

It is like that for many reasons, I'd say. First, there is a big incentive to use HTTP for all the things: bypassing firewalls! Second, implementing all the features of HTTP in a transparent way is rather hard. Some implementers even think that only richer user-agents like browsers would benefit from such features.

Even cURL is partially to blame: it is probably the most widely used and deployed HTTP client around, but its mission is to allow downloading content over many other protocols, where HTTP is just one of them. If you're doing:

```
> curl https://www.google.com
```

You're a) not negotiation payload compression; b) not checking if a cached version of the resource is still up-to-date. Can you do it with cURL? Yes. Do you have to be verbose to do it? Pretty much.

Most 3rd-party JSON API SDKs suffer from this issue, because the underlying library is not doing these things. The only reason why we're sending JSON over HTTP is because proxies have to be bypassed, but it is done in an inefficient way.  



## Conclusion

I could had a few more thoughts, but 7 sounds official, so I'll let that sink in.

Enjoy the week, y'all!
