#!/bin/bash
# exit on failure
set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

apt-get update -y && apt-get install -y wget ca-certificates lsb-release git python python-pip python-dev nginx python-setuptools sudo libssl-dev libxml2-dev libossp-uuid-dev gettext libperl-dev libreadline-dev #upervisor



#################### install postgresql 9.6 from source ####################
cd /tmp
wget https://ftp.postgresql.org/pub/source/v9.6.0/postgresql-9.6.0.tar.gz
tar -zxvf postgresql-9.6.0.tar.gz
cd postgresql-9.6.0
# alternate location?
./configure --prefix=/usr/local --enable-nls --with-perl --with-python --with-openssl --with-ossp-uuid --with-libxml
make world
make install-world

adduser --gecos "Postgresql" --disabled-password --no-create-home --disabled-login postgres

mkdir --parents /var/lib/postgresql/aquameta
mkdir --parents /var/log/postgresql
chown postgres:postgres /var/lib/postgresql/aquameta
chown postgres:postgres /var/log/postgresql

sudo -u postgres /usr/local/bin/initdb -D /var/lib/postgresql/aquameta
sudo -u postgres /usr/local/bin/pg_ctl -D /var/lib/postgresql/aquameta -l /var/log/postgresql/postgresql.log start

apt-get install -y pgxnclient fuse libfuse-dev sendmail
# needs pg_config but not in $PATH yet
pgxn install multicorn
pgxn install pgtap
pip install requests sphinx sphinx-autobuild fusepy
locale-gen "en_US.UTF-8" && dpkg-reconfigure locales

# FQDN for sendmail
echo `tail -1 /etc/hosts`.localdomain >> /etc/hosts

#################### nginx/uwsgi server ###############################
# setup /etc/nginx settings
cp $DIR/core/004-http_server/servers/uwsgi/conf/nginx/aquameta_endpoint.conf /etc/nginx/sites-available
cd /etc/nginx/sites-enabled
rm ./default
ln -s ../sites-available/aquameta_endpoint.conf


# build the aquameta db python egg
cd $DIR/core/004-http_server/servers/uwsgi
pip install .


# ADD docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# pgfs
mkdir /mnt/aquameta


#################### build aquameta ###############################
createdb aquameta

cd $DIR

echo "Loading requirements ..."
cat core/requirements.sql | psql aquameta

echo "Loading core/*.sql ..."
cat core/0*/0*.sql  | psql -a aquameta


echo "Loading bundles-enabled/*.sql ..."
cat bundles-enabled/*.sql | psql -a aquameta

echo "Checking out head commit of every bundle ..."
echo "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" | psql aquameta

### echo "Loading semantics ..."
### cat core/0*/semantics.sql  | psql -a aquameta
### 
### echo "Loading default permissions ..."
### cat core/004-http_server/default_permissions.sql  | psql -a aquameta
### 
### echo "Loading mimetypes ..."
### cat core/004-http_server/mimetypes.sql  | psql -a aquameta
### 




# audit this...
echo "host all  all 0.0.0.0/0  md5"   >> /var/lib/postgresql/aquameta/pg_hba.conf
sed -i "s/^local   all.*$/local all all trust/" /var/lib/postgresql/aquameta/pg_hba.conf
echo "listen_addresses='*'" >> /var/lib/postgresql/aquameta/postgresql.conf
# psql -c "alter role postgres password 'postgres'" aquameta

# Install pgtap
# RUN psql -c "create extension pgtap" aquameta

# Install FS FDW
cd $DIR/core/002-filesystem/fs_fdw
pip install . --upgrade
cat fs_fdw.sql | psql aquameta



# start uwsgi
mkdir /var/log/aquameta
uwsgi --die-on-term --emperor $DIR/core/004-http_server/servers/uwsgi/conf/uwsgi/aquameta_db.ini & # >> /var/log/aquameta/uwsgi.log &

sudo -u postgres /usr/local/bin/pg_ctl -D /var/lib/postgresql/aquameta -l /var/log/postgresql/postgresql.log start