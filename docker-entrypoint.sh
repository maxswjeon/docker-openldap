#!/bin/sh

lower() {
  export "${1?}" "$(echo "$1" | tr '[:upper:]' '[:lower:]')"  
}

env_from_file() {
  ENV_FROM_FILE_ENV_NAME="${1}_FILE"
  if [ -n "${ENV_FROM_FILE_NAME}" ]; then
    export "${1?}" "$(cat "${ENV_FROM_FILE_ENV_NAME}")"
  fi
}

copy_if_exists() {
  if [ -e "$1" ]; then
    cp -r "$1" "$2"
  fi
}

# Handle Default Envariables
: "${LDAP_DOMAIN:=example.org}"
: "${LDAP_PORT:=389}"
: "${LDAPS_PORT:=636}"
: "${LDAP_ADMIN_PASSWORD:=admin}"
: "${LDAP_CONFIG_PASSWORD:=config}"
: "${LDAP_READONLY_USER:=false}"
: "${LDAP_READONLY_USER_USERNAME:=readonly}"
: "${LDAP_READONLY_USER_PASSWORD:=readonly}"
: "${LDAP_RFC2307BIS_SCHEMA:=false}"

: "${LDAP_BACKEND:=mdb}"

: "${LDAP_TLS:=true}"
: "${LDAP_TLS_BASE_DIR:=/container/service/slapd/assets/certs}"
: "${LDAP_TLS_CRT_FILENAME:=ldap.crt}"
: "${LDAP_TLS_KEY_FILENAME:=ldap.key}"
: "${LDAP_TLS_DH_PARAM_FILENAME:=dhparam.pem}"
: "${LDAP_TLS_CA_FILENAME:=ca.crt}"
: "${LDAP_TLS_ENFORCE:=false}"
: "${LDAP_TLS_CIPHER_SUITE:="SECURE256:+SECURE128:-VERS-TLS-ALL:+VERS-TLS1.2:-RSA:-DHE-DSS:-CAMELLIA-128-CBC:-CAMELLIA-256-CBC"}"
: "${LDAP_TLS_VERIFY_CLIENT:=demand}"

: "${KEEP_EXISTING_CONFIG:=false}"
: "${LDAP_REMOVE_CONFIG_AFTER_SETUP:=true}"
: "${HOSTNAME:=$(hostname)}"
: "${DISABLE_CHOWN:=false}"
: "${LDAP_LOG_LEVEL:=256}"
: "${LDAP_NOFILE:=1024}"

env_from_file "LDAP_ADMIN_PASSWORD"
env_from_file "LDAP_CONFIG_PASSWORD"
env_from_file "LDAP_READONLY_USER_PASSWORD"

lower DISABLE_CHOWN
if [ "$DISABLE_CHOWN" = "false" ]; then
  echo "Updaing ownerships for folders"
  chown -R openldap:openldap /var/lib/openldap -R
  chown -R openldap:openldap /etc/openldap -R
fi

# ulimit -n "$LDAP_NOFILE"

