#!/bin/bash

# Use case 1: four PrestaShop versions on one LAMP stack
# (MariaDB + phpMyAdmin), based on the LAMP templates.

# start clean: remove a previous run of this use case
docker rm -f $(docker ps -aq --filter name=myLampPrj_) 2>/dev/null
rm -rf "$HOME/MyDockers/myLampPrj" 2>/dev/null


source "$HOME/MyDockersScripts/myDockersCreate.sh"
source "$HOME/MyDockersScripts/myDockersAdd.sh"
source "$HOME/MyDockersScripts/myDockersBuild.sh"
source "$HOME/MyDockersScripts/myDockersInitDBs.sh"
source "$HOME/MyDockersScripts/myDockersHints.sh"

myDockersCreate myLampPrj ps91 8611 8612 8613 php:8.5-apache

myDockersAdd myLampPrj ps8_last php:8.1-apache
myDockersAdd myLampPrj ps_1_7_last php:7.2-apache
myDockersAdd myLampPrj ps_1_6_last php:7.1-apache

myDockersBuild myLampPrj

# start the stack
cd "$HOME/MyDockers/myLampPrj" && docker compose up -d

myDockersInitDBs myLampPrj

myDockersHints myLampPrj
