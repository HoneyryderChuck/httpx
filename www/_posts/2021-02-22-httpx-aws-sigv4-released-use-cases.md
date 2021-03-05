---
layout: post
title: HTTPX AWS Sigv4 plugin - Use cases
---


`httpx` v0.12.0 ships with [new plugins to authenticate requests using AWS Sigv4 signatures](https://gitlab.com/honeyryderchuck/httpx/-/wikis/AWS-Sigv4).

AWS Sigv4 is how requests are authenticated when using AWS services, such as when a file is uploaded to an S3 private bucket, or a message is pushed to an SQS queue (if you're using `awscli` or any of the SDKs, they're doing it for you). [It's well specified](https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html), and is not a proprietary protocol, and Google Cloud Services is known to support it, along with other cloud providers, so it's the *de-facto* way of authenticating with cloud services APIs.

This feature was inspired by a [recently integrated, similar feature in cURL](https://www.mankier.com/3/CURLOPT_AWS_SIGV4), and was driven both by curiosity (what can I say, I'm a protocol sucker), and also by thinking about how `httpx` could be used to improve cloud-based workflows.

## aws-sdk, fog

In the ruby ecosystem, both [aws-sdk](https://github.com/aws/aws-sdk-ruby) (the official AWS-supported ruby AWS SDK) and [fog](https://github.com/fog/fog) (multi cloud provider library, also supports some AWS services) already provide integration with some of the aforementioned cloud services.

Both are organized the same way:

* full functionality is spread all over different gems (`aws-sdk-core`, `aws-sdk-s3`, `fog-aws`...);
* API interactions are "hidden" behind Ruby object façades:
  * `fog` example: `directory.files.create(key: 'user/1/Gemfile', body: File.open('Gemfile')`
  * `aws-sdk` example : `s3.buckets.create('my-bucket')`
* "mocking" method calls is a library feature;

Both are well-tested, mature and complete (for each use-case) implementations.

These plugins aren't supposed to replace them. If they work well for you, by all means, keep using them.

So what are they for?


## It's only HTTP, but I like it!

![Mick Jagger]({{ '/images/mick.jpg' | prepend: site.baseurl }})

All of these cloud providers serve their customers via HTTP APIs, and most of them provide SDKs, in their chosen batch of supported programming languages. For instance, AWS supports `aws-sdk` for ruby, `boto3` for python, `awssdk` for Java, and the list goes on. They all interface with the same HTTP APIs.

These SDKs tend to be idiomatic to the language, hence ruby's is pretty much dominated by object oriented APIs, with its own sack of exceptions, result object... The devil is in the ~~details~~ documentation.

These SDKs do achieve the goal of lowering the entry barrier: most developers will much rather have an SDK with proper IDE integration and autocomplete hints, than spend their time searching in the API documentation for the correct URLs and mime type formats. They won't care if the extra layer means they will miss on batching some work, or are going through many hops, as longs as it works and they can close that Jira ticket.

But some developers live on the wire. They know how HTTP works. They won't need the extra layer. Some just get it. They know `s3.buckets.create('my-bucket')` means `PUT https://my-bucket.s3.amazonaws.com`. Some of them probably need to know it: given an organization with certain scale, every extra hop might mean a christmas bonus for Jeff Bezos (or birthday present, because as we all know, Bezos is Jesus in disguise).

![Jeff Bezos]({{ '/images/bezesus.jpg' | prepend: site.baseurl }})

This plugin is for them!

```ruby
http = HTTPX.plugin(:aws_sdk_authentication)
http.aws_sdk_authentication(service: "s3")
    .put("https://my-bucket.s3.amazonaws.com") # there's your S3 bucket
```

## 0 to 1, 1 to many

I've worked in certain stacks which only use S3. In such cases, it might seem a bit overkill to use the SDKs, although YMMV.

But where `httpx` stands out is when you'd need to download/upload multiple files. Here's how you'd hypothetically download all the seasons of "Seinfeld" from a known bucket:

```ruby
# using aws sdk
s3 = AWS::S3.new
1.upto(9).each do |season|
  File.open("season-#{season}", 'wb') do |file|
    s3.get_object({ bucket:'seinfeld', key:"season-#{season}" }, target: file)
  end
end

#using httpx
http = HTTPX.plugin(:aws_sdk_authentication)
http.aws_sdk_authentication(service: "s3")
responses = http.get(*1.upto(9).map{ |i| "https://seinfeld.s3.amazonaws.com/season-#{i}" })
# they're already in the filesystem, but just for convenience:
responses.each_with_index { |res, i| res.body.copy_to(Pathname.new("/path/to/seinfeld/season-#{i+1}")) }
```

![Seinfeld]({{ '/images/seinfeld.jpg' | prepend: site.baseurl }})

Besides the arguably better ergonomics, `httpx` will target the more recent HTTP version to download items concurrently, which might not mean much right now for AWS (at the time of writing the article, S3 requests can only be made via HTTP/1.1), but certainly for other providers (GCP Storage, for example, supports HTTP/2, so put your Seinfelds there).


## Multi-cloud support

In case you're targeting multiple cloud providers from the same application, having one client support both providers can become easier to maintain than two SDKs with different underlying APIs. It's a non-common scenario, but again given enough scale, dollars can be squeezed by distributing data and lowering costs of storage.

Also, data migrations. When moving data from AWS to GCP, and from GCP to Rackspace, having the same way of doing things will help you move faster when the time comes. And AWS Sigv4 and reasonably similar URIs is a much simpler lower common denominator to maintain than multiple SDK libraries, where one calls it "bucket" and the other calls it "directory", and there's always a different exception popping up.

## Conclusion

The AWS Sigv4 plugins are just another layer in the `httpx` "swiss army knife". Hope it'll be of use to someone, as it'll be for myself (I'll be sure to integrate it in some of the S3 integrations I maintain).

Hack on.


