
ARG PYTHON_VER ODOO_VER LEGACY
FROM python:${PYTHON_VER}-buster as builder
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
ENV PYTHONUNBUFFERED=1
RUN set -ex; \
    curl -L https://raw.githubusercontent.com/odoo/odoo/${ODOO_VER}/requirements.txt -o /tmp/requirements.txt; \
    if [ ! -z "${LEGACY}" ]; then sed -i 's/psycopg2.*/psycopg2==2.8.6/g' /tmp/requirements.txt; fi; \
    apt update; \
    apt upgrade -y; \
    apt install --no-install-recommends -y \
        git \
        file \
        curl \
        util-linux \
        libxslt-dev \
        libzip-dev \
        libldap2-dev \
        libsasl2-dev \
        libpq-dev \
        libjpeg-dev \
        gcc \
        g++ \
        build-essential;
RUN pip wheel -r /tmp/requirements.txt  --wheel-dir /usr/src/app/wheels    

FROM python:${PYTHON_VER}-buster as runner
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
ENV PYTHONUNBUFFERED=1

# Install PostgreSQL client
RUN set -ex; \
    echo "deb http://apt.postgresql.org/pub/repos/apt ${RELEASE_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -; \
    apt-get update; \
    apt-get install -y postgresql-client-${PSQL_VER}

# Install Odoo Dependencies
COPY --from=builder /usr/src/app/wheels  /wheels/
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
        htop; \
    pip install --no-cache-dir --no-index --find-links=/wheels/ /wheels/*; \
    rm -rf /wheels/; \
    apt install --no-install-recommends -y /tmp/wkhtmltopdf.deb; \
    rm -f /tmp/wkhtmltopdf.deb

# Install NodeJS
RUN set -ex; \
    curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VER}.x | bash -; \
    apt update; \
    apt install -y --no-install-recommends \
        nodejs; \
    npm install -g rtlcss less@3.0.4

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
    ln -s server s; ln -s extra-addons e; \
    if [ ! -z "${LEGACY}" ]; then if [ ! -e /opt/odoo/server/odoo-bin ]; then cd /opt/odoo/server; ln -s ./openerp-server ./odoo-bin; fi; fi; \
    if [ ! -z "${LEGACY}" ]; then cd /opt/odoo/site-packages; ln -s ../server/openerp openerp; else cd /opt/odoo/site-packages; ln -s ../server/odoo odoo; fi; \
    if [ "$ODOO_VER" = "8.0" ]; then cd /opt/odoo/server; wget https://github.com/odoo/odoo/commit/0baf5f9916a7fde4d0d4fa97c1ee70059ae886fb.patch -O allow_root_user.patch; patch -p1 -i allow_root_user.patch; fi

# Install S6
RUN set -ex ; \
    curl -L https://github.com/just-containers/s6-overlay/releases/download/${S6_VER}/s6-overlay-${ARCH}-installer \
        -o /tmp/s6-overlay-installer; \
    chmod +x /tmp/s6-overlay-installer; \
    /tmp/s6-overlay-installer .; \
    rm -f /tmp/s6-overlay-installer; \
    mkdir -p /etc/services.d/odoo /etc/services.d/odootail

# Copy configurations
COPY ./src/cont-init.d/* /etc/cont-init.d/
COPY ./src/services.d/odoo/* /etc/services.d/odoo/
COPY ./src/services.d/odootail/* /etc/services.d/odootail/
COPY ./src/bin/* /usr/local/bin/
RUN chmod +x /usr/local/bin/* /etc/cont-init.d/* /etc/services.d/odoo/* /etc/services.d/odootail/*

# Set cwd
WORKDIR /opt/odoo

# Set environment variables
ENV \
    S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    ODOOCONF__options__addons_path=server/addons \
    ODOOCONF__options__data_dir=data \
    ODOOCONF__options__logfile=logs/odoo${ODOO_VER}.log \
    OARGS=--config=etc/odoo.conf \
    ODOO_STAGE=start
LABEL maintainer="Syahrial Agni Prasetya <syahrial@mplus.software>"

# EXPOSE doesn't actually do anything, it's just gives metadata to the container
EXPOSE 8069 8072

# Add Healthcheck, port settings must not be changed.
HEALTHCHECK CMD healthcheck

# Run S6
ENTRYPOINT ["/init"]
