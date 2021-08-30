---
layout: post
title: Gitlab CI suite optimizations, and how I decreased the carbon footprint of my CI suite
keywords: CI, Gitlab CI, caching, optimizations, fork-join
---


![Eco]({{ '/images/eco.png' | prepend: site.baseurl }})


One of the accomplishments I'm most proud of in the work I have done in `httpx` is the test suite. Testing an http library functionally ain't easy. But leveraging gitlab CI, docker-compose and different docker images from known http servers and proxies provides me with an elaborate, yet-easy-to-use setup, which I use fo CI, development, and overall troubleshooting. In fact, running the exact same thing that runs in CI is as easy as running this command (from the project root):

```
# running the test suite for ruby 2.7
> docker-compose -f docker-compose.yml -f docker-compose-ruby-2.7.yml run httpx
```

This has been the state-of-the-art for +2 years, and I've been learning the twists and turns of CI setups along with it. All that to say, there were a few not-so-obvious issues with my initials setups. The fact that Gitlab CI documentation for ruby has been mostly directioned towards the common *how to test rails applications with a database* scenario certainly didn't help, as the gitlab CI  `docker-in-docker` setup, felt like a second class citizen, back in the day. I also ran coverage in the test suite for every ruby version, while never bothering to merge the results, culminating in incorrect coverage badges and inability to fully identify unreachable code across ruby versions.

But most of all, it all took too damn long to run. Over 12 minutes, yikes!

While certainly not ideal, it still worked, and for a long time, I didn't bother to touch that running system. It did annoy me sporadically, such as when having to wait for CI to finish in order to publish a new version, but all in all, from the project maintenance perspective, it was a net positive.

