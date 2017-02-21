# Redis on Kubernetes as StatefulSet

The following document describes the deployment of a self-bootstrapping, reliable,
multi-node Redis on Kubernetes. It deploys a master with replicated slaves, as
well as replicated redis sentinels which are use for health checking and failover.

## Prerequisites

This example assumes that you have a Kubernetes cluster installed and running,
and that you have installed the kubectl command line tool somewhere in your path.
Please see the getting started for installation instructions for your platform.

### Storage Class

This makes use of a StorageClass, either create a storage class with the name of
"ssd" or update the StatefulSet to point to to the correct StorageClass.

## Running

To get your cluster up and running simple run:

`kubectl apply -Rf k8s`

The cluster will automatically bootstrap itself.

### Caveats

Your pods may not show up in the dashboard. This is because we automatically add
additional labels to the pods to recognize the master. To see the pods within the
dashboard you should look at the redis-nodes service instead.
