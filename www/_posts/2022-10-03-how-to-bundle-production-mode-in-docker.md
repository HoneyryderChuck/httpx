---
layout: post
title: How to "bundle install" in deployment mode, using bundler in docker
keywords: ruby, docker, bundler, gems, rubygems
---

**tl;dr**: `BUNDLE_PATH=$GEM_HOME`.

I was recently setting up the deployment of a `ruby` service, in my employer's production environment, which uses [EKS on AWS](https://aws.amazon.com/pt/eks/) and [docker](https://docs.docker.com/get-docker/) containers. This time though, I wanted to try how hard would be to generate a production image, as well the dev/test one we use in CI, from the same [Dockerfile](https://docs.docker.com/engine/reference/builder/).

I figured that it was just a matter of juggling the right combination of [ARG](https://docs.docker.com/engine/reference/builder/) and [ENV](https://docs.docker.com/compose/environment-variables/) declarations. And while I was right, I thought the outcome was worth documenting in a blog post about, in order to spare the next rubyist suffering when going down the same path. And while I can still appreciate `bundler`'s role and leadership in the `ruby` community, and array of features and configurability, its defaults and user/permissions handling leave some to be desired.

## Development setup

The initial Dockerfile used for development looked roughly like this:

```Dockerfile
FROM ruby:3.1.2-bullseye

LABEL maintainer=me

RUN adduser --disabled-password --gecos '' app \
    && mkdir -p /home/service \
    && chown app:app /home/service

USER app:app

WORKDIR /home/service

COPY --chown=app:app Gemfile Gemfile.lock /home/service

RUN bundle install
COPY --chown=app:app . .

CMD ["bundle", "exec", "start-it-up"]
```

The Gemfile was very simple, with a test group:

```ruby
# Gemfile

source "https://rubygems.org"

gem "rake"
gem "zeitwerk"
gem "sentry-ruby"
# ...

group :test do
  gem "minitest"
  gem "standard"
  gem "debug"
  # ...
end
```

This was all tied up locally using [Docker Compose](https://docs.docker.com/get-started/08_using_compose/), where the service declaration looked like this:

```yaml
# docker-compose.yml

services:
  foo:
    env_file: .env
    volumes:
      - ./:/home/service
```

This setup worked well locally, and was reused to run the tests in CI (we use [Gitlab CI docker executors](https://docs.gitlab.com/runner/executors/docker.html)).

It was ready to go to production.

## bundler in production

[Bundler how to deploy page](https://bundler.io/guides/deploying.html) gives you a simple advice: `bundle install --deployment` and you're good to go. My use-case wasn't as simple though, as I wanted to follow some best practices from the get-go, rather than retrofitting them when it's too costly to do so.

For once, I didn't want to install test dependencies in the final production image (benefit: leaner production image, less exposure to vulnerabilities I don't need in servers). I also didn't want to use commmand-line options, as dealing with the development/production options would make my single Dockerfile harder to read. Fortunately, [bundler covers that by supporting environment variables for configuration](https://bundler.io/man/bundle-config.1.html):

```Dockerfile
# Dockerfile
FROM ruby:3.1.2-bullseye

# to declare which bundler groups to ignore, aka bundle install --without
ARG BUNDLE_WITHOUT
```

```yaml
# .gitlab-ci.yml

Build Production Image:
  variables:
    DOCKER_BUILD_ARGS: "BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=test"
  script:
    - docker build ${DOCKER_BUILD_ARGS} ...
```

```yml
# kubernetes service.yml
env:
  BUNDLE_WITHOUT:
    value: "test"
  BUNDLE_DEPLOYMENT:
    value: 1
```

Simple, right? So I thought, so I deployed. And the service didn't boot. Looking at the logs, I was seeing a variation of the following error:

```log
Could not find rake-13.0.6, zeitwerk-2.6.0, ...(the rest) in any of the sources (Bundler::GemNotFound)
```

I couldn't figure out. It worked on my machine. And I vaguely remembered doing similar work in the past. So I start googling for "ruby dockerfile setup", only to find similar dockerfiles. I initialize a pod, and quickly check for `GEM_PATH`, pointing to `/usr/local/bundle`, and nothing was there in fact.

I then spent the next two days, playing with several other bundler flags, adding, removing, editing them, trying to get to a positive outcome, and in the process almost giving up the idea altogether.

But this post is not about the journey. It's about the solution. Which eventually became clear.

## Root, non-root, bundler, and rubygems

The main difference between my dockerfile, and most of the "ruby docker" examples on the web: I wasn't running the process as root.

The [ruby base image](https://github.com/docker-library/ruby/blob/master/3.1/bullseye/Dockerfile) sets up some variables, some of them involving `bundler` and `rubygems` (both ship with ruby as "bundled gems"):

```dockerfile
# from ruby 3.1.2 bullseye dockerfile

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
```

This means that:

* gems are installed in `$GEM_HOME`;
* gem-installed binstubs are accessible in the `$PATH`;
* `bundler` configs can be found under `$GEM_HOME`;

When I switch to a non-privileged user, as the initial Dockerfile shows, and run `bundle install`, gems are installed under `$GEM_HOME/gems`; executables are under `$GEM_HOME/bin`. It works on my machine.

But when I do it with `BUNDLE_DEPLOYMENT=1`? Gems still get installed in the same place. Executables too. But running `bundle exec` breaks. That's because, in deployment mode, `bundler` sets its internal bundle path, used for dependency resolution and lookup, [to `"vendor/bundle"`](https://github.com/rubygems/rubygems/blob/def27af571af48f7375cc0bdc58b845122dcb5b4/bundler/lib/bundler/settings.rb#L4).

```ruby
# from lib/bundler/settings.rb
def path
  configs.each do |_level, settings|
    path = value_for("path", settings)
    path = "vendor/bundle" if value_for("deployment", settings) && path.nil?
    # ...
```

But there's nothing there, because as it was mentioned, gems were installed under `$GEM_HOME`.

So the solution is right in the line above: just set the bundle path. The most straightforward way to do this in this setup was via `BUNDLE_PATH`:

```dockerfile
# Dockerfile
ENV BUNDLE_PATH $GEM_HOME
# and now, you can bundle exec
```

That's it. Annoying, but simple to fix.

## Conclusion

While the solution was very straightforward (patch this environment variable and you're good to go), it took me some time and a lot of trial and error to get there. Due to a combination of factors.

First one is docker defaults and best practices; while it's been known for some time in the security realm that ["thou shalt not run containers as root"](https://stackoverflow.com/questions/68155641/should-i-run-things-inside-a-docker-container-as-non-root-for-safety), if I type "dockerfile ruby" in google, from the [first](https://lipanski.com/posts/dockerfile-ruby-best-practices) [5](https://semaphoreci.com/community/tutorials/dockerizing-a-ruby-on-rails-application) [relevant](https://www.cloudbees.com/blog/build-minimal-docker-container-ruby-apps) [results](https://www.digitalocean.com/community/tutorials/containerizing-a-ruby-on-rails-application-for-development-with-docker-compose) [I](https://docs.docker.com/samples/rails/) get (the last one being docker official recommendation for using `compose` and `rails`), only one of them sets a non-privileged user for running the container. And that single example does it **after** running `bundle install`.

Why is it important to run `bundle install` as non-root? You can read the details in [this Snyk blog post](https://snyk.io/blog/ruby-gem-installation-lockfile-injection-attacks/), but the tl;dr is, if the gem requires compiling C extensions, a [post-install callback can be invoked](https://blog.costan.us/2008/11/post-install-post-update-scripts-for.html) which allows arbitrary code to run with the privileges of the user invoking `bundle install`, which becomes a privilege escalation attack when exploited.

Why does `bundler` default to setting `"vendor/bundle"` as the default gems lookup dir, which is different than the default gem install dir, when deployment-mode is activated? I have no idea. I'd say it looks like a bug, as [the docs do say that gems are installed to "vendor/bundle" in deployment mode](https://github.com/rubygems/rubygems/blob/def27af571af48f7375cc0bdc58b845122dcb5b4/bundler/lib/bundler/man/bundle-install.1.ronn#deployment-mode), and ruby docker defaults overriding `GEM_HOME` causes `bundler` to use it to install gems, but then it gets ignored for path lookups? But somehow works when user can `sudo`? Do `bundler` and `rubygems` still have a few misalignments to work out? `bundler` defaults don't seem to be the sanest, as [this blog post puts it, whether you agree with the tone or not](https://felipec.wordpress.com/2022/08/25/fixing-ruby-gems-installation/), it can definitely do better.

But don't get me wrong, as it's still better than dealing with the absolute scorched earth equivalent in `python` or `nodejs`.


No bundler options were deprecated while performing these reproductions.