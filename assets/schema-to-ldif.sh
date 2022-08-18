#!/bin/sh

SCHEMAS=$1

OLDPWD="$(pwd)"
tmpd=$(mktemp -d)
cd "${tmpd}" || echo "cd to ${tmpd} failed" || exit

{
  echo "include /etc/openldap/schema/core.schema"
  echo "include /etc/openldap/schema/cosine.schema"
  echo "include /etc/openldap/schema/inetorgperson.schema"
} >> convert.dat

if [ -e "/etc/ldap/schema/rfc2307bis.schema" ]; then
  echo "include /etc/openldap/schema/rfc2307bis.schema" >> convert.dat
else
  echo "include /etc/openldap/schema/nis.schema" >> convert.dat
fi

for schema in ${SCHEMAS} ; do
    echo "include ${schema}" >> convert.dat
done

mkdir slapd.d

if ! slaptest -f convert.dat -F "$tmpd/slapd.d" ; then
    echo "[EROR] slaptest conversion failed"
    exit
fi

for schema in ${SCHEMAS} ; do
    fullpath=${schema}
    schema_name=$(basename "${fullpath}" .schema)
    schema_dir=$(dirname "${fullpath}")
    ldif_file=${schema_name}.ldif

    echo "[INFO] Converting schema $schema"

    if [ -e "${schema_dir}/${ldif_file}" ]; then
      echo "[WARN] ${schema} ldif file ${schema_dir}/${ldif_file} already exists skipping conversion"
      continue
    fi

    find ./slapd.d -name "*\}${schema_name}.ldif" -exec mv '{}' "./${ldif_file}" \;

    sed -i "/dn:/ c dn: cn=${schema_name},cn=schema,cn=config" "${ldif_file}"
    sed -i "/cn:/ c cn: ${schema_name}" "${ldif_file}"
    sed -i '/structuralObjectClass/ d' "${ldif_file}"
    sed -i '/entryUUID/ d' "${ldif_file}"
    sed -i '/creatorsName/ d' "${ldif_file}"
    sed -i '/createTimestamp/ d' "${ldif_file}"
    sed -i '/entryCSN/ d' "${ldif_file}"
    sed -i '/modifiersName/ d' "${ldif_file}"
    sed -i '/modifyTimestamp/ d' "${ldif_file}"

    # slapd seems to be very sensitive to how a file ends. There should be no blank lines.
    sed -i '/^ *$/d' "${ldif_file}"

    mv "${ldif_file}" "${schema_dir}"
done

cd "$OLDPWD" || echo "cd to ${OLDPWD} failed" || exit
rm -rf "$tmpd"
