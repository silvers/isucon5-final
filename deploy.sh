#!/bin/bash
set -x

cd $(dirname $0)

branch="$1"

if [ `uname -s` = 'Darwin' ]; then
    for server in "isucon5-final-app1" "isucon5-final-app2" "isucon5-final-app3"; do
        gcloud compute --project "isucon5-qualifier-oniyanma" ssh --zone "asia-east1-c" $server -- sudo -H /home/isucon/isucon5-final/deploy.sh $branch
    done
elif [ `whoami` != 'isucon' ]; then
    sudo -u isucon -H git reset --hard
    sudo -u isucon -H git pull
    sudo -u isucon -H $PWD/deploy.sh $branch
else
    git reset --hard
    git pull
    if [ $branch != "" ]; then
        git checkout $branch
        git pull
    fi
    ./config/install.sh
fi