Still, things could be improved. And experience at my day job with other CI setups and services (sending some love to [Buildkite](https://buildkite.com/)!) gave me more of an idea of what type of expectations should I have from a ruby library test suite. Also, a desire to lower the carbon footprint of such systems started creeping in, and faster test suites use less CPU.


So, after months of failed experiments and some procrastination, I've finally deployed some optimizations in the CI suite of `httpx`, not only with the intent of providing more accurate coverage information, but also to make the CI suite run significantly faster. And faster it runs, now in around 6 minutes!

What follows are a set of very obvious, and some not so obvious, recommendations about CI in general, CI in gitlab, CI for ruby (and multiple ruby versions), quirks, rules and regulations, and I hope by the time all is said and done, you've learned a valuable lesson about life and software.

## Run only the necessary tasks

By default, the CI suite runs the `minitest` tests and `rubocop`, for all ruby versions supported.

A case could be made that linting should only be run for the latest version, and "just work" for the rest. However, `rubocop` runs so fast that this optimization is negligible.

Except for JRuby. JRuby has many characteristics that make it a desirable platform to run ruby code, but start up time and short running scripts aren't among its strenghts. Also, `rubocop` cops are way slower under JRuby.

Also, the supported JRuby version (latest from the 9000 series) complies with a ruby version (2.5), which is already tested by CRuby. Therefore, there is no tangible gain from running it under JRuby.

And that's why, in gitlab CI, `rubocop` isn't run for JRuby anymore.

## Cache your dependencies

So, let's go straight for the meat: the 20% work that gave 80% of the benefit was caching the dependencies used in the CI.

*Well, thank you, captain obvious*. It was not that simple, unfortunately.

[Gitlab CI documents how to cache dependencies](https://docs.gitlab.com/ee/ci/caching/#caching-ruby-dependencies), and the advertised setup is, at the moment of this article, this one here:

```ruby
#
# https://gitlab.com/gitlab-org/gitlab/tree/master/lib/gitlab/ci/templates/Ruby.gitlab-ci.yml
#
image: ruby:2.6

# Cache gems in between builds
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - vendor/ruby

before_script:
  - ruby -v                                        # Print out ruby version for debugging
  - bundle install -j $(nproc) --path vendor/ruby  # Install dependencies into ./vendor/ruby
```

This setup assumes that you're using the ["docker executor" mode](https://docs.gitlab.com/runner/executors/docker.html), you're running your suite using a docker ruby image, and you're passing options to `bundler` using CLI arguments (the `-j` and `--path`). The script will run, gems will be installed to `vendor/ruby`. As the project directory is a volume mounted in the docker container, `vendor/ruby` will be available in the host machine, and the directory will be zipped and stored somewhere, until the next run.

This couldn't be applied to `httpx` though, as the container runs a `docker-compose` image, and tests run in a separate service (the `docker-in-docker` service), so this mount isn't available out of the box. This meant that, for a long time, **all dependencies were being installed for every test job in every ruby version all the time!**.

Think about that for a second. How many times the same gem was downloaded in the same machine for the same project. How many times C extensions were compiled. Not only was this incredibly expensive, it was unsafe as well, as the CI suite was vulnerable to the "leftpad curse", i.e. one package could be yanked from rubygems and break all the builds.

The first thing I considered doing was *translating* my docker-compose setup to `.gitlab-ci.yml`, similar to the example from the documentation. This approach was tried, but quickly abandoned, as docker-compose provides a wider array of options, some of them which couldn't be translated to gitlab CI options; moreover, by keeping the docker-compose setup, so I could still be able to run the test suite locally, now I had to maintain two systems, thereby increasing the maintenance overhead.


Recently I found the answer [here](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html#use-docker-in-docker-workflow-with-docker-executor): `docker-in-docker` with a `mount-in-mount`:

> Since the docker:19.03.12-dind container and the runner container don’t share their root file system, the job’s working directory can be used as a mount point for child containers. For example, if you have files you want to share with a child container, you may create a subdirectory under /builds/$CI_PROJECT_PATH and use it as your mount point...

Since `/builds/$CI_PROJECT_PATH` is the mount-point, all you have to do is make sure that the directory exists and is mounted in  the child container which runs the test scripts:

```yml
# in gitlab.ci

variables:
  MOUNT_POINT: /builds/$CI_PROJECT_PATH/vendor
  # relative path from project root where gems are to be installed
  BUNDLE_PATH: vendor

script:
  - mkdir -p "$MOUNT_POINT"

# in docker-compose.gitlab.yml, which is only loaded in CI mode, not locally when you develop:
...
services:
  httpx:
    environment:
      - "BUNDLE_PATH=${BUNDLE_PATH}"
      - "BUNDLE_JOBS=${BUNDLE_JOBS}"
    volumes:
      # tests run in /home, so making sure that gems will ben installed in /home/vendor
      - "${MOUNT_POINT}:/home/vendor"
      ...

```


And all of a sudden, cache was enabled:

![CI Cache view]({{ '/images/ruby27cache.png' | prepend: site.baseurl }})


... only for the ruby 2.7 build 🤦.

Which takes me to my next recommendation.


## Make sure you cache the right directories

As per the example from the gitlab CI documentation, you should be caching `vendor/ruby`. And if you pay closer attention, you'll notice that the same directory is passed as an argument to `bundle install`, via the `--path` option.

However, if you do this, more recent versions of `bundler` will trigger the following warning:

```[DEPRECATED] The `--path` flag is deprecated because it relies on being remembered across bundler invocations, which bundler will no longer do in future versions. Instead please use `bundle config set path '.bundle'`, and stop using this flag```.

If you also look at the `docker-compose.gitlab.yml` example a bit above, you'll also notice that I'm setting the `BUNDLE_PATH` environment variable. This variable is [documented by bundler](https://bundler.io/v2.1/man/bundle-config.1.html) and is supposed to do the same as that `bundle config set path '.bundle'`, which is, declare the directory where the gems are to be installed.

I thought that this was going to be compliant with the example from the gitlab CI, and the ruby 2.7 build gave me that assurance. But I thought wrong.

By now, you must have heard about `bundler` 2 already: a lot of people have been complaining, and I'm no exception. I particularly get confused with `bundler` 2 handling of lockfiles bundled by older versions, and `bundler -v` showing different versions depending because of that. And due to the described issue, I found out that [it also interprets BUNDLE_PATH differently than older versions](https://github.com/rubygems/bundler/issues/3552).

To be fair with `bundler`, major versions are supposed to break stuff if the change makes sense, and the new way makes sense to me. But I can't use `bundler` 2 under ruby 2.1, so I have to find a way to support both.

That was easy: since all of them dump everything under `BUNDLE_PATH`, I just have to cache it.

```yml
# in .gitlab-ci.yml
# Cache gems in between builds
cache:
  ...
  paths:
    - vendor
...
variables:
  BUNDLE_PATH: vendor
```

And just like that, dependencies were cached for all test builds.

## Minimize dependency usage

Although you probably need all dependencies for running your tests, a CI suite is more than that: it's preparing the coverage reports, build documentation, build wikis, deploy project pages to servers, and all that.

You don't need all dependencies for all that.

There different strategies for that, and although I'm still not done exploring this part, I can certainly make a few recommendations.

### gem install

If you only need a single gem for the job, you can forego `bundler` and use `gem` instead. For instance, building coverage reports only requires `simplecov`. So, at the time of this writing, I'm using this approach when doing it:

```yml
scripts:
  - gem install --no-cov simplecov
  - rake coverage:report
```

The main drawback from it is that the gem won't be cached, and will be installed every single time, while keeping it all contained in a single file, which is very handy for development.

### Different Gemfiles

You can also opt for having dependencies for each task segregated into different Gemfiles. For building this website, there's a particular job which sets a different Gemfile as the default to install `jekyll`. This is particularly easy when leveraging bundler supported environment variables:

```yml
# in .gitlab-ci.yml
jekyll:
  stage: test
  image: "ruby:2.7-alpine"
  variables:
    JEKYLL_ENV: production
    BUNDLE_GEMFILE: www/Gemfile-jekyll
  script:
    - bundle install
    - bundle exec jekyll build -s www -d www/public
```

### Different Gemfile groups

This one is still in the making, as I'm thinking of segregating the dependencies in the same Gemfile, and then using the `--with` flag from bundler to point which groups to use.

Then I can have the "test", "coverage", and "website" groups, and use them accordingly.

This'll diminish cache sizes and the time to install when cache is busted.


## Work around simplecov quirks

`simplecov` is the de-facto code coverage tool for ruby. And works pretty much out-of-the-box when running all your tests in a single run.

It also supports ["distributed mode"](https://github.com/simplecov-ruby/simplecov#merging-results), which is, when execution of your code is exercised across different tools (i.e. `rspec` and `cucumber`) or across many machines (the `knapsack` example). In such a case, you can gather all the generated result files, and merge them, using `SimpleCov.collate`.

This also fits the case for running multiple ruby versions.

So what I do is: first, set up the directory where simplecov results are to be stored as having something unique to that run:

```ruby
# in test helper
require "simplecov"
SimpleCov.command_name "#{RUBY_ENGINE}-#{RUBY_VERSION}"
SimpleCov.coverage_dir "coverage/#{RUBY_ENGINE}-#{RUBY_VERSION}"
```

And set it as artifact:

```yml
# in .gitlab-ci.yml
artifacts:
  paths:
    - coverage/
```

Then, gather all the results in a separate job, and collate them:

```yml
coverage:
  stage: prepare
  dependencies:
    - test_jruby
    - test_ruby21
    - test_ruby27
  image: "ruby:2.7-alpine"
  script:
    - gem install --no-doc simplecov
    - rake coverage:report
```

In and of itself, there is nothing here that you wouldn't have found in the documentation of the projects. However, there's a caveat for our case: `simplecov` uses absolute paths when storing the result files, and requires the paths to still be valid when collating.

This breaks for `httpx`: tests run in a container set up in its own `docker-compose.yml`, mounted under `/home`, whereas `coverage`job runs inside a "docker executor", where the mounted directory is `builds/$PROJECT_CI_PATH`.

Don't wait too long for `simplecov` to start supporting relative paths though, as [many](https://github.com/simplecov-ruby/simplecov/issues/887) [issues](https://github.com/simplecov-ruby/simplecov/issues/229) [have](https://github.com/simplecov-ruby/simplecov/issues/197) [been](https://github.com/simplecov-ruby/simplecov/issues/197) reported and closed as early as 2013.

So one has to manually update the absolute paths, before the result files are merged. This can be achieved using our friends `bash` and `sed`:

```yml
script:
  # bash kung fu fighting
  - find coverage -name "*resultset.json" -exec sed -i 's?/home?'`pwd`'?' {} \;
  - gem install --no-doc simplecov
  - rake coverage:report
```

And voilá, we have a compounded coverage report.

## Set job in badges

Coverage badges are cool, and they are informative.

![coverage badge]({{ '/images/coverage-badge.png' | prepend: site.baseurl }})

They can also be wrong, if you're not specific about where the badge percentage is to be taken from. Since all of the test jobs emit (partial) coverage information, it's important that we say we want the value for the "compounded" coverage.

You should then use the badge and append the job name via query param, i.e. `https://gitlab.com/honeyryderchuck/httpx/badges/master/coverage.svg?job=coverage`.

## TODOs

A significant chunk of improvements has been achieved. Still there are a few things to do to lower the carbon footprint. Here's what I would like to accomplish before I call it a day:

### Single Gemfile

I've touched on this previously, so you should already be familiar with the topic.

### Eliminate job logs

Job logs are pretty verbose. I think that can be improved. By eliminating `bundler` logs (via `--quiet` or environment variable) and docker services logs (via `run` instead of `up`), much can be achieved.

I'd like to be able to easily turn it on though, for debugging purposes.

### Dynamic Dockerfile

I'd like to be able to cache the set of commands in the `build.sh` script. That would be possible if the build process were leveraged by a `Dockerfile`, but I'd like not to maintain a Dockerfile per ruby version. So ideally, I'd be able to do this dynamically, using a single `Dockerfile` and some parameter. Let the research begin.

### Improve job dependencies

Part of the reason why the overall pipeline takes so long is because of "bottleneck" jobs, i.e. jobs waiting on other jobs to finish.

Also there's no gain in running the tests if I only updated the website, or docs. One of the latest releases of Gitlab hinted at a feature in this direction for CI.

I'd like to see if there's something in that department one could do, however.

## Conclusion

Technical debt also exists outside of commercial software. And although open source projects aren't constrained by the needs of "delivering customer value", there is sometimes self-imposed pushback in improving less-than sexy parts of projects.

Investing some time in improving the state of `httpx` CI doesn't make it a better HTTP client, indeed; but a significant part of the "cost" in maintaining it is in the machines constantly verifying that it works as intended. This cost is not always tangible for open source maintainers, as usually machines are at our disposal for free (even if not available all the time), so one tends to chalk it up to "economies of scale" and other bulls*** we tell ourselves.

But the environment feels the cost. The energy to run that EC2 instance running linux running docker running docker-in-docker running ruby running your CI suite comes from somewhere. So the less you make use of it, the more the planet and future generations will thank you for it.


And that concludes my "jesus complex" post of the month.

<!-- blank line -->
<figure class="video-container">
  <iframe src="https://www.youtube.com/embed/6wbaGf4fU9w" frameborder="0" allowfullscreen="true"> </iframe>
</figure>
<!-- blank line -->
