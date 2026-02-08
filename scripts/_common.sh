#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# Path for the service to retrieve the Calibre tools
path_with_calibre="$install_dir/tools/calibre:$install_dir/bin:$data_dir/bin:$PATH"

log_file=/var/log/$app/$app.log
access_log_file=/var/log/$app/$app-access.log

VER_DIR=$install_dir/cwa/versions
OLD_CWA="/app/calibre-web-automated"
CWA="$install_dir/cwa"
SCRIPTS="$CWA/scripts"
APP="$CWA/cps"
OLD_CONFIG_DIR="/config"
CONFIG_DIR="$install_dir/config"
OLD_DB="/config/app.db"
DB="$install_dir/config/app.db"
OLD_CALIBRE="/app/calibre"
CALIBRE="$install_dir/tools/calibre"
OLD_META_TEMP="$OLD_CWA/metadata_temp"
META_TEMP="$CWA/metadata_temp"
OLD_META_LOGS="$OLD_CWA/metadata_change_logs"
META_LOGS="$CWA/metadata_change_logs"
INGEST="cwa-book-ingest"
CONVERSION=".cwa_conversion_tmp"

# Heavily inspired by/copy-pasted https://github.com/vhsdream/calibre-web-automated-lxc/blob/main/cwa-lxc.sh
_ynh_patch_cwa() {

mkdir -p "$install_dir"/{config,ingest}
mkdir -p "$install_dir/config"/{processed_books,log_archive,.cwa_conversion_tmp}
mkdir -p $install_dir/config/processed_books/{converted,imported,failed,fixed_originals}
mkdir -p $install_dir/cwa/{metadata_change_logs,metadata_temp,versions}
touch $install_dir/config/convert-library.log
touch $install_dir/config/cwa_update_notice

$install_dir/tools/kepubify --version | awk '{print substr($2 ,2)}' >"$VER_DIR"/kepubify.txt
ynh_hide_warnings $install_dir/tools/calibre/calibre --version | awk '{print substr($3, 1, length($3) -1)}' >"$VER_DIR"/calibre.txt
echo "V${cwa_release}" >"$VER_DIR"/cwa.txt

pushd $CWA
  # Deal with a couple initial modifications
  sed -i "s|\"/calibre-library\"| \"$calibre_library_dir\"|" dirs.json ./scripts/auto_library.py
  sed -i -e "s|\"$OLD_CONFIG_DIR/$CONVERSION\"| \"$CONFIG_DIR/$CONVERSION\"|" \
    -e "s|\"/$INGEST\"| \"$install_dir/config/$INGEST\"|" dirs.json


  # Gather list of Python scripts to be iterated
  FILES=$(find ./scripts "$APP" -type f -name "*.py" -or -name "*.html")
  # Create two arrays containing the paths to be modified
  OLD_PATHS=("$OLD_META_TEMP" "$OLD_META_LOGS" "$OLD_CONFIG_DIR" "$OLD_CWA" "$OLD_CALIBRE")
  NEW_PATHS=("$META_TEMP" "$META_LOGS" "$CONFIG_DIR" "$CWA" "$CALIBRE")

  # Loop over each file; if the old paths are there, then replace using sed
  for file in $FILES; do
    for ((path = 0; path < ${#OLD_PATHS[@]}; path++)); do
      if grep -q "${OLD_PATHS[path]}" "$file"; then
        sed -i "s|${OLD_PATHS[path]}|${NEW_PATHS[path]}|g" "$file"
      fi
    done
  done

  sed -i -e "s|\"/admin$CONFIG_DIR\"|\"/admin$OLD_CONFIG_DIR\"|" \
    -e "s|/app/LSCW_RELEASE|${VER_DIR}/calibre-web.txt|g" \
    -e "s|/app/CWA_RELEASE|${VER_DIR}/cwa.txt|g" \
    -e "s|/CALIBRE_RELEASE|${VER_DIR}/calibre.txt|g" \
    -e "s/lscw_version/calibreweb_version/g" \
    -e "s|/app/KEPUBIFY_RELEASE|${VER_DIR}/kepubify.txt|g" \
    -e "s|/app/cwa_update_notice|$install_dir/config/cwa_update_notice|g" \
    -e "s|/app/theme_migration_notice|$install_dir/config/theme_migration_notice|g" \
    -e "s|/app/cwa_translation_notice_{lang}|$install_dir/config/cwa_translation_notice_{lang}|g" \
    $APP/admin.py $APP/render_template.py

  sed -i "s|\"$CONFIG_DIR/post_request\"|\"$OLD_CONFIG_DIR/post_request\"|; s|python3|/$install_dir/cwa/venv/bin/python3|g" $APP/cwa_functions.py

  sed -i "s/chown\", \"-R\", \"abc:abc\"/chown\", \"-R\", \"$app:$app\"/" "$install_dir"/cwa/scripts/*.py
popd

echo -e "{\n}" > $install_dir/config/user_profiles.json

chown -R $app:$app $install_dir/
}

_ynh_create_koplugin() {
 if [ -d "$install_dir/cwa/koreader/plugins/cwasync.koplugin" ]; then \
    cd $install_dir/cwa/koreader/plugins && \
    # Calculate digest of all files in the plugin for debugging purposes
    PLUGIN_DIGEST=$(find cwasync.koplugin -type f -name "*.lua" -o -name "*.json" | sort | xargs sha256sum | sha256sum | cut -d' ' -f1) && \
    echo "Plugin digest: $PLUGIN_DIGEST" && \
    # Create a file named after the digest inside the plugin folder
    echo "Plugin files digest: $PLUGIN_DIGEST" > cwasync.koplugin/${PLUGIN_DIGEST}.digest && \
    echo "Build date: $(date)" >> cwasync.koplugin/${PLUGIN_DIGEST}.digest && \
    echo "Files included:" >> cwasync.koplugin/${PLUGIN_DIGEST}.digest && \
    find cwasync.koplugin -type f -name "*.lua" -o -name "*.json" | sort >> cwasync.koplugin/${PLUGIN_DIGEST}.digest && \
    zip -r koplugin.zip cwasync.koplugin/ && \
    echo "Created koplugin.zip from cwasync.koplugin folder with digest file: ${PLUGIN_DIGEST}.digest"; \
  else \
    echo "Warning: cwasync.koplugin folder not found, skipping zip creation"; \
  fi && \
  	# Move koplugin.zip to static directory
  if [ -f "$install_dir/cwa/koreader/plugins/koplugin.zip" ]; then \
    mkdir -p $install_dir/cwa/cps/static && \
    cp $install_dir/cwa/koreader/plugins/koplugin.zip $install_dir/cwa/cps/static/ && \
    echo "Moved koplugin.zip to static directory"; \
  else \
    echo "Warning: koplugin.zip not found, skipping move to static directory"; \
  fi
}

_ynh_adapt_cwa_db() {
  # Correct path of binaries
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_kepubifypath='$install_dir/tools/kepubify'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_binariesdir='$install_dir/tools/calibre'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_converterpath='$install_dir/tools/calibre/ebook-convert'"

  # Add correct ldap values for ldap support
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_login_type='1'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_ldap_provider_url='localhost'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_ldap_dn='dc=yunohost,dc=org'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_ldap_user_object='(&(objectClass=posixAccount)(permission=cn=calibreweb.main,ou=permission,dc=yunohost,dc=org)(uid=%s))'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_ldap_group_object_filter='(&(objectClass=posixGroup)(cn=%s.main))'"

  # Correct logs path
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_logfile='$log_file'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_access_log='1'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_access_logfile='$access_log_file'"

  # Correct mail settings
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_server='$domain'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_port='587'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_use_ssl='1'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_login='$app'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_password='$mail_pwd'"
  sqlite3 $install_dir/config/app.db "UPDATE settings SET mail_from='$app@$domain'"

  # Correct misc
  sqlite3 $install_dir/config/app.db "UPDATE settings SET config_external_port='$port'"
}