# If this is the first time the container is started
if [ ! -f /.config ]; then
  domain_to_dn() {
    DOMAIN_TO_DN_LDAP_BASE_DN=

    OLD_IFS="$IFS"
    IFS="."
    for DOMAIN_TO_DN_PART in $1; do
      DOMAIN_TO_DN_LDAP_BASE_DN="${DOMAIN_TO_DN_LDAP_BASE_DN}dc=${DOMAIN_TO_DN_PART},"
    done
    IFS="$OLD_IFS"

    DOMAIN_TO_DN_LDAP_BASE_DN="$(echo "$DOMAIN_TO_DN_LDAP_BASE_DN" | sed 's/.$//')"
    echo "$DOMAIN_TO_DN_LDAP_BASE_DN"
  }

  dn_to_domain() {
    echo "$1" | tr ',' '\n' | sed -e 's/^.*=//' | tr '\n' '.' | sed -e 's/\.$//'
  }
  
  generate_base_dn() {
    if [ -z "$LDAP_BASE_DN" ]; then
      echo "Generating base DN"
      LDAP_BASE_DN="$(domain_to_dn "$LDAP_DOMAIN")"
      echo "Base DN: $LDAP_BASE_DN"
    fi
  }

  assert_base_dn() {
    ASSERT_BASE_DN_DOMAIN=$(dn_to_domain "$LDAP_BASE_DN")
    if ! echo "$ASSERT_BASE_DN_DOMAIN" | grep -qE ".*$LDAP_DOMAIN\$" && ! echo "$LDAP_DOMAIN" | grep -qE ".*$ASSERT_BASE_DN_DOMAIN\$"; then
      echo "[EROR] Base DN does not match domain"
      exit 1
    fi
  }

  is_new_schema() {
    IS_NEW_SCHEMA_COUNT=$(ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config cn | grep -c "}$1,")
    if [ "$IS_NEW_SCHEMA_COUNT" -eq 0 ]; then
      echo 1
    else
      echo 0
    fi
  }

  ldap_add_or_modify() {
    LDAP_ADD_OR_MODIFY_LDIF_FILE="$1"
    sed -i "s/{{ LDAP_BASE_DN }}/${LDAP_BASE_DN}/g" "$LDAP_ADD_OR_MODIFY_LDIF_FILE"
    sed -i "s/{{ LDAP_BACKEND }}/${LDAP_BACKEND}/g" "$LDAP_ADD_OR_MODIFY_LDIF_FILE"
    sed -i "s/{{ LDAP_DOMAIN }}/${LDAP_DOMAIN}/g" "$LDAP_ADD_OR_MODIFY_LDIF_FILE"

    lower LDAP_READONLY_USER
    if [ "$LDAP_READONLY_USER" = "true" ]; then
      sed -i "s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g" "$LDAP_ADD_OR_MODIFY_LDIF_FILE"
      sed -i "s|{{ LDAP_READONLY_USER_PASSWORD_ENCRYPTED }}|${LDAP_READONLY_USER_PASSWORD_ENCRYPTED}|g" "$LDAP_ADD_OR_MODIFY_LDIF_FILE"
    fi

    if grep -iq changetype "$LDAP_ADD_OR_MODIFY_LDIF_FILE" ; then
      LDAP_ADD_OR_MODIFY_LDIF_CMD=ldapmodify
    else
      LDAP_ADD_OR_MODIFY_LDIF_CMD=ldapadd
    fi

    $LDAP_ADD_OR_MODIFY_LDIF_CMD -Y EXTERNAL -Q -H ldapi:/// -f "$LDAP_ADD_OR_MODIFY_LDIF_FILE" 2>&1 || $LDAP_ADD_OR_MODIFY_LDIF_CMD -h localhost -p 389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASSWORD" -f "$LDAP_ADD_OR_MODIFY_LDIF_FILE" 2>&1
  }

  BOOTSTRAP=false

  DATA_DIR_CONTENT=$(ls /var/lib/openldap/openldap-data)
  CONFIG_DIR_CONTENT=$(ls /etc/openldap/slapd.d)

  if [ -z "$CONFIG_DIR_CONTENT" ] && [ -z "$DATA_DIR_CONTENT" ]; then
    BOOTSTRAP=true

    echo
    echo "=================================================="
    echo " Database and config empty, bootstrapping"
    echo "=================================================="
    echo

    generate_base_dn
    assert_base_dn

    sed -i "s/{{ LDAP_BASE_DN }}/$LDAP_BASE_DN/g" /etc/openldap/slapd.ldif
    slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif > /dev/null 2>&1
    chown -R openldap:openldap /etc/openldap/slapd.d

    lower LDAP_RFC2307BIS_SCHEMA
    if [ "${LDAP_RFC2307BIS_SCHEMA}" = "true" ]; then
      echo "Switching schema to RFC2307bis..."
      cp /config/bootstrap/schema/rfc2307bis* /etc/openldap/schema/

      rm -f /etc/openldap/slapd.d/cn=config/cn=schema/*

      TEMP=$(mktemp -d)
      slaptest -f /config/bootstrap/schema/rfc2307bis.conf -F "$TEMP"
      mv "$TEMP/cn=config/cn=schema" /etc/openldap/slapd.d/cn=config/cn=schema
      rm -r "$TEMP"

      lower DISABLE_CHOWN
      if [ "$DISABLE_CHOWN" = "false" ]; then
        chown -R openldap:openldap /etc/openldap/slapd.d/cn=config/cn=schema
      fi
    fi
    rm /config/bootstrap/schema/rfc2307bis*
  elif [ -z "$CONFIG_DIR_CONTENT" ] && [ -n "$DATA_DIR_CONTENT" ]; then
    echo "[EROR] The config directory (/etc/openldap/slapd.d) is empty but the data directory (/var/lib/openldap/openldap-data) is not"
    exit 1
  elif [ -n "$CONFIG_DIR_CONTENT" ] && [ -z "$DATA_DIR_CONTENT" ]; then
    echo "[EROR] The data directory (/var/lib/openldap/openldap-data) is empty but the config directory (/etc/openldap/slapd.d) is not"
    exit 1
  else
    if [ "$LDAP_BACKEND" = "mdb" ]; then
      if [ -e "/etc/openldap/slapd.d/cn=config/olcDatabase={1}hdb.ldif" ]; then
        echo "[WARN] LDAP_BACKEND environment variable is set to mdb but hdb backend is deteded"
        echo "[WARN] Going to use hdb as LDAP_BACKEND. Set LDAP_BACKEND to hdb to discard this warning"
        exit 1
      fi
    fi
  fi


  lower KEEP_EXISTING_CONFIG
  if [ "$KEEP_EXISTING_CONFIG" = "true" ]; then
    echo "[INFO] Keeping existing config"
  else
    echo "[INFO] Starting OpenLDAP..."
    slapd -h "ldap:/// ldapi:///" -u openldap -g openldap

    echo "[INFO] Waiting for OpenLDAP to start..."
    while [ ! -e /var/lib/openldap/run/slapd.pid ]; do sleep 0.1; done

    if [ "$BOOTSTRAP" = "true" ]; then
      echo "[INFO] Bootstrapping..."

      ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f /etc/openldap/pqchecker/ppolicy.ldif 2>&1

      SCHEMAS=""
      for f in $(find /config/bootstrap/schema -name \*.schema -type f | sort); do
        SCHEMAS="$SCHEMAS $f"
        echo "[INFO] Adding schema $f"
      done

      /schema-to-ldif.sh "$SCHEMAS"

      for f in $(find /config/bootstrap/schema -name \*.ldif -type f | sort); do
        SCHEMA=$(basename "$f" .ldif)
        ADD_SCHEMA=$(is_new_schema "$SCHEMA")

        if [ "$ADD_SCHEMA" -eq 1 ]; then
          ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f "$f" 2>&1
        else
          echo "[INFO] Schema $f already exists"
        fi
      done

      LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
      sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" /config/bootstrap/ldif/01-config-password.ldif
      sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" /config/bootstrap/ldif/02-security.ldif

      echo "[INFO] Adding bootstrap ldif files..."
      for f in $(find /config/bootstrap/ldif -mindepth 1 -maxdepth 1 -type f -name \*.ldif | sort); do
        echo "Modify $f"
        ldap_add_or_modify "$f"
      done

      lower LDAP_READONLY_USER
      if [ "$LDAP_READONLY_USER" = "true" ]; then
        echo "[INFO] Adding readonly user..."

        LDAP_READONLY_USER_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_READONLY_USER_PASSWORD")

        ldap_add_or_modify /config/bootstrap/ldif/readonly-user/readonly-user.ldif
        ldap_add_or_modify /config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif
      fi

      echo "[INFO] Adding custom bootstrap ldif files..."
      for f in $(find /config/bootstrap/ldif/custom -type f -name \*.ldif | sort); do
        ldap_add_or_modify "$f"
      done
    fi

    lower LDAP_TLS
    if [ "$LDAP_TLS" = "true" ]; then
      echo "[INFO] Adding TLS configuration..."
      
      LDAP_TLS_CERT_PATH="${LDAP_TLS_BASE_DIR}/${LDAP_TLS_CRT_FILENAME}"
      LDAP_TLS_KEY_PATH="${LDAP_TLS_BASE_DIR}/${LDAP_TLS_KEY_FILENAME}"
      LDAP_TLS_CA_PATH="${LDAP_TLS_BASE_DIR}/${LDAP_TLS_CA_FILENAME}"
      LDAP_TLS_DH_PARAM_PATH="${LDAP_TLS_BASE_DIR}/${LDAP_TLS_DH_PARAM_FILENAME}"

      if [ ! -f "$LDAP_TLS_CERT_PATH" ]; then
        echo "[EROR] TLS certificate not found at $LDAP_TLS_CERT_PATH"
        exit 1
      fi

      if [ ! -f "$LDAP_TLS_KEY_PATH" ]; then
        echo "[EROR] TLS key not found at $LDAP_TLS_KEY_PATH"
        exit 1
      fi

      if [ ! -f "$LDAP_TLS_CA_PATH" ]; then
        echo "[EROR] TLS CA not found at $LDAP_TLS_CA_PATH"
        exit 1
      fi

      [ -f "$LDAP_TLS_DH_PARAM_PATH" ] || openssl dhparam -out "$LDAP_TLS_DH_PARAM_PATH" 4096

      lower DISABLE_CHOWN
      if [ "$DISABLE_CHOWN" = "false" ]; then
        chmod 600 "$LDAP_TLS_DH_PARAM_PATH"
      fi

      sed -i "s|{{ LDAP_TLS_CA_CRT_PATH }}|${LDAP_TLS_CA_PATH}|g"     /config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_CRT_PATH }}|${LDAP_TLS_CERT_PATH}|g"           /config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_KEY_PATH }}|${LDAP_TLS_KEY_PATH}|g"           /config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_DH_PARAM_PATH }}|${LDAP_TLS_DH_PARAM_PATH}|g" /config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_CIPHER_SUITE }}|${LDAP_TLS_CIPHER_SUITE}|g"   /config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_VERIFY_CLIENT }}|${LDAP_TLS_VERIFY_CLIENT}|g" /config/tls/tls-enable.ldif

      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f /config/tls/tls-enable.ldif 2>&1

      START_WITH_TLS=true

      lower LDAP_TLS_ENFORCE
      if [ "$LDAP_TLS_ENFORCE" = "true" ]; then
        echo "[INFO] Enforcing TLS..."
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f /config/tls/tls-enforce-enable.ldif 2>&1
      fi
    fi

    remove_replication_config() {
      sed -i "s/export WAS_STARTED_WITH_REPLICATION=.*//g" /.config
      sed -i "s/export PREVIOUS_HOSTNAME=.*//g" /.config
    }

    disable_replication() {
      sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" /config/replication/replication-disable.ldif
      ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f /config/replication/replication-disable.ldif 2>&1
      remove_replication_config
    }

    lower LDAP_REPLICATION
    if [ "$LDAP_REPLICATION" = "true" ]; then
      echo "[INFO] Adding replication configuration..."

      START_WITH_REPLICATION=true

      echo "[EROR] LDAP_REPLICATION is not supported yet"
      exit 1
    elif [ "$LDAP_REPLICATION" = "own" ]; then
      echo "[INFO] Not touching replication configuration..."
      
      START_WITH_REPLICATION=true

      remove_replication_config
    else
      echo "[INFO] Disabling replication configuration..."
      disable_replication || true
    fi
    
    ADMIN_PASSWORD_SET=true
  
    echo "[INFO] Stopping OpenLDAP..."
    SLAPD_PID=$(cat /var/lib/openldap/run/slapd.pid)

    kill -15 "$SLAPD_PID"
    while [ -e "/proc/$SLAPD_PID" ]; do sleep 0.1;  done

    echo "[INFO] Running /docker-entrypoint-init.d"
    if [ -d /docker-entrypoint-init.d ]; then
      for f in $(find /docker-entrypoint-init.d -mindepth 1 -maxdepth 1 -type f | sort); do
        echo "[INFO] Running docker-entrypoint-init.d/$(basename "$f")"

        # shellcheck disable=SC1090
        . "/docker-entrypoint-init.d/$f"
      done
    fi
  fi

  lower LDAP_TLS
  if [ "$LDAP_TLS" = "true" ]; then
    echo "[INFO] Configuring LDAP Client with TLS configuration..."
    sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT &{LDAP_TLS_CA_CRT_PATH},g" /etc/openldap/ldap.conf
    echo "TLS_REQCERT $LDAP_TLS_VERIFY_CLIENT" >> /etc/openldap/ldap.conf
    cp -f /etc/openldap/ldap.conf /ldap.conf

    [ -f "$HOME/.ldaprc" ] && rm -f "$HOME/.ldaprc"
    echo "TLS_CERT $LDAP_TLS_CERT_PATH" >> "$HOME/.ldaprc"
    echo "TLS_KEY $LDAP_TLS_KEY_PATH" >> "$HOME/.ldaprc"
    cp -f "$HOME/.ldaprc" /.ldaprc
  fi

  lower LDAP_REMOVE_CONFIG_AFTER_SETUP
  if [ "$LDAP_REMOVE_CONFIG_AFTER_SETUP" = "true" ]; then
    echo "[INFO] Removing configuration files..."
    rm -rf /config
  fi

  # Generate .config file
  touch /.config
  if [ "$START_WITH_TLS" = true ]; then
    {
      echo "export WAS_STARTED_WITH_TLS=true"
      echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_PATH}"
      echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CERT_PATH}"
      echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}"
      echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}"
    } >> /.config
  fi

  if [ "$START_WITH_REPLICATION" = "true" ]; then
    {
      echo "export WAS_STARTED_WITH_REPLICATION=true"
      echo "export PREVIOUS_HOSTNAME=$(hostname -f)"
    } >> /.config
  fi

  if [ "$ADMIN_PASSWORD_SET" = "true" ]; then
    echo "export WAS_ADMIN_PASSWORD_SET=true" >> /.config
  fi
fi

ln -sf /.ldaprc "$HOME/.ldaprc"
ln -sf ldap.conf /etc/openldap/ldap.conf

# echo "0.0.0.0 $(hostname) $(hostname -f)" >> /etc/hosts

FQDN="$(hostname -f)"
HOST_PARAM="ldap://0.0.0.0:$LDAP_PORT ldaps://0.0.0.0:$LDAPS_PORT"
exec slapd -h "$HOST_PARAM ldapi:///" -u openldap -g openldap -d "$LDAP_LOG_LEVEL"
