#!/bin/bash


get_remote()
{
    
	if ![ -d /vagrant/dev/ ]; then
	git clone  https://github.com/coulonpascal/exchange /vagrant
	fi

}

yum_setup()
{
    pushd /etc/yum.repos.d/
    if [ -f geoshape.repo ]; then
        rm -f geoshape.repo
    fi
    wget https://yum.boundlessps.com/geoshape.repo
    popd
    yum -y install python27-devel \
        python27-virtualenv \
        gcc \
        gcc-c++ \
        make \
        expat-devel \
        db4-devel \
        gdbm-devel \
        sqlite-devel \
        readline-devel \
        zlib-devel \
        bzip2-devel \
        openssl-devel \
        tk-devel \
        gdal-devel-2.0.1 \
        libxslt-devel \
        libxml2-devel \
        libjpeg-turbo-devel \
        zlib-devel \
        libtiff-devel \
        freetype-devel \
        lcms2-devel \
        proj-devel \
        geos-devel \
        postgresql95-devel \
        openldap-devel \
        java-1.8.0-openjdk \
        unzip \
        wget \
        git \
        postgis-postgresql95 \
        elasticsearch \
        rabbitmq-server-3.6.1 \
        libmemcached-devel \
        httpd \

	rpm -ivh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
	yum install -y python-pip
		
    if [ -f /etc/profile.d/settings.sh ]; then
        rm -fr /etc/profile.d/settings.sh
    fi
    cp /vagrant/dev/settings.sh /etc/profile.d/settings.sh
    source /etc/profile.d/settings.sh
}

