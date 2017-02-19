#!/usr/bin/env bash
kubectl --namespace="$1" --context="$2" apply -Rf=./k8s/shared
kubectl --namespace="$1" --context="$2" apply -Rf=./k8s/$3
