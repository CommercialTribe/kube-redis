#!/usr/bin/env bash
kubectl --namespace="$1" --context="$2" ${ACTION-"apply"} -Rf=./k8s --force
