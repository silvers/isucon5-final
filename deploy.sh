#!/bin/bash
set -ux

cd $(dirname $0)

if [ `uname -s` = 'Darwin' ]; then
    for server in "isucon5-final-app1" "isucon5-final-app2" "isucon5-final-app3"; do
        gcloud compute --project "isucon5-qualifier-oniyanma" ssh --zone "asia-east1-c" $server -- sudo -H /home/isucon/isucon5-final/deploy.sh
    done
elif [ `whoami` != 'isucon' ]; then
    sudo -u isucon -H $PWD/deploy.sh
else
    git reset --hard
    git pull
    ./config/install.sh
    sudo -H service memcached restart
fi
