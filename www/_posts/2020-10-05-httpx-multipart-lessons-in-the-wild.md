---
layout: post
title: HTTPX multipart plugin, lessons in the wild
---

Some say that open source maintainers should "dogfood" their own software, in order to "feel the pain" of its users, and apply their lessons learned "from the trenches" in order to improve it. Given that no one else is better positioned to make improvements big and small, it's hard to dispute against this.

But in the real world, OS maintainers work in companies where they not always get to decide about software tools, processes or coding style. Sometimes it's hard to justify using your "part-time" project when there's already something else in-place which "does the job".

Also, the feature set might just be too wide for one maintainers to exercise it all. To name an example, `cURL` has over 9000 command-line options and supports 42 protocols (numbers completely made up, but probably not too far off from the real ones), I honestly do not believe [bagder](https://twitter.com/bagder) has had a chance to use them all in production.

`httpx` is an HTTP client. In ruby, there are over 9000 HTTP client libraries (numbers completely made up, but probably not too far off from the real ones), and 10 more will be released by the time you finish reading this post. An HTTP client is a well-known commodity, and a pretty large subset of HTTP is implemented widely.  So it's pretty hard, however good and useful you client is, to convince your co-workers to ditch their tool of choice (even something as bad as `httparty`), because "it works", "I've used it for years", "it has over 9000 stars on Github" (numbers completely made up, but probably not too far off from the real ones), are good arguments when you're just downloading some JSON from a server.

*(The popularity argument is pretty prevalent in the ruby community, which probably means that no one bothers to read the source, and I'm just not that popular. Gotta probably work on that.)*

So you shrug, you move the wheel forward and patiently wait for your turn, and roll your eyes while you write some code using `rest-client`, and life goes on. Sorry `httpx` users, not there yet!

And then, an opportunity hits.

## Media files

Where I work, we handle a lot of media files, such as photos and videos. Users upload photos and videos from their devices to our servers, where we pass them around across a number of services in order to verify the user's identity. Pretty cool stuff. Downloading, uploading, transferring, happens a lot.

Some tasks often involve uploading data in bulk. And although uploading photos is not a big deal, uploading videos is, as some information about what happens in the video must also be transferred, as extra metadata, in a widely known encoding format.

And for that, the `multipart/form-data` media type is used. 

## multipart/form-data

[RFC7578](https://tools.ietf.org/html/rfc7578) describes the `multipart/form-data` media type. In layman's terms, this media type is what powers file upload buttons from HTML forms. For instance, in your typical login form with an email and a password:

```html
<form method="post" action="/login">
  <input type="text" name="email" placeholder="Your email..." />
  <input type="password" name="password" placeholder="Your password..." />
  <input type="submit" value="Login" />
</form>
```

The browser will submit a POST request to the server, where the form data is sent to the server in an encoding called `application/x-www-form-urlencoded`. This encoding is one giant string, where (huge simplication disclaimer) key/value pairs are encoded with an `"="` between them, and all pair are then concatenated with the `"&"` as the character separator:

```http
POST /login HTTP/1.1
....
Content-Type: application/x-www-form-urlencoded
....

email=foo@bar.com&password=password
```

This works great for text input, but what if you want to support binary data, such as in the scenario of, uh, uploading a profile picture? That's where `multipart/form-data` comes to the rescue:

```html
<form method="post" enctype=multipart/form-data action="/upload-picture">
  <input type="file" name="file" />
  <input type=text" name="description" placeholder="Describe your picture..." />
  <input type="submit" name="submit" value="Upload" />
</form>
```

The browser will send the request while encoding the data a bit differently:

```http
POST /upload-picture HTTP/1.1
....
Content-Type: multipart/form-data; boundary=--abc123--
....

--abc123-- 
Content-Disposition: form-data; name="file"; filename="in-the-shower.jpg"
Content-Type: image/jpeg

{RANDOM-BINARY-GIBBERISH}
--abc123--
Content-Disposition: form-data; name="description"

Me coming out of the shower
```

This is a simplified explanation of what kind of "magic" happens when you submit forms in the web. In fact, these two types of form submissions are the only ones which user agents are **required** to implement.

So where does `httpx` fit?

## Multiple content types

As I explained above, in my company's product, a user uploads videos to our servers from their devices, along with the metadata, and that all is done via a single multipart request. Our "videos" services know how to process these requests.

Recently, during an integration of video support in a product my team owns, it was necessary to test a certain scalability scenario, and we needed some "dummy" videos on our test servers. Which meant, uploading them using multipart requests.

Although there are certain restrictions regarding adding new dependencies to some projects, this is a general-purpose script, so you can do what you want. Still, my first approach was adapting the same script we use for uploading photos using `rest-client`, widely used within the company. But I couldn't make it work, as these multipart requests are too elaborate for `rest-client`: it involves 1 text value, 2 json-encoded values, and the video file itself. (if you know how to do this using `rest-client`, do let me know).

My next attempt was trying to use `cURL`. But even `cURL` didn't make such a scenario obvious (I've since learned about the `";type=magic/string"` thing, don't know if it's applicable to my use-case yet though).

And then I thought, "why don't I just use `httpx`"?

## The httpx solution: the good

Building this using `httpx` and its `multipart` plugin was more straightforward than I thought:


```ruby
require "httpx"

session = HTTPX.plugin(:multipart)
response = session.post("https://mycompanytestsite.com/videos", form: {
  metadata1: HTTP::Part.new(JSON.encode(foo: "bar"), content_type: "application/json"),
  metadata2: HTTP::Part.new(JSON.encode(ping: "pong"), content_type: "application/json"),
  video: HTTP::File.new("path/to/file", content_type: "video/mp4")
})
# 200 OK ....
```

It just works!

### http-form_data: the secret sauce

`httpx` doesn't actually encode the multipart body request. Credit for that part of the "magic" above goes to the [http/form_data](https://github.com/httprb/form_data) gem, maintained by the `httprb` org.

(It's also [used by httprb](https://github.com/httprb/http/wiki/Passing-Parameters#file-uploads-via-form-data), so the example above could also have been written with it.)

Great! So now I can apply the example script above to handle multiple videos, multiplex them using HTTP/2 (the "killer feature" of `httpx`), and I'm done, right?

Not so fast.

## The httpx solution: the bad (but not that bad, really)

My first attempt at uploding multiple videos ended up being something like this:

```ruby
require "httpx"

session = HTTPX.plugin(:multipart)
               .plugin(:persistent) # gonna upload to the same server, might as well

opts = {
  metadata1: HTTP::Part.new(
    JSON.encode(foo: "bar"), 
    content_type: "application/json"
  ),
  metadata2: HTTP::Part.new(
    JSON.encode(ping: "pong"),
    content_type: "application/json"
  ),
}

Dir["path/to/videos"].each do |video_path|
  response = session.post(
    "https://mycompanytestsite.com/videos",
    form: opts.merge(
      video: HTTP::File.new(
        video_path,
        content_type: "video/mp4"
      )
    )
  )
  response.raise_for_status
end
# first request: 200 OK ....
# second: 400 Bad Request ... smth smth encoding
```

400... Bad Request. Well, that was unexpected!

I must admit I flipped seeing that error. So I started troubleshooting. Uploading the second file standalone worked as expected. Then I thought the `persistent` plugin was the issue, and I removed it as well. Still didn't worked. And then I thought that something about the HTTP/2 layer was wrong, and as the best positioned person to take a look at the issue, I started agressively `puts`ing the HTTP/2 parser, getting some PTSD about the worst bug reproductions I'd had since starting the project. "This is going to be a long week", I thought. And then my co-worker reminded me that we didn't have a week.

So I called it a day, and started thinking about going back to square 1 and doing some spaghetti with `rest-client`.

I went to sleep, I woke up, and then it suddenly came to me. `http-form_data` was the reason.

## The httpx solution: the ugly (or just, not so pretty)

The issue here was sharing the parameters, and how `http-form_data` dealt with them. Recently, it added streaming support, by implementing the Readable API in the parts; this enables partial reads on large files, so that programs don't need to fully load a file in memory and potentially run out of memory. And this "Readable" API was implemented for all parts, including non-file parts.

The Readable API requires an implementation of `def read(num_bytes, buffer = nil)`, and by definition, once you've read it all, you don't read it from the beginning again.

This means that parts could only be read once, before returning `nil`. So in the example above, `metadata1` and `metadata2` payloads for the second request were empty. And that caused the encoding issues leading to the "400 Bad Request".

This was rather unfortunate. However, the fix was simple: share nothing!

```ruby
require "http"

session = HTTPX.plugin(:multipart)
               .plugin(:persistent) # gonna upload to the same server, might as well

Dir["path/to/videos"].each do |video_path|
  response = session.post("https://mycompanytestsite.com/videos", form: {
    metadata1: HTTP::Part.new(JSON.encode(foo: "bar"), content_type: "application/json"),
    metadata2: HTTP::Part.new(JSON.encode(ping: "pong"), content_type: "application/json"),
    video: HTTP::File.new(video_path, content_type: "video/mp4")
  })
  response.raise_for_status
end
# 200 OK ....
# 200 OK Again!
# Another 200 OK!
# ...
```

And just like that, I could move on to the next thing!

## Conclusion

This was a humbling learning experience. Writing complex HTTP requests using `httpx` did prove to be as simple and straightforward as I'd hope it would be. However, the "dogfooding" session proved that when it doesn't work, it's not very obvious about the why. I spent an entire afternoon plotting on why the hell that second request was failing, and I'm the maintainer. How would another user react? File an issue? Write a blog post about the "sad state of httpx multipart requests"? Or just abandon it and write it in `net/http` instead?

So I decided to do something about it. Firstly, I updated the wiki from the `multipart` plugin, [warning users **not to** share request state across requests](https://gitlab.com/honeyryderchuck/httpx/-/wikis/Multipart-Uploads#things-to-consider-when-using-the-plugin).

Second, I'll probably be replacing `http-form_data` at some point in the future. As a dependency should, it served me quite well, and allowed me to iterate quickly and concentrate on other parts of the project. I've even contributed to it. But at this point, owning the multipart encoding is something I'd like to keep closer to the project, and I think that I know enough about multipart requests by now, to warrant "writing my own" and kill yet another dependency. It'll not happen immediately, though.

Lastly, I'll try to make a better job at talking about my work, so that hopefully my co-workers one day ask me if I know `httpx`. And it starts with this post.

