#!/bin/bash

# Use case 2, with PostgreSQL: two PHP versions on one LAPP stack
# (PostgreSQL + Adminer), based on the LAPP templates.

# start clean: remove a previous run of this use case
docker rm -f $(docker ps -aq --filter name=myLappPrj_) 2>/dev/null
rm -rf "$HOME/MyDockers/myLappPrj" 2>/dev/null

source "$HOME/MyDockersScripts/myDockersCreate.sh"
source "$HOME/MyDockersScripts/myDockersAdd.sh"
source "$HOME/MyDockersScripts/myDockersBuild.sh"
source "$HOME/MyDockersScripts/myDockersInitDBs.sh"
source "$HOME/MyDockersScripts/myDockersHints.sh"

myDockersCreate myLappPrj php82web 8601 8602 8603 php:8.5-apache LAPP

myDockersAdd myLappPrj php71web php:7.1-apache LAPP

myDockersBuild myLappPrj

# start the stack
cd "$HOME/MyDockers/myLappPrj" && docker compose up -d

# create the databases and users, and import the initial data
myDockersInitDBs myLappPrj

myDockersHints myLappPrj
