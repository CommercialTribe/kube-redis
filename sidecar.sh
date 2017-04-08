#!/usr/bin/env bash
set -e
[[ $DEBUG == "true" ]] && set -x

# Set vars
ip=${POD_IP-`hostname -i`}                                  # ip address of pod
redis_port=${NODE_PORT_NUMBER-6379}                         # redis port
sentinel_port=${SENTINEL_PORT_NUMBER-26379}                 # sentinel port
group_name="$POD_NAMESPACE-$(hostname | sed 's/-[0-9]$//')" # master group name
quorum="${SENTINEL_QUORUM-2}"                               # quorum needed

# Sentinel options
down_after_milliseconds=${DOWN_AFTER_MILLESECONDS-1000}
failover_timeout=${FAILOVER_TIMEOUT-$(($down_after_milliseconds * 10))}
parallel_syncs=${PARALEL_SYNCS-1}

# Get all the kubernetes pods
labels=`echo $(cat /etc/pod-info/labels) | tr -d '"' | tr " " ","`

try_step_interval=${TRY_STEP_INTERVAL-"1"}
max_tries=${MAX_TRIES-"3"}
retry() {
  local tries=0
  until $@ ; do
    status=$?
    tries=$(($tries + 1))
    if [ $tries -gt $max_tries ] ; then
      >&2 echo "Failed to run \`$@\` after $max_tries tries..."
      return $status
    fi
    sleepsec=$(($tries * $try_step_interval))
    >&2 echo "Failed: \`$@\`, retyring in $sleepsec seconds..."
    sleep $sleepsec
  done
  return $?
}

cli(){
  retry redis-cli -p $redis_port $@
}

sentinel-cli(){
  retry redis-cli -p $sentinel_port $@
}

ping() {
  cli ping > /dev/null
}

ping-sentinel() {
  sentinel-cli ping > /dev/null
}

ping-both(){
  ping && ping-sentinel
}

role() {
  host=${1-"127.0.0.1"}
  (cli -h $host info || echo -n "role:none") | grep "role:" | sed "s/role://" | tr -d "\n" | tr -d "\r"
}

become-slave-of() {
  host=$1
  cli slaveof $host $redis_port
}

sentinel-monitor() {
  host=$1
  sentinel-cli sentinel monitor $group_name $host $redis_port $quorum
  sentinel-cli sentinel set $group_name down-after-milliseconds $down_after_milliseconds
  sentinel-cli sentinel set $group_name failover-timeout $failover_timeout
  sentinel-cli sentinel set $group_name parallel-syncs $parallel_syncs
}

active-master(){
  master=""
  for host in `hosts` ; do
    if [[ `role $host` = "master" ]] ; then
      master=$host
      break
    fi
  done
  echo -n $master
}

hosts(){
  echo ""
  kubectl get pods -l=$labels \
    --template="{{range \$i, \$e :=.items}}{{\$e.status.podIP}} {{end}}" \
  | sed "s/ $//" | tr " " "\n" | grep -E "^[0-9]" | grep --invert-match $ip
}

boot(){
  set-role-label "none" # set roll label to nothing
  sleep $(($failover_timeout / 1000))
  ping-both
  master=$(active-master)
  if [[ -n "$master" ]] ; then
    become-slave-of $master
    sentinel-monitor $master
  else
    sentinel-monitor $ip
  fi
  echo "Ready!"
  touch booted
}

set-role-label(){
  kubectl label --overwrite pods `hostname` role=$1
}

monitor-label(){
  last_role=none
  while true ; do
    ping-both || exit 1
    current_role=`role`
    if [[ "$last_role" != "$current_role" ]] ; then
      set-role-label $current_role
      last_role=$current_role
    fi
    sleep 1
  done
}

boot
monitor-label
