# OpenLDAP Image with Alpine

OpenLDAP Image with [alpine linux](https://www.alpinelinux.org/)

## Quick Start

Run OpenLDAP docker image

```bash
docker run --detach -p :389:389 -p 636:636 maxswjeon/openldap
```

## Why Alpine?

Suprisingly, Alpine is one of the OSs that supports latest version of OpenLDAP. (In 2022-08-17, OpenLDAP version 2.6.3 for Alpine 3.16) I have been used [osixia/docker-openldap](https://github.com/osixia/docker-openldap) image to set up OpenLDAP servers before, but I found that the image is based on [Debian Buster](https://www.debian.org/releases/buster/), whcih is supressed by [Debian Bullseye](https://www.debian.org/releases/bullseye/)[^1]. OpenLDAP packages (slapd, etc.) that are in the buster package repository are outdated (In 2022-08-17, OpenLDAP version 2.4.15).

## Differences from [`osixia/openldap`](https://github.com/osixia/openldap)

1. Replication is not supported.
2. Config file are moved from `/container/serive/slapd/assets/config` to `/config`. Mount to `/config` to override bootstrap configs.
3. Mountpoint of custom bootstrap schema files are changed from `/container/service/slapd/assets/config/bootstrap/schema/custom` to `/custom/schema`.
4. Mountpoint of custom bootstrap schema files are changed from `/container/service/slapd/assets/config/bootstrap/ldif/custom` to `/custom/ldif`.
5. Files in `/docker-entrypoint-initdb.d` will be executed when creating the database.
6. Data persistence folder is changed
   - Data Directory: `/var/lib/ldap` to `/var/lib/openldap/openldap-data`
   - Config Directory: `/etc/ldap/slapd.d` to `/etc/openldap/slapd.d`
7. Environment variable `LDAP_TLS_BASE_DIR` is added instead of using hardcoded `/container/service/slapd/assets/certs/`
8. Automatic Certificate generation is not supported.
9. All the command passed to container is ignored.

## Configuration

Available environment variables are listed here

### LDAP Server Initialization

These environment variables are used to initialize the LDAP server. Required and used only for new LDAP server.

- **LDAP_DOMAIN**: LDAP Domain. Defaults to `example.org`
- **LDAP_PORT**: LDAP Port. Defaults to `389`
- **LDAPS_PORT**: LDAPS Port. Defaults to `636`
- **LDAP_BASE_DN**: LDAP Base DN. If empty, it is automatically generated from `LDAP_DOMAIN` value. Defaults to `(empty)`
- **LDAP_ADMIN_PASSWORD**: LDAP Admin Password. Defaults to `admin`
- **LDAP_ADMIN_PASSWORD_FILE**: LDAP Admin Password File. If set, `LDAP_ADMIN_PASSWORD` is ignored. Defaults to `(empty)`
- **LDAP_CONFIG_PASSWORD**: LDAP Config Password. Defaults to `config`
- **LDAP_CONFIG_PASSWORD_FILE**: LDAP Config Password File. If set, `LDAP_CONFIG_PASSWORD` is ignored. Defaults to `(empty)`
- **LDAP_READONLY_USER**: Add a readonly user. Defaults to `false`
  > **Note**  
  > The readonly user **does** have write access to its own password.  
  > `LDAP_READONLY_USER` is a boolean value. Accepts only `true` or `false`.
- **LDAP_READONLY_USER_USERNAME**: Read only user username. Defaults to `readonly`
- **LDAP_READONLY_USER_PASSWORD**: Read only User Password. Defaults to `readonly`
- **LDAP_RFC2307BIS_SCHEMA**: Use rfc2307bis schema instead of nis schema. Defaults to `false`
  > **Note**  
  > `LDAP_RFC2307BIS_SCHEMA` is a boolean value. Accepts only `true` or `false`.

### Backend Selection

- **LDAP_BACKEND**: LDAP Backend used for the server. Defaults to `mdb`
  Currently, only `mdb` is supported.

  To be supported values:

  - `asyncmeta`
  - `dnssrv`
  - `ldap`
  - `meta`
  - `null`
  - `passwd`
  - `relay`
  - `sock`
  - `sql`

### TLS Configuration

- **LDAP_TLS**: Add openLDAP TLS capabilities. Cannot be removed once set to true. Defaults to `true`

  > **Note**  
  > `LDAP_TLS` is a boolean value. Accepts only `true` or `false`.

- **LDAP_TLS_BASE_DIR**: Base directory for TLS configuration. Defaults to `/container/service/slapd/assets/certs`
  > **Warning**  
  > Do not set a trailing slash (`/`) to `LDAP_TLS_BASE_DIR` value.
- **LDAP_TLS_CRT_FILENAME**: LDAP TLS certificate filename. Defaults to `ldap.crt`
- **LDAP_TLS_KEY_FILENAME**: LDAP TLS private key filename. Defaults to `ldap.key`
- **LDAP_TLS_DH_PARAM_FILENAME**: LDAP TLS DH parameter filename. Defaults to `dhparam.pem`
- **LDAP_TLS_CA_FILENAME**: LDAP TLS CA Filename. Defaults to `ca.crt`
- **LDAP_TLS_ENFORCE**: Enforce TLS but except `ldapi` connections. Cannot be disabled once set to true. Defaults to `false`

  > **Note**  
  > `LDAP_TLS_ENFORCE` is a boolean value. Accepts only `true` or `false`.

- **LDAP_TLS_CIPHER_SUITE**: LDAP TLS Cipher Suite. Defaults to `SECURE256:+SECURE128:-VERS-TLS-ALL:+VERS-TLS1.2:-RSA:-DHE-DSS:-CAMELLIA-128-CBC:-CAMELLIA-256-CBC`, based on Red Hat's TLS hardening guide
- **LDAP_TLS_VERIFY_CLIENT**: TLS verify client. Defaults to `demand`
  Accepted values: `never`, `allow`, `try`, `demand`. Refer to [OpenLDAP Manual](https://www.openldap.org/doc/admin24/tls.html) for more details.

### Replication Configuration

Replication Configuration is not supported yet.

### Miscellaneous Configuration

- **KEEP_EXISTING_CONFIG**: Do not change the ldap config. Defaults to `false`

  > **Note**  
  > `KEEP_EXISTING_CONFIG` is a boolean value. Accepts only `true` or `false`.

  Expected Behaviors

  - If set to true with an existing database
    - Config: Remain unchanged
    - TLS and Replication config: Not executed
    - `LDAP_ADMIN_PASSWORD`: ignored
    - `LDAP_CONFIG_PASSWORD`: ignored
  - If set to true without an existing database (when bootstrapping a new database)
    - Bootstrap ldif and schema: not be added
    - TLS and Replication config: Not executed

- **LDAP_REMOVE_CONFIG_AFTER_SETUP**: Delete config folder after setup. Defaults to `true`

  > **Note**  
  > `LDAP_REMOVE_CONFIG_AFTER_SETUP` is a boolean value. Accepts only `true` or `false`.

- **HOSTNAME**: Set the hostname of the running openLDAP server. Defaults to whatever docker hostname.
- **DISABLE_CHOWN**: Do not perform any chown to fix file ownership. Defaults to `false`

  > **Note**  
  > `DISABLE_CHOWN` is a boolean value. Accepts only `true` or `false`.

- **LDAP_LOG_LEVEL**: Slap log level. Defaults to `256`. See table 5.1 in [OpenLDAP Manual](https://www.openldap.org/doc/admin24/slapdconf2.html) for available log levels.

- **LDAP_NOFILE**: Maximum number of open files (`ulimit -n`). Defaults to `1024`.

## Limitations

### Alpine Package Limitations

These modules are not supported by Alpine

#### LDAP Overlays

- autogroup
- back_perl
- smbk5pwd

#### SASL2 Modules

- libldapdb
- libotp
- libsql -> Supported in `edge`

### Repository and Image Limitations

Replication is not supported since it is hard to implement complex-bash-env with only POSIX Bourne shell (without python and bash) in Alpine. Contributions are welcome.

[^1]: [osixia/docker-openldap](https://github.com/osixia/docker-openldap) is using [osixia/docker-light-baseimage](https://github.com/osixia/docker-light-baseimage) as base image, which uses debian:buster-slim base image. References: [Dockerfile for osixia/docker-openldap](https://github.com/osixia/docker-openldap/blob/master/image/Dockerfile), [Dockerfile for osixia/docker-light-baseimage](https://github.com/osixia/docker-light-baseimage/blob/master/image/Dockerfile)
