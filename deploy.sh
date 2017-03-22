#!/usr/bin/env bash
set -e
kubectl --context="$1" --namespace="$2" apply -Rf=./k8s --force
kubectl --context="$1" --namespace="$2" delete pods -l name=redis-node
