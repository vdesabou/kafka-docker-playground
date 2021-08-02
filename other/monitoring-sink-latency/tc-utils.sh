#!/bin/bash

container_to_name() {
    container=$1
    echo "${PWD##*/}_${container}_1"
}

container_to_ip() {
    if [ $# -lt 1 ]; then
        echo "Usage: container_to_ip container"
    fi
    echo $(docker inspect $1 -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
}

clear_traffic_control() {
    if [ $# -lt 1 ]; then
        echo "Usage: clear_traffic_control src_container"
    fi

    src_container=$1

    echo "Removing all traffic control settings on $src_container"

    # Delete the entry from the tc table so the changes made to tc do not persist
    docker exec --privileged -u0 -t $src_container tc qdisc del dev eth0 root 2>&1
}

get_latency() {
    if [ $# -lt 2 ]; then
        echo "Usage: get_latency src_container dst_container"
    fi
    src_container=$1
    dst_container=$2
    docker exec --privileged -u0 -t $src_container ping $dst_container -c 4  | tail -1 | awk -F '/' '{print $5}'
}

# https://serverfault.com/a/906499
add_latency() {
    if [ $# -lt 3 ]; then
        echo "Usage: add_latency src_container dst_container latency"
        echo "Exemple: add_latency container-1 container-2 100ms"
    fi

    src_container=$1
    dst_container_ip=$(container_to_ip $2)
    latency=$3

    echo "Adding $latency from $src_container to $2"

    # Add a classful priority queue which lets us differentiate messages.
    # This queue is named 1:.
    # Three children classes, 1:1, 1:2 and 1:3, are automatically created.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 root handle 1: prio 2>&1


    # Add a filter to the parent queue 1: (also called 1:0). The filter has priority 1 (if we had more filters this would make a difference).
    # For all messages with the ip of dst_container_ip as their destination, it routes them to class 1:1, which
    # subsequently sends them to its only child, queue 10: (All messages need to  "end up" in a queue).
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $dst_container_ip flowid 1:1 2>&1

    # Route the rest of the of the packets without any control.
    # Add a filter to the parent queue 1:. The filter has priority 2.
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2 2>&1
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2 2>&1

    # Add a child queue named 10: under class 1:1. All outgoing packets that will be routed to 10: will have delay applied them.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:1 handle 10: netem delay $latency 2>&1

    # Add a child queue named 20: under class 1:2
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:2 handle 20: sfq 2>&1
}

