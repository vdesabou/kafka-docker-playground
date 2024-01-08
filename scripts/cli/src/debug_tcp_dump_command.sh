container="${args[--container]}"
port="${args[--port]}"
duration="${args[--duration]}"
filename="tcp-dump-$container-$port-`date '+%Y-%m-%d-%H-%M-%S'`.pcap"

set +e
docker exec $container type tcpdump > /dev/null 2>&1
if [ $? != 0 ]
then
    tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "Could not find current CP version from docker ps"
        exit 1
    fi

    logwarn "tcpdump is not installed on container $container, attempting to install it"
    
    if [[ "$tag" == *ubi8 ]] || version_gt $tag "5.9.0"
    then
      if [ `uname -m` = "arm64" ]
      then
        docker exec --privileged --user root $container bash -c "rpm -i --nosignature https://rpmfind.net/linux/centos/8-stream/AppStream/aarch64/os/Packages/tcpdump-4.9.3-2.el8.aarch64.rpm"
      else
        docker exec --privileged --user root $container bash -c "curl http://mirror.centos.org/centos/8-stream/AppStream/x86_64/os/Packages/tcpdump-4.9.3-1.el8.x86_64.rpm -o tcpdump-4.9.3-1.el8.x86_64.rpm && rpm -Uvh tcpdump-4.9.3-1.el8.x86_64.rpm"
      fi
    else
      docker exec --privileged --user root $container bash -c "apt-get update && echo bind-utils openssl unzip findutils net-tools nc jq which iptables iproute tree | xargs -n 1 apt-get install --force-yes -y && rm -rf /var/lib/apt/lists/*"
    fi
fi
docker exec $container type tcpdump > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ tcpdump could not be installed"
    exit 1
fi
set -e

set +e
docker exec --privileged --user root ${container} bash -c "killall tcpdump" > /dev/null 2>&1
set -e

if [[ -n "$port" ]]
then
  log "🕵️‍♂️ Taking tcp dump on container ${container} and port ${port} for ${duration} seconds..."
  docker exec -d --privileged --user root ${container} bash -c "tcpdump -w /tmp/${filename} port ${port}"
else
  log "🕵️‍♂️ Taking tcp dump on container ${container} and all ports for ${duration} seconds..."
  docker exec -d --privileged --user root ${container} bash -c "tcpdump -w /tmp/${filename}"
fi

if [ $? -eq 0 ]
then
    playground container get-ip-addresses
    sleep $duration
    set +e
    docker exec --privileged --user root ${container} bash -c "killall tcpdump" > /dev/null 2>&1
    set -e
    log "🌶️ tcp dump is available at ${filename}"
    docker cp ${container}:/tmp/${filename} ${filename}
    if [[ $(type -f wireshark 2>&1) =~ "not found" ]]
    then
        logwarn "🦈 wireshark is not installed, grab it at https://www.wireshark.org/"
        exit 0
    else
        log "🦈 Opening ${filename} with wireshark"
        wireshark ${filename}
    fi 
else
    logerror "❌ Failed to take tcp dump"
fi


