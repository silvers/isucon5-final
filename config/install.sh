#!/bin/bash
set -ux

cd $(dirname $0)

sudo -H cp -R hosts /etc/hosts

for daemon in "supervisor" "h2o"; do
    sudo -H rm -rf /etc/$daemon
    sudo -H cp -R $daemon /etc/$daemon
done

sudo -H supervisorctl reload

if [ `hostname` != 'isucon5-final-app1' ]; then
    sleep 6
    sudo -H supervisorctl stop h2o
fi

