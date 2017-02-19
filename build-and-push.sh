#!/usr/bin/env bash
image=commercialtribe/redis-sidecar
docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
docker build -t $image .
docker push $image
