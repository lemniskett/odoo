ARG PYTHON_VER
FROM python:${PYTHON_VER}-buster

ARG \
    ARCH \
    LEGACY \
    ODOO_VER \
    NODEJS_VER \
    WKHTMLTOPDF_VER \
    S6_VER \
    PSQL_VER \
    RELEASE_CODENAME=buster \
    DEBIAN_FRONTEND=noninteractive

# Install PostgreSQL client
RUN set -ex; \
    echo "deb http://apt.postgresql.org/pub/repos/apt ${RELEASE_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -; \
    apt-get update; \
    apt-get install -y postgresql-client-${PSQL_VER}

# Install Odoo Dependencies
RUN set -ex; \
    curl -L https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VER}/wkhtmltox_${WKHTMLTOPDF_VER}.${RELEASE_CODENAME}_${ARCH}.deb \
        -o /tmp/wkhtmltopdf.deb; \
    apt update; \
    apt upgrade -y; \
    apt install --no-install-recommends -y \
        git \
        file \
        curl \
        screen \
        util-linux \
        vim \
        htop \
        libxslt-dev \
        libzip-dev \
        libldap2-dev \
        libsasl2-dev \
        libpq-dev \
        libjpeg-dev \
        gcc \
        g++ \
        build-essential; \
    apt install --no-install-recommends -y /tmp/wkhtmltopdf.deb; \
    rm -f /tmp/wkhtmltopdf.deb

# Install NodeJS
RUN set -ex; \
    curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VER}.x | bash -; \
    apt update; \
    apt install -y --no-install-recommends \
        nodejs; \
    npm install -g rtlcss $([ ! -z "${LEGACY}" ] && echo "less")

# Install Odoo
ENV PIP_CACHE_DIR /opt/odoo/pip-cache
ENV PYTHONPATH /opt/odoo/site-packages
RUN set -ex; \
    curl -L https://github.com/odoo/odoo/archive/${ODOO_VER}.tar.gz \
        -o /tmp/odoo.src.tar.gz; \
    mkdir -p /opt/odoo/server /opt/odoo/logs /opt/odoo/data /opt/odoo/etc /opt/odoo/pip-cache /opt/odoo/extra-addons /opt/odoo/site-packages /opt/odoo/pre-start.d /opt/odoo/post-stop.d; \
    cd /opt/odoo; \
    tar xf /tmp/odoo.src.tar.gz --strip-components=1 -C /opt/odoo/server; \
    rm -f /tmp/odoo.src.tar.gz; \
    pip install --upgrade pip; \
    pip install wheel setuptools phonenumbers; \
    if [ ! -z "${LEGACY}" ]; then sed -i 's/psycopg2.*/psycopg2==2.8.6/g' /opt/odoo/server/requirements.txt; fi; \
    pip install -r /opt/odoo/server/requirements.txt; \
    rm -rf /opt/odoo/pip-cache/*; \
    if [ ! -z "${LEGACY}" ]; then if [ ! -e /opt/odoo/server/odoo-bin ]; then cd /opt/odoo/server; ln -s ./openerp-server ./odoo-bin; fi; fi; \
    if [ ! -z "${LEGACY}" ]; then cd /opt/odoo/site-packages; ln -s ../server/openerp openerp; else cd /opt/odoo/site-packages; ln -s ../server/odoo odoo; fi

# Install S6
RUN set -ex ; \
    curl -L https://github.com/just-containers/s6-overlay/releases/download/${S6_VER}/s6-overlay-${ARCH}-installer \
        -o /tmp/s6-overlay-installer; \
    chmod +x /tmp/s6-overlay-installer; \
    /tmp/s6-overlay-installer .; \
    rm -f /tmp/s6-overlay-installer; \
    mkdir -p /etc/services.d/odoo

# Copy configurations
COPY ./src/cont-init.d/* /etc/cont-init.d/
COPY ./src/services.d/odoo/* /etc/services.d/odoo/
COPY ./src/bin/* /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# Set cwd
WORKDIR /opt/odoo

# Set environment variables
ENV \
    S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    OPTIONS__ADDONS_PATH=server/addons \
    OPTIONS__DATA_DIR=data \
    OPTIONS__LOGFILE=logs/odoo${ODOO_VER}.log \
    OUID=2000 \
    OGID=2000 \
    OARGS=--config=etc/odoo.conf \
    ODOO_STAGE=start
LABEL maintainer="Syahrial Agni Prasetya <syahrial@mplus.software>"

# EXPOSE doesn't actually do anything, it's just gives metadata to the container
EXPOSE 8069 8071 8072

# Run S6
ENTRYPOINT ["/init"]
