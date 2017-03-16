#!/usr/bin/env bash
kubectl --context="$1" --namespace="$2" apply -Rf=./k8s --force
