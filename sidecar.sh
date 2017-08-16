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

# Retry a command until max tries is reached
try_step_interval=${TRY_STEP_INTERVAL-"1"}
max_tries=${MAX_TRIES-"3"}
retry() {
  local tries=0
  until $@ ; do
    status=$?
    tries=$(($tries + 1))
    if [ $tries -gt $max_tries ] ; then
      log "failed to run \`$@\` after $max_tries tries..."
      return $status
    fi
    sleepsec=$(($tries * $try_step_interval))
    log "failed: \`$@\`, retyring in $sleepsec seconds..."
    sleep $sleepsec
  done
  return $?
}

# Call the cli for the redis instance
cli(){
  debug redis-cli -p $redis_port $@
  retry timeout 5 redis-cli -p $redis_port $@
}

# Call the cli for the sentinel instance
sentinel-cli(){
  debug redis-cli -p $sentinel_port $@
  retry timeout 5 redis-cli -p $sentinel_port $@
}

# Ping redis to see if it is up
ping() {
  cli ping > /dev/null
}

# Ping sentinel to see if it is up
ping-sentinel() {
  sentinel-cli ping > /dev/null
}

# Ping redis and sentinel to see if they are up
ping-both(){
  ping && ping-sentinel
}

# Get the role for this node or the specified ip/host
role() {
  host=${1-"127.0.0.1"}
  (cli -h $host info || echo -n "role:none") | grep "role:" | sed "s/role://" | tr -d "\n" | tr -d "\r"
}

# Convert this node to a slave of the specified master
become-slave-of() {
  host=$1
  log "becoming a slave of $host"
  sentinel-monitor $host
  cli slaveof $host $redis_port
}

# Tell sentinel to monitor a particular master
sentinel-monitor() {
  host=$1
  sentinel-cli sentinel remove $group_name
  sentinel-cli sentinel monitor $group_name $host $redis_port $quorum
  sentinel-cli sentinel set $group_name down-after-milliseconds $down_after_milliseconds
  sentinel-cli sentinel set $group_name failover-timeout $failover_timeout
  sentinel-cli sentinel set $group_name parallel-syncs $parallel_syncs
}

# Find the first host that identifys as a master
active-master(){
  master=""
  for host in `hosts` ; do
    debug "checking to see if '$host' is master..."
    if [ "$(role $host)" = "master" ] ; then
      debug "found master: '$host'"
      master=$host
      break
    fi
  done
  if [ -z "$master" ] ; then
    debug "found no active master"
  fi
  echo -n $master
}

# Get all the current redis-node ips
hosts(){
  kubectl get pods -l=$labels \
    --template="{{range \$i, \$e :=.items}}{{\$e.status.podIP}} {{end}}" \
  | sed "s/ $//" | tr " " "\n" | grep -E "^[0-9]" | grep --invert-match $ip
}

# Boot the sidecar
boot(){
  log "booting: $ip"

  # set roll label to "none"
  set-role-label "none"

  # wait, as things may still be failing over
  sleep $(($failover_timeout / 1000))

  # Check to ensure both the sentinel and redis are up,
  # if not, exit with an error
  ping-both || panic "redis and/or sentinel is not up"

  # Store the current active-master to a variable
  master=$(active-master)

  if [[ -n "$master" ]] ; then
    # There is a master, become a slave
    become-slave-of $master
  else
    # There is not active master, so become the master
    log "booted as master"
    sentinel-monitor $ip
  fi
  log "node ready!"
  touch booted
}

# Set the role label on the pod to the specified value
set-role-label(){
  log "setting role label to $1"
  kubectl label --overwrite pods `hostname` role=$1
}

# Print a message to stderr
log () {
  >&2 echo $@
}

# debug
debug () {
  if [ "$VERBOSE" = "true" ] || [ "$DEBUG" = "true" ] ; then
    >&2 echo $@
  fi
}

# Exit, printing an error message
panic () {
  log $1
  exit 1
}

monitor-label(){
  last_role=none
  while true ; do
    # Check to ensure both the sentinel and redis are up,
    # if not, exit with an error
    ping-both || panic "redis and/or sentinel is not up"

    # Store the current role to a variable
    current_role=`role`

    # Monitor the role, if it changes, set the label accordingly
    if [[ "$last_role" != "$current_role" ]] ; then
      set-role-label $current_role
      last_role=$current_role
    fi

    # Don't ever allow multiple masters
    if [ "$current_role" = "master" ] ; then
      if [ -n "$(active-master)" ] ; then
        if [ "$(active-master)" != $ip ] ; then
          # If I am a master and not the active one, then just become a slave
          log "not the active master!"
          become-slave-of $(active-master)
        fi
      fi
    fi
    sleep 1
  done
}

boot
monitor-label
