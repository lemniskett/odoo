ARG \
    PYTHON_VER=3.7 \
    ODOO_VER
FROM python:${PYTHON_VER}-buster as builder
ARG \
    ARCH \
    ODOO_VER \
    RELEASE_CODENAME=buster \
    DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
RUN set -ex; \
    curl -L https://raw.githubusercontent.com/odoo/odoo/${ODOO_VER}/requirements.txt -o /tmp/requirements.txt; \
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
    RELEASE_CODENAME=buster \
    DEBIAN_FRONTEND=noninteractive \
    S6_VER=3.1.2.1 \
    PSQL_VER=14 \
    WKHTMLTOPDF_VER=0.12.6-1 \
    NODEJS_VER=16 \
    ARCH \
    ODOO_VER 
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
        locales \
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
RUN set -ex; \
    curl -L https://github.com/odoo/odoo/archive/${ODOO_VER}.tar.gz \
        -o /tmp/odoo.src.tar.gz; \
    mkdir -p /opt/odoo/server /opt/odoo/logs /opt/odoo/data /opt/odoo/etc /opt/odoo/pip-cache /opt/odoo/extra-addons; \
    cd /opt/odoo; \
    tar xf /tmp/odoo.src.tar.gz --strip-components=1 -C /opt/odoo/server; \
    rm -f /tmp/odoo.src.tar.gz; \
    ln -s server s; ln -s extra-addons e;

# Install S6
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VER}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VER}/s6-overlay-x86_64.tar.xz /tmp
RUN set -ex ; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz; \
    mkdir -p /etc/services.d/odoo /etc/services.d/odootail

# Copy configurations
COPY ./src/cont-init.d/* /etc/cont-init.d/
COPY ./src/services.d/odoo/* /etc/services.d/odoo/
COPY ./src/services.d/odootail/* /etc/services.d/odootail/
COPY ./src/bin/* /usr/local/bin/
RUN set -ex; \
    chmod +x /usr/local/bin/* /etc/cont-init.d/* /etc/services.d/odoo/* /etc/services.d/odootail/*; \
    useradd -d /opt/odoo odoo; \
    chown -R odoo:odoo /opt/odoo

# Set locale
RUN set -ex; \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen; \
    locale-gen

# Set cwd
WORKDIR /opt/odoo

# Set environment variables
ENV \
    S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    ODOOCONF__options__addons_path=server/addons \
    ODOOCONF__options__data_dir=data \
    ODOOCONF__options__logfile=logs/odoo-${ODOO_VER}.log \
    ODOOCONF__options__list_db=True \
    OARGS=--config=etc/odoo.conf \
    ODOO_STAGE=start \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8
LABEL maintainer="Syahrial Agni Prasetya <syahrial@mplus.software>"

# EXPOSE doesn't actually do anything, it's just gives metadata to the container
EXPOSE 8069 8072

# Run S6
ENTRYPOINT ["/init"]