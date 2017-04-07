#!/usr/bin/env bash
image="commercialtribe/redis-sentinel-sidecar:v20170407.1"

login(){
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
}

push(){
  if docker pull $image ; then exit 1 ; fi
  docker push $image
}

build() {
  docker build -t $image .
}

build && (push || (login && push))