exchange_setup()
{
    rm -fr /vagrant/.storage/*
    if [ -d /vagrant/.venv ]; then
        rm -fr /vagrant/.venv
    fi

    if [ -d /vagrant/dev/.logs ]; then
        rm -fr /vagrant/dev/.logs
    fi

    mkdir -p /vagrant/dev/.logs

    /usr/local/bin/virtualenv /vagrant/.venv
    source /vagrant/.venv/bin/activate
    pip install -r /vagrant/requirements.txt
    python /vagrant/manage.py makemigrations
    python /vagrant/manage.py migrate account --noinput
    python /vagrant/manage.py migrate --noinput
    python /vagrant/manage.py collectstatic --noinput
    # import default admin and test user
    python /vagrant/manage.py loaddata initial
    # "hotfix, need to find out why it is not importing the categories"
    python /vagrant/manage.py loaddata base_resources
    # migrate account after loaddata to avoid DoesNotExist profile issue
    python /vagrant/manage.py migrate account --noinput

    #echo "from geonode.people.models import Profile; Profile.objects.create_superuser('admin', 'admin@exchange.com', 'exchange', first_name='Administrator', last_name='Exchange')" | python /vagrant/manage.py shell
    #echo "from geonode.people.models import Profile; Profile.objects.create_user('test', 'test@exchange.com', 'exchange', first_name='Test', last_name='User')" | python /vagrant/manage.py shell
    printf "\nsource /vagrant/dev/activate\n" > /home/vagrant/.bash_profile
    if ! grep -q 'django-runserver' /home/vagrant/.bashrc; then
        printf "\nalias django-runserver='/vagrant/.venv/bin/python /vagrant/manage.py runserver 0.0.0.0:8000'" >> /home/vagrant/.bashrc
    fi
    if ! grep -q 'django-collectstatic' /home/vagrant/.bashrc; then
        printf "\nalias django-collectstatic='/vagrant/.venv/bin/python /vagrant/manage.py collectstatic'" >> /home/vagrant/.bashrc
    fi
    if ! grep -q 'django-migrate' /home/vagrant/.bashrc; then
        printf "\nalias django-migrate='/vagrant/.venv/bin/python /vagrant/manage.py migrate'" >> /home/vagrant/.bashrc
    fi
    chmod -R 755 /vagrant/.venv && chown -R vagrant.vagrant /vagrant/.venv
}

geoserver_setup()
{
    if [ ! -d /vagrant/dev/.geoserver ]; then
        mkdir -p /vagrant/dev/.geoserver
    fi
    if [ ! -f /vagrant/dev/.geoserver/jetty-runner-9.3.8.v20160314.jar ]; then
        echo "=> Downloading jetty-runner.jar"
	    pushd /vagrant/dev/.geoserver
	    wget http://central.maven.org/maven2/org/eclipse/jetty/jetty-runner/9.3.8.v20160314/jetty-runner-9.3.8.v20160314.jar > /dev/null 2>&1
	    popd
    fi
    if [ ! -f /vagrant/dev/.geoserver/geoserver.war ]; then
	    echo "=> Downloading GeoServer web archive"
	    pushd /vagrant/dev/.geoserver
	    wget https://s3.amazonaws.com/boundlessps-public/GVS/geoserver.war > /dev/null 2>&1
	    unzip geoserver.war -d geoserver
	    popd
    fi
    if [ -d /vagrant/dev/.geoserver/data ]; then
        rm -fr /vagrant/dev/.geoserver/data
    fi
    cp -R /vagrant/dev/.geoserver/geoserver/data /vagrant/dev/.geoserver
    sed -i.bak 's@<baseUrl>\([^<][^<]*\)</baseUrl>@<baseUrl>http://localhost/</baseUrl>@' \
               /vagrant/dev/.geoserver/data/security/auth/geonodeAuthProvider/config.xml
    mkdir -p /vagrant/dev/.geoserver/data/geogig
    printf "[user]\nname = admin\nemail = exchange@boundlessgeo.com\n" > /vagrant/dev/.geoserver/data/geogig/.geogigconfig
    chmod -R 755 /vagrant/dev/.geoserver && chown -R vagrant.vagrant /vagrant/dev/.geoserver
}

database_setup()
{
    if [ -f /etc/init.d/exchange ]; then
        service exchange stop > /dev/null 2>&1
    fi
    if [ ! -d /var/lib/pgsql/9.5/data/base ]; then
        service postgresql-9.5 initdb
        chkconfig postgresql-9.5 on
        sed -i.orig 's/peer$/trust/g' /var/lib/pgsql/9.5/data/pg_hba.conf
        sed -i.orig 's/ident$/md5/g' /var/lib/pgsql/9.5/data/pg_hba.conf
        service postgresql-9.5 restart > /dev/null 2>&1
    fi
    PGUSER=$(psql -U postgres -c '\du' | cut -d \| -f 1 | grep -w exchange | wc -l)
    if [ "${PGUSER}" -eq 0 ]; then
        psql -U postgres -c "CREATE USER exchange WITH PASSWORD 'boundless';"
    else
        psql -U postgres -c "ALTER USER exchange WITH PASSWORD 'boundless';"
    fi
    EXCHANGE_DB=$(psql -U postgres -lqt | cut -d \| -f 1 | grep -w exchange | wc -l)
    if [ "${EXCHANGE_DB}" -eq 1 ]; then
        psql -U postgres -c "DROP DATABASE exchange;"
    fi
    psql -U postgres -c "CREATE DATABASE exchange OWNER exchange;"
    EXCHANGE_DATA_DB=$(psql -U postgres -lqt | cut -d \| -f 1 | grep -w exchange_data | wc -l)
    if [ "${EXCHANGE_DATA_DB}" -eq 1 ]; then
        psql -U postgres -c "DROP DATABASE exchange_data;"
    fi
    psql -U postgres -c "CREATE DATABASE exchange_data OWNER exchange;"
    psql -U postgres -d exchange_data -c 'CREATE EXTENSION postgis;'
    psql -U postgres -d exchange_data -c 'GRANT ALL ON geometry_columns TO PUBLIC;'
    psql -U postgres -d exchange_data -c 'GRANT ALL ON spatial_ref_sys TO PUBLIC;'
}

dev_init()
{
    if [ -f /etc/httpd/conf.d/httpd.conf ]; then
        rm -f /etc/httpd/conf.d/httpd.conf
    fi
    cp /vagrant/dev/httpd.conf /etc/httpd/conf.d/httpd.conf
    if [ -f etc/init.d/exchange ]; then
        rm -f /etc/init.d/exchange
    fi
    cp /vagrant/dev/exchange.init /etc/init.d/exchange
    chmod +x /etc/init.d/exchange
    service exchange restart > /dev/null 2>&1
}

service_setup()
{
  service httpd restart
  service elasticsearch restart
  service rabbitmq-server restart
  rabbitmqctl stop_app
  rabbitmqctl reset
  rabbitmqctl start_app
}
get_remote
yum_setup
database_setup
exchange_setup
geoserver_setup
dev_init
service_setup
