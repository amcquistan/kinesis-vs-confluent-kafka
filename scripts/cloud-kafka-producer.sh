#!/bin/bash

kafka-console-producer --broker-list $1 --topic $2 --producer.config ./client.properties
