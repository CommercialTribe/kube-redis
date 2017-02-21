#!/usr/bin/env bash
dir=${TYPE-"cluster"}
action=${ACTION-"apply"}
kubectl --namespace="$1" --context="$2" $action -Rf=./k8s-$TYPE/shared
kubectl --namespace="$1" --context="$2" $action -Rf=./k8s-$TYPE/$3
