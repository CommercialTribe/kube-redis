FROM ruby:2.4
MAINTAINER Jason Waldrip <jwaldrip@commercialtribe.com>

RUN gem install redis
ADD http://download.redis.io/redis-stable/src/redis-trib.rb /usr/local/bin/redis-trib
RUN chmod +x /usr/local/bin/redis-trib
ADD https://storage.googleapis.com/kubernetes-release/release/v1.5.3/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

WORKDIR app
ADD runner.sh ./runner.sh
RUN chmod +x ./runner.sh
CMD ./runner.sh
