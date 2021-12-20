## how to build and publish new version of nghttp2 container

```
> docker build -f test/support/ci/Dockerfile.nghttp2 -t registry.gitlab.com/honeyryderchuck/httpx/nghttp2:latest .
> docker login -u HoneyryderChuck --password-stdin registry.gitlab.com/honeyryderchuck/httpx/nghttp2:latest
> docker push registry.gitlab.com/honeyryderchuck/httpx/nghttp2:latest

```