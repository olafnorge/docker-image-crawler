# docker-image-crawler
Checks Dockerfiles if they are up-to-date with the latest base image.

[![GitHub release](https://img.shields.io/github/release/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)
[![Docker Automated buil](https://img.shields.io/docker/automated/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)
[![Docker Stars](https://img.shields.io/docker/stars/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)
[![Docker Pulls](https://img.shields.io/docker/pulls/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)
[![license](https://img.shields.io/github/license/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)

To overcome a common problem of outdated base images I created a script that
crawls the registry of a given docker image and checks if the base image is
still up-to-date.

The script either accepts a path to your Dockerfile or a full qualified image
tag like `alpine:3.5` as you would use in our Dockerfiles.

## Requirements

I tried to keep the requirements as less as possible. Please make sure you have
the following tools available on your machine:

* bash
* curl
* jq

If you don't want to or can't install those tools on your machine you could
also use a docker container which can be found at [the docker hub](https://hub.docker.com/r/olafnorge/docker-image-crawler/)

## Checking a Dockerfile

### Running the script

To check if you still use an up-to-date base image in your Dockerfile you
simply run:

```shell
./crawl.sh --dockerfile=<path to your Dockerfile>
```

I find it quiet useful to check all my Dockerfiles one after the other but
I am very lazy. Fortunately you can use `find` and `xargs` to get this job
done.

```shell
find $(pwd) -name Dockerfile -print0 | xargs -0 -I {} ./crawl.sh --dockerfile={}
```

### Running against a private docker registry

If you have a private docker registry you most likely have authentication in
place. You can provide your username and password to the script as well.

To do so please make use of the `--user` and `--pass` switches:

```shell
./crawl.sh --dockerfile=<path to your Dockerfile> --user=<username> --pass=<password>
```

It it also possible to combine it with the `find`-`xargs` approach:

```shell
find $(pwd) -name Dockerfile -print0 | xargs -0 -I {} ./crawl.sh --dockerfile={} --user=<username> --pass=<password>
```

If you don't want to see your username and/or password in the bash history you
have the possibility to export them to your environment.  
The script takes `REPOSITORY_USER` and `REPOSITORY_TOKEN` as the equivalents to
the `--user` and `--pass` switches. The switches always have precedence over the
environment variables.

### Running from docker

All the functionality described above can also be achieved by running it inside
a [docker container](https://hub.docker.com/r/olafnorge/docker-image-crawler/).

```shell
# check of a Dockerfile
docker run --rm --volume <path to your Dockerfile>:/tmp/Dockerfile olafnorge/docker-image-crawler:latest --dockerfile=/tmp/Dockerfile

# check of several Dockerfiles
find $(pwd) -name Dockerfile -print0 | xargs -0 -I {} docker run --rm --volume {}:/tmp/Dockerfile olafnorge/docker-image-crawler:latest --dockerfile=/tmp/Dockerfile

# check of a Dockerfile from private docker registry
docker run --rm --volume <path to your Dockerfile>:/tmp/Dockerfile olafnorge/docker-image-crawler:latest --dockerfile=/tmp/Dockerfile --user=<username> --pass=<password>

# check of several Dockerfiles from private docker registry
find $(pwd) -name Dockerfile -print0 | xargs -0 -I {} docker run --rm --volume {}:/tmp/Dockerfile olafnorge/docker-image-crawler:latest --dockerfile=/tmp/Dockerfile --user=<username> --pass=<password>
```

## Checking a full qualified `FROM` string

If you want to check a `FROM` string but don't have a corresponding Dockerfile
you can do it by using the `--from` switch instead of the `--dockerfile` switch.  

Please see the compressed commands below to get an idea of it:

```shell
# script without authentication
./crawl.sh --from=alpine:3.5

# script with authentication
./crawl.sh --from=alpine:3.5 --user=<username> --pass=<password>

# from docker without authentication
docker run --rm olafnorge/docker-image-crawler:latest --from=alpine:3.5

# from docker with authentication
docker run --rm olafnorge/docker-image-crawler:latest --from=alpine:3.5 --user=<username> --pass=<password>
```

## Checking locally pulled images

You can also check all your locally pulled images if they are still up-to-date.
Therefore you need to list all images and pass the output either to the script
or the docker container.

```shell
# list images and pass to script (without authentication)
docker image ls --format '{{ .Repository }}:{{ .Tag }}' | xargs -0 -I {} ./crawl.sh --from={}

# list images and pass to script (with authentication)
docker image ls --format '{{ .Repository }}:{{ .Tag }}' | xargs -0 -I {} ./crawl.sh --from={} --user=<username> --pass=<password>

# list images and pass to docker container (without authentication)
docker image ls --format '{{ .Repository }}:{{ .Tag }}' | xargs -0 -I {} docker run --rm olafnorge/docker-image-crawler:latest --from={}

# list images and pass to docker container (with authentication)
docker image ls --format '{{ .Repository }}:{{ .Tag }}' | xargs -0 -I {} docker run --rm olafnorge/docker-image-crawler:latest --from={} --user=<username> --pass=<password>
```


## Checking already deployed containers

From a security perspective it totally makes sense to check your running containers
periodically if they are still up-to-date.  

You can achieve it also with this script and/or docker container. Please see
compressed commands below.

```shell
# list containers and pass to script (without authentication)
docker container ls --all --format '{{ .Image }}' | xargs -0 -I {} ./crawl.sh --from={}

# list containers and pass to script (with authentication)
docker container ls --all --format '{{ .Image }}' | xargs -0 -I {} ./crawl.sh --from={} --user=<username> --pass=<password>

# list containers and pass to docker container (without authentication)
docker container ls --all --format '{{ .Image }}' | xargs -0 -I {} docker run --rm olafnorge/docker-image-crawler:latest --from={}

# list containers and pass to docker container (with authentication)
docker container ls --all --format '{{ .Image }}' | xargs -0 -I {} docker run --rm olafnorge/docker-image-crawler:latest --from={} --user=<username> --pass=<password>
```

## Contributing

Pull requests are welcome! I recommend getting feedback before starting by
opening a [GitHub issue](https://github.com/olafnorge/docker-image-crawler/issues).

## License

[![license](https://img.shields.io/github/license/olafnorge/docker-image-crawler.svg)](https://hub.docker.com/r/olafnorge/docker-image-crawler/)
