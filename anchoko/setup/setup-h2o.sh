#!/bin/sh
set -eu

H2O_REVISION=1.7.0

wget -q https://github.com/h2o/h2o/archive/v$H2O_REVISION.tar.gz
tar xzf v$H2O_REVISION.tar.gz
rm v$H2O_REVISION.tar.gz

cd h2o-$H2O_REVISION
cmake -DWITH_BUNDLED_SSL=on -DCMAKE_INSTALL_PREFIX=/opt/h2o/v$H2O_REVISION .
make
sudo -H make install
