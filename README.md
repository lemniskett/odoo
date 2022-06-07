# Odoo Container
This is an Odoo container image, you can use this as a base image for a more customized odoo image.

## Odooctl Dependencies
```sh
pip install pyyaml
```

## Example Usage
Example docker compose with traefik and postgresql is available in `example`

## Configuration
Instead of config file, you can use environment variables to configure the container:
```sh
OPTIONS__DB_HOST=127.0.0.1
OPTIONS__DB_USER=odoo
OPTIONS__DB_PASSWORD=mitija
OPTIONS__WORKERS=3
QUEUE_JOB__CHANNELS=root:1
```
will correspond to:
```
[options]
db_host = 127.0.0.1
db_user = odoo
db_password = mitija
workers = 3

[queue_job]
channels = root:1
```
> Note 1: It's discouraged to change the values of `OPTIONS__DATA_DIR`.

> Note 2: For changing `OPTIONS__ADDONS_PATH`, add `server/addons` (and `server/enterprise` for the enterprise variant) and make sure the directory you're mounting is accessible by the odoo server UID/GID, see below to configure UID/GID, also it's recommended for addons to be placed in `/opt/odoo/extra-addons` to auto fix the file ownership.

Also, there's additional environment variables to configure the container:
- `NO_CHOWN`: If set to anything, the container won't change the ownership of the files to the odoo user, will cause permission error when `OUID` or `OGID` is set to other than 2000.
- `OUID`: UID of the odoo user, must be set between 1000 - 65534, defaults to 2000.
- `OGID`: GID of the odoo user, must be set between 1000 - 65534, defaults to 2000.
- `OARGS`: Additional arguments to pass to odoo, defaults to `--config=/opt/odoo/etc/odoo.conf`.
- `ODOO_DRY_RUN`: If set to anything, the container will not start odoo, but will initialize all the required things to run odoo in the container.
- `ONESHOT`: If set to anything, the container will run only once and will exit after the first start.
- `PIP_INSTALL`: Comma separated list of additional pip packages to install, mount a volume to `/opt/odoo/pip-cache` to avoid recompiling when restarting.
- `PIP_INSTALL_FILE`: The same as above but comma separated list of files to install.
> Note 3: If you're using `PIP_INSTALL` and `PIP_INSTALL_FILE` together, `PIP_INSTALL` will be installed first, and installed modules will be removed from `PIP_INSTALL_FILE`.
- `PURGE_CACHE`: If set to anything, the container will purge `__pycache__` in `/opt/odoo/extra-addons`

## Data persistence
Mount a volume to persist data between restarts.

- `/opt/odoo/data`: Persistent data directory.

## Custom container
If modules fail to install because of missing build dependencies (e.g. pycups), you may want to build your own container using this container as the base image. (e.g. Odoo 14)

```Dockerfile
FROM registry.gitlab.com/mplus-software/containers/odoo/ocommunity/14.0:latest
COPY ./requirements.txt /requirements.txt
RUN apt install libcups2-dev -y
USER odoo
RUN requirements-install /requirements.txt; \
USER root
RUN rm /requirements.txt
```

## Docker desktop on Windows (WSL2 Backend/OS X)
Fix file permissions by using this following `/etc/wsl.conf` in `docker-desktop` distro:

```
[automount]
root = /mnt/host
crossDistro = true
options = metadata,uid=2000,gid=2000
```

And add `NO_CHOWN=True` to the environment variables.