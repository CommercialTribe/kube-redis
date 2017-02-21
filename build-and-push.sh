#!/usr/bin/env bash
login(){
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
}

build-and-push() {
  docker build -t $1 $2
  docker push $1 || (login && docker push $1)
}

build-and-push commercialtribe/redis-cluster-sidecar k8s-cluster
build-and-push commercialtribe/redis-sentinel-sidecar k8s-sentinel
