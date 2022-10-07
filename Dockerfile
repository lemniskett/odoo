ARG \
    PYTHON_VERSION=3.7 \
    ALPINE_VERSION=3.16
FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION} as builder
ARG ODOO_VERSION
ENV PYTHONUNBUFFERED=1
RUN set -ex; \
    echo 'INPUT ( libldap.so )' > /usr/lib/libldap_r.so; \
    wget https://raw.githubusercontent.com/odoo/odoo/${ODOO_VERSION}/requirements.txt -O /tmp/requirements.txt; \
    apk update; \
    apk add --no-cache \
        git \
        file \
        curl \
        util-linux \
        libxslt-dev \
        libzip-dev \
        openldap-dev \
        libpq-dev \
        libjpeg-turbo-dev \
        libffi-dev \
        openssl-dev \
        gcc \
        g++ \
        make \
        musl-dev;
RUN pip wheel -r /tmp/requirements.txt  --wheel-dir /usr/src/app/wheels    

FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION} as runner
LABEL maintainer="Syahrial Agni Prasetya <syahrial@mplus.software>"
ARG \
    S6_VERSION=3.1.2.1 \
    ARCH \
    ODOO_VERSION
ENV PYTHONUNBUFFERED=1

# Install PostgreSQL client
RUN apk add --no-cache postgresql-client

# Install Odoo Dependencies
COPY --from=builder /usr/src/app/wheels  /wheels/
RUN set -ex; \
    apk update; \
    apk add --no-cache \
        bash \
        git \
        file \
        curl \
        screen \
        util-linux \
        vim \
        htop \
        libxslt \
        libjpeg \
        alpine-conf; \
    pip install --no-cache-dir --no-index --find-links=/wheels/ /wheels/*; \
    rm -rf /wheels/

# Install NodeJS
RUN set -ex; \
    apk add --no-cache nodejs npm; \
    npm install -g rtlcss

# Install Odoo
ENV PIP_CACHE_DIR /opt/odoo/pip-cache
RUN set -ex; \
    curl -L https://github.com/odoo/odoo/archive/${ODOO_VERSION}.tar.gz \
        -o /tmp/odoo.src.tar.gz; \
    mkdir -p /opt/odoo/server /opt/odoo/logs /opt/odoo/data /opt/odoo/etc /opt/odoo/pip-cache /opt/odoo/extra-addons; \
    cd /opt/odoo; \
    tar xf /tmp/odoo.src.tar.gz --strip-components=1 -C /opt/odoo/server; \
    rm -f /tmp/odoo.src.tar.gz; \
    ln -s server s; ln -s extra-addons e;

# Install S6
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.xz /tmp
RUN set -ex ; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-${ARCH}.tar.xz; \
    mkdir -p /etc/services.d/odoo /etc/services.d/odootail

# Copy configurations
COPY ./src/cont-init.d/* /etc/cont-init.d/
COPY ./src/services.d/odoo/* /etc/services.d/odoo/
COPY ./src/services.d/odootail/* /etc/services.d/odootail/
COPY ./src/bin/* /usr/local/bin/
RUN set -ex; \
    setup-apkcache /var/cache/apk; \
    chmod +x /usr/local/bin/* /etc/cont-init.d/* /etc/services.d/odoo/* /etc/services.d/odootail/*; \
    echo 'source /etc/profile' >> /etc/bash/bashrc; \
    addgroup -S -g 1000 odoo; \
    adduser -u 1000 -S -s /bin/bash -h /opt/odoo odoo odoo; \
    chown -R odoo:odoo /opt/odoo

# Set cwd
WORKDIR /opt/odoo

# Set environment variables
ENV \
    S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    ODOOCONF__options__addons_path=server/addons \
    ODOOCONF__options__data_dir=data \
    ODOOCONF__options__logfile=logs/odoo-${ODOO_VERSION}.log \
    ODOOCONF__options__list_db=True \
    ODOO_ARGS=--config=etc/odoo.conf \
    ODOO_STAGE=start

# EXPOSE doesn't actually do anything, it's just gives metadata to the container
EXPOSE 8069 8072

# Run S6
ENTRYPOINT ["/init"]