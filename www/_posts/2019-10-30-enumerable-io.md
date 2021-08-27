---
layout: post
title: Enumerable IO Streams
keyowrds: IO, enumerable, streaming, API
---

I've been recently working on CSV generation with ruby in my day job, in order to solve a bottleneck we found because of a DB table, whose number or rows grew too large for the infrastructure to handle our poorly optimized code. This led me in a journey of discovery on how to use and play with raw ruby APIs to solve a complex problem.

## The problem

So, let's say we have a `User` ActiveRecord class, and our routine looks like this:

```ruby

class UsersCSV
  def initialize(users)
    @users = users
  end

  def generate
    CSV.generate(force_quotes: true) do |csv|
      csv << %w[id name address has_dog]
      @users.find_each do |user|
      csv << [
        user.id,
        user.name,
        user.address.to_addr,
        user.dog.present?
      ]
    end
  end
end

payload = UsersCSV.new(User.relevant_for_this_csv).generate

aws_bucket.upload(body: StringIO(payload))
```

The first thing you might ask is "why are you not using [sequel](https://github.com/jeremyevans/sequel)". That is a valid question, but for the purpose of this article, let's assume we're stuck with active record (we really kind of are).

The second might be "dude, that address seems to be a relationship, isn't that a classic N+1 no-brainer?". It kind of is, and good for you to notice, I'll get back to it later.

But the third thing is "dude, what happens if you have like, a million users, and you're generating a CSV for all of them?". And touchè! That's what I wanted you to focus on.

You see, this example is a standard example you find all over the internet on how to generate CSV  data using the `csv` standard library, so it's not like I'm doing something out of the ordinary.

I could rewrite the generation to use `CSV.open("path/to/file", "wb")` to pipe the data to a file, however if I can send the data to the AWS bucket in chunks, why can't I just pipe it as I generate? There are many ways to do this, but this put me to think, and I came up with an solution using the `Enumerable` module.


## Enumerable to the rescue

I'll change my code to enumerate the CSV rows as they're generated:

```ruby
class UsersCSV
  include Enumerable

  def initialize(users)
    @users = users
  end

  def each
    yield line(%w[id name address has_dog])
      @users.find_each do |user|
      yield line([
        user.id,
        user.name,
        user.address.to_addr,
        user.dog.present?
      ])
    end
  end

  private

  def line(row)
    CSV.generate(row, force_quotes: true)
  end
end

# I can eager-load the payload
payload = UsersCSV.new(User.relevant_for_this_csv).to_a.join
# you can select line by line
csv = UsersCSV.new(User.relevant_for_this_csv).each
headers = csv.next
first_row = csv.next
#...
```

But this by itself doesn't solve my issue. If you look at the first example, specifically the line:

```ruby
aws_bucket.upload(body: StringIO(payload))
```

I'm wrapping the payload in a StringIO. that's because my aws client expects an IO interface. And Enumerables aren't IOs.

## The IO interface

An IO-like object must implement a few methods to be usable by certain functions which expect the IO interface. In other more-ruby-words, it must "quack like an IO". And how does an IO quack? Here are a few examples:

* An IO reader must implement `#read(size, buffer)`
* An IO writer must implement `#write(data)`
* A duplex IO must implement both
* A closable IO must implement `eof?` and `#close`
* A rewindable socket must implement `#rewind`
* IO wrappers must implement `#to_io`

You know some of ruby's classes which implement a few (some, all) of these APIs: `File`, `TCPSocket`, and the aforementioned `StringIO`.

A few ruby APIs expect arguments which implement the IO interface, but aren't necessarily instances of IO.

* `IO.select` can be passed IO wrappers
* `IO.copy_stream(src, dst)`, takes an IO reader and an IO writer as arguments.

## Enter Enumerable IO

So, what if our csv generator can turn itself into a readable IO?

I could deal with this behaviour directly in my routine, but I'd argue that this should be a feature provided by `Enumerable`, i.e. an enumerable could also be cast into an IO. The expectation is risky: the yield-able data must be strings, for example. But for now, I'll just monkey-patch the `Enumerable` module:

```ruby
# practical example of a feature proposed to ruby core:
# https://bugs.ruby-lang.org/issues/15549

module Enumerable
  def to_readable_stream
    Reader.new(self, size)
  end

  class Reader
    attr_reader :bytesize

    def initialize(enum, size = nil)
      @enum = enum
      @bytesize = size
      @buffer = "".b
    end

    def read(bytes, buffer = nil)
      @iterator ||= @enum.each
      buffer ||= @buffer
      buffer.clear
      if @rest
        buffer << @rest
        @rest.clear
      end
      while buffer.bytesize < bytes
        begin
          buffer << @iterator.next
        rescue StopIteration
          return if buffer.empty?
          break
        end
      end
      @rest = buffer.slice!(bytes..-1)
      buffer
    end
  end
end
```

With this extension, I can do the following:

```ruby
csv = UsersCSV.new(User.relevant_scope_for_this_csv).to_readable_stream
aws_bucket.upload(body: csv)
```

And voilà! Enumerable and IO APIs for the win!

Using this solution, there's a performance benefit while using clean ruby APIs.

The main performance benefit is, the payload doesn't need to be all kept in memory til all the CSV is generated, so we get constant memory usage (in our case, this leak was exacerbated by that N+1 problem; the more you wait for the rows, the longer the csv payload was being retained).

## Caveat

Depending of what you're using to upload the file, you might still need to buffer first to a file; at work, we use `fog` to manage our S3 uploads, which requires IO-like request bodies to implement `rewind`, therefore the easy way out is to buffer to a tempfile first:

```ruby
csv = UsersCSV.new(User.relevant_scope_for_this_csv).to_readable_stream
file = Tempfile.new
IO.copy_stream(csv, file)
file.rewind
fog_wrapper.upload(file)
```

## Conclusion

There are many ways to skin this cat, but I argue that this way is the easiest tom maintain: you can tell any developer that their CSV/XML/${insert format here} generator must implement `#each` and yield formatted lines, and then you just have to pass it to your uploader. You ensure that the payload will not grow linearly, and no one will ever have to read another tutorial on "How to write CSV files in ruby" ever again.


This doesn't mean that all of our problems are solved: as the number of records grows, so does the time needed to generate it. And it will become a bottleneck. So how can you guarantee that the time needed to generate the date won't derail?


I'll let you know when I have the answer.
