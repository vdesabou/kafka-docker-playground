#!/bin/bash

docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml down -v