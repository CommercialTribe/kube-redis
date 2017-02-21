#!/usr/bin/env bash
set -e

# Set vars
replicas=${REPLICAS-1}              # number of replicas
ip=${POD_IP-`hostname -i`}          # ip address of pod
redis_port=${REDIS_NODE_PORT-6379}  # redis port
min_hosts=$(((1 + $replicas) * 3))  # the minimum number of hosts
this_host="$ip:$redis_port"         # this host

# Get all the kubernetes pods
labels=`cat /etc/pod-info/labels | tr -d '"'`

run(){
  echo $@
  $@
}

status() {
  host=${1-"$this_host"}
  echo "Checking status of '$host'..."
  if redis-trib check $host | tee >(cat 1>&2) | grep '\[ERR\]' &> /dev/null ; then
    >&2 echo "Host: '$host' unhealthy"
    return 1
  else
    echo "Host: '$host' healthy"
  fi
}

create-cluster() {
  echo "Creating cluster ($hosts)..."
  echo "yes" | run redis-trib create --replicas $replicas $hosts
}

join-cluster() {
  host=$1
  echo "Joining '$host' to the cluster..."
  shift
  run redis-trib add-node $@ $host $this_host
}

start-loop(){
  sleep_sec=10
  while true ; do
    if [[ `hostname` =~ -0$ ]] ; then # Allow the first host to manage the cluster
      echo "Managing cluster..."
      hosts=`kubectl get pods -l=$labels --template="{{range \\$i, \\$e :=.items}}{{\\$e.status.podIP}}:$redis_port {{end}}" | sed "s/ $//" | tr " " "\n" | grep -E "^[0-9]"`
      host_count=`echo "$hosts" | wc -l | tr -d " "`
      if [[ "$host_count" -ge "$min_hosts" ]] ; then # wait for the available hosts to be greater than the minimum required
        if ! status ; then # If the cluster has not initialized, then initialize it
          create-cluster

        else # Join the other nodes to the cluster
          i=0 # index
          for host in $hosts ; do # if there is more then one replica, then ensure we join the proper number of nodes as slaves
            echo "Checking host #$i in list: $host..."
            status $host &> /dev/null || if [[ $replicas -gt "0" && $(($i % ($replicas + 1))) != "0" ]] ; then
              join-cluster $host --slave
            else # join the cluster as a master
              join-cluster $host
            fi

            i=$(($i + 1)) # increment the index
          done
          sleep_sec=30
        fi
      else # Show an error
        >&2 echo "Not enough hosts yet to initialize the cluster (have $host_count, need $min_hosts)..."
      fi
    else
      sleep_sec=8640000
      echo "Not managing cluster..."
    fi

    echo "Sleeping $sleep_sec seconds..."
    sleep $sleep_sec # Sleep before the next cycle
  done
}

case $1 in
status)
  status
  ;;
*)
  start-loop
  ;;
esac
