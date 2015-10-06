#!/bin/bash

for i in $(docker ps -a | grep -v "CONTAINER ID"| cut -f 1 -d ' '); do
    docker kill $i >/dev/null
    docker rm $i
done
