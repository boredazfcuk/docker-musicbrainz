#!/bin/bash

Initialise(){
   lan_ip="$(hostname -i)"
   echo
   echo "$(date '+%c') INFO:    ***** Configuring Musicbrainz container launch environment *****"
   echo "$(date '+%c') INFO:    $(cat /etc/*-release | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | sed 's/"//g')"
   echo "$(date '+%c') INFO:    Local user: ${stack_user:=stackman}:${stack_uid:=1000}"
   echo "$(date '+%c') INFO:    Local group: ${musicbrainz_group:=musicbrainz}:${musicbrainz_group_id:=1000}"
   echo "$(date '+%c') INFO:    Password: ${stack_password:=Skibidibbydibyodadubdub}"
   echo "$(date '+%c') INFO:    Musicbrainz application directory: ${app_base_dir:=/Musicbrainz}"
   echo "$(date '+%c') INFO:    Configuration directory: ${config_dir:=/config}"
   if [ ! -d "${config_dir}" ]; then mkdir --parents "${config_dir}"; fi
   if [ ! -d "${config_dir}/nginx" ]; then mkdir --parents "${config_dir}/nginx"; fi
   if [ ! -d "${config_dir}/nginx/logs" ]; then mkdir --parents "${config_dir}/nginx/logs"; fi
   if [ ! -d "${config_dir}/postgres" ]; then mkdir --parents "${config_dir}/postgres"; fi
   if [ ! -d "${config_dir}/postgres/logs" ]; then mkdir --parents "${config_dir}/postgres/logs"; fi
   if [ ! -d "/run/postgresql" ]; then mkdir --parents "/run/postgresql"; fi
   if [ ! -d "${config_dir}/redis" ]; then mkdir --parents "${config_dir}/redis"; fi
   if [ ! -d "${config_dir}/redis/logs" ]; then mkdir --parents "${config_dir}/redis/logs"; fi
   if [ ! -d "${config_dir}/musicbrainz" ]; then mkdir --parents "${config_dir}/musicbrainz"; fi
   if [ ! -d "${config_dir}/musicbrainz/logs" ]; then mkdir --parents "${config_dir}/musicbrainz/logs"; fi
   if [ ! -f "${config_dir}/musicbrainz/logs/server.log" ]; then touch "${config_dir}/musicbrainz/logs/server.log"; fi
   if [ ! -f "${config_dir}/musicbrainz/logs/replication.log" ]; then touch "${config_dir}/musicbrainz/logs/replication.log"; fi
   if [ ! -d "${data_dir}/musicbrainz_db" ]; then mkdir --parents "${data_dir}/musicbrainz_db"; fi
   if [ ! -d "${data_dir}/redis" ]; then mkdir --parents "${data_dir}/redis"; fi
   if [ ! -f "/run/fcgi.pid" ]; then touch "/run/fcgi.pid"; fi
   if [ -f "/tmp/musicbrainz-template-renderer.socket" ]; then rm /tmp/musicbrainz-template-renderer.socket; fi
   echo "$(date '+%c') INFO:    Database directory: ${data_dir:=/data}"
   if [ ! -d "${data_dir}" ]; then mkdir --parents "${data_dir}"; fi
   echo "$(date '+%c') INFO:    LAN IP Address: ${lan_ip}"
   echo "$(date '+%c') INFO:    Musicbrainz Web Address: ${web_address:=musicbrainz:5000}"
   if [ -f "/var/tmp/web_address" ]; then
      previous_web_address="$(cat /var/tmp/web_address)"
   else
      previous_web_address="Initialise"
   fi
   echo "${web_address}" > "/var/tmp/web_address"
   if [ "${replication_token}" ]; then
      echo "$(date '+%c') INFO:    Musicbrainz replication token: ${replication_token}"
   else
      echo "$(date '+%c') WARNING: Musicbrainz replication token not configured. Databse will not update"
   fi
   if [ "${MUSICBRAINZ_USE_PROXY}" = 1 ]; then echo "$(date '+%c') INFO:    Musicbrainz proxying enabled"; fi
}

CreateGroup(){
   if [ "$(grep -c "^${musicbrainz_group}:x:${musicbrainz_group_id}:" "/etc/group")" -eq 1 ]; then
      echo "$(date '+%c') INFO:    Group, ${musicbrainz_group}:${musicbrainz_group_id}, already created"
   else
      if [ "$(grep -c "^${musicbrainz_group}:" "/etc/group")" -eq 1 ]; then
         echo "$(date '+%c') ERROR:   Group name already in use: ${musicbrainz_group} - exiting"
         sleep 120
         exit 1
      elif [ "$(grep -c ":x:${musicbrainz_group_id}:" "/etc/group")" -eq 1 ]; then
         if [ "${force_gid}" = "True" ]; then
            group="$(grep ":x:${musicbrainz_group_id}:" /etc/group | awk -F: '{print $1}')"
            echo "$(date '+%c') WARNING: Group id already exists: ${musicbrainz_group_id} - continuing as force_gid variable has been set. Group name to use: ${musicbrainz_group}"
         else
            echo "$(date '+%c') ERROR:   Group id already in use: ${musicbrainz_group_id} - exiting"
            sleep 120
            exit 1
         fi
      else
         echo "$(date '+%c') INFO:    Creating group ${musicbrainz_group}:${musicbrainz_group_id}"
         addgroup --gid "${musicbrainz_group_id}" "${musicbrainz_group}" --quiet
      fi
   fi
}

CreateUser(){
   if [ "$(grep -c "^${stack_user}:x:${stack_uid}:${musicbrainz_group_id}" "/etc/passwd")" -eq 1 ]; then
      echo "$(date '+%c') INFO:    User already created: ${stack_user}:${stack_uid}"
   else
      if [ "$(grep -c "^${stack_user}:" "/etc/passwd")" -eq 1 ]; then
         echo "$(date '+%c') ERROR:   User name already in use: ${stack_user} - exiting"
         sleep 120
         exit 1
      elif [ "$(grep -c ":x:${stack_uid}:$" "/etc/passwd")" -eq 1 ]; then
         echo "$(date '+%c') ERROR:   User id already in use: ${stack_uid} - exiting"
         sleep 120
         exit 1
      else
         echo "$(date '+%c') INFO:    Creating user ${stack_user}:${stack_uid}"
         adduser --shell /bin/bash --disabled-password --ingroup "${musicbrainz_group}" --uid "${stack_uid}" "${stack_user}" --home "/home/${stack_user}" --gecos '' --quiet
      fi
   fi
}

GetDBSnapshot(){
   if [ ! -d "${data_dir}/mbdump" ]; then
      mkdir --parents "${data_dir}/mbdump"
      cd "${data_dir}/mbdump" || exit 1
      echo "This directory contains the latest DB dump. Files can be removed to save space, to redownload latest dump, remove the directory" > README
      wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/LATEST"
      latest_db="$(cat "${data_dir}/mbdump/LATEST")"
      echo "$(date '+%c') INFO:    Download latest database dump: ${latest_db}"
      if [ ! -f "${data_dir}/mbdump/mbdump-cdstubs.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-cdstubs.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-cover-art-archive.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-cover-art-archive.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-derived.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-derived.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-documentation.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-documentation.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-editor.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-editor.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-stats.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-stats.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump-wikidocs.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump-wikidocs.tar.bz2"
      fi
      if [ ! -f "${data_dir}/mbdump/mbdump.tar.bz2" ]; then
         wget -c -P "${data_dir}/mbdump" "http://ftp.musicbrainz.org/pub/musicbrainz/data/fullexport/${latest_db}/mbdump.tar.bz2"
      fi
      cd - >/dev/null
   fi
}

SetOwnerAndGroup(){
   echo "$(date '+%c') INFO:    Correct owner and group of application files, if required"
   find "/run" -name "/run/fcgi.pid" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "/run" -name "/run/fcgi.pid" ! -group "${musicbrainz_group}" -exec chgrp "${musicbrainz_group}" {} \;
   find "/run/postgresql" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "/run/postgresql" ! -group "${musicbrainz_group}" -exec chgrp "${musicbrainz_group}" {} \;
   find "${config_dir}" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "${config_dir}" ! -group "${musicbrainz_group}" -exec chgrp "${musicbrainz_group}" {} \;
   find "${data_dir}" ! -user "${stack_user}" -exec chown "${stack_user}" {} \;
   find "${data_dir}" ! -group "${musicbrainz_group}" -exec chgrp "${musicbrainz_group}" {} \;
}

ConfigureNGINX(){
   echo "$(date '+%c') INFO:    Configure NGINX"
   if [ ! -d "${config_dir}/nginx/conf.d" ]; then mkdir --parents "${config_dir}/nginx/conf.d"; fi
   if [ ! -f "${config_dir}/nginx/nginx.conf" ]; then cp "/defaults/nginx.conf" "${config_dir}/nginx/nginx.conf"; fi
   if [ ! -f "${config_dir}/nginx/conf.d/musicbrainz.conf" ]; then cp "/defaults/musicbrainz.conf" "${config_dir}/nginx/conf.d/musicbrainz.conf"; fi
   if [ ! -f "${config_dir}/nginx/conf.d/rewrites.conf" ]; then cp "/defaults/rewrites.conf" "${config_dir}/nginx/conf.d/rewrites.conf"; fi
   if [ "$(grep -c 'fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;' /etc/nginx/fastcgi_params)" = 0 ]; then
      echo "$(date '+%c') INFO:    Configure NGINX FastCGI parameters"
      echo 'fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;' >> /etc/nginx/fastcgi_params
   fi
}

ConfigureRedis(){
   echo "$(date '+%c') INFO:    Configure Redis"
   if [ ! -f "${config_dir}/redis/redis.conf" ]; then
      cp "/etc/redis/redis.conf" "${config_dir}/redis/redis.conf"
      sed -i \
         -e "s/^loglevel.*/loglevel warning/" \
         -e "s%^logfile.*%logfile ${config_dir}/redis/logs/redis.log%" \
         -e "s%dir.*%dir ${data_dir}/redis%" \
         "${config_dir}/redis/redis.conf"
   fi
   if [ "$(grep -c "^daemonize" "${config_dir}/redis/redis.conf")" -eq 0 ]; then
      {
         echo "# By default Redis does not run as a daemon. Use 'yes' if you need it."
         echo "# Note that Redis will write a pid file in /var/run/redis.pid when daemonized."
         echo "daemonize yes"
      } >>"${config_dir}/redis/redis.conf"
   fi
}

ConfigureMusicbrainz(){
   echo "$(date '+%c') INFO:    Configure Musicbrainz"
   if [ ! -f "${config_dir}/musicbrainz/DBDefs.pm" ]; then
      echo "$(date '+%c') INFO:    Copy sample configuration to ${config_dir}"
      cp "${app_base_dir}/lib/DBDefs.pm.sample" "${config_dir}/musicbrainz/DBDefs.pm"
      echo "$(date '+%c') INFO:    Configure Musicbrainz as slave server"
      sed -i \
         -e "/sub REPLICATION_TYPE/ s/^# //" \
         -e "s/sub REPLICATION_TYPE {.*/sub REPLICATION_TYPE { RT_SLAVE }/" \
         -e "/sub DB_STAGING_SERVER/ s/^# //" \
         -e "s/sub DB_STAGING_SERVER {.*/sub DB_STAGING_SERVER { 0 }/" \
         -e "/sub CATALYST_DEBUG/ s/^# //" \
         -e "s/sub CATALYST_DEBUG {.*/sub CATALYST_DEBUG { 0 }/" \
         -e "/sub DEVELOPMENT_SERVER/ s/^# //" \
         -e "s/sub DEVELOPMENT_SERVER {.*/sub DEVELOPMENT_SERVER { 0 }/" \
         "${config_dir}/musicbrainz/DBDefs.pm"
      echo "$(date '+%c') INFO:    Configure Musicbrainz database credentials"
      sed -i -r \
         -e "/READONLY/,/},$/ s/(.*)username(.*)\".*\"(.*)/\1username\2\"${stack_user}\"\3/" \
         -e "/READONLY/,/},$/ s/(.*)password(.*)\".*\"(.*)/\1password\2\"${stack_password}\"\3/" \
         -e "/SYSTEM/,/},$/ s/(.*)username(.*)\".*\"(.*)/\1username\2\"${stack_user}\"\3/" \
         "${config_dir}/musicbrainz/DBDefs.pm"
      echo "$(date '+%c') INFO:    Configure Musicbrainz root directory"
      sed -i -r \
         -e "/# sub MB_SERVER_ROOT / s/^# //" \
         -e "/sub MB_SERVER_ROOT / s%(.*)\".*\"(.*)%\1\"${app_base_dir}\"\2%" \
         "${config_dir}/musicbrainz/DBDefs.pm"
   fi
   if [ "${replication_token}" ]; then
      echo "$(date '+%c') INFO:    Configure Musicbrainz replication token"
      sed -i \
         -e "/sub REPLICATION_ACCESS_TOKEN/s/^# //" \
         -e "s/sub REPLICATION_ACCESS_TOKEN .*/sub REPLICATION_ACCESS_TOKEN { \"${replication_token}\" }/" \
         "${config_dir}/musicbrainz/DBDefs.pm"
   fi
   if [ -f "${app_base_dir}/lib/DBDefs.pm" ] && [ ! -L "${app_base_dir}/lib/DBDefs.pm" ]; then 
      echo "$(date '+%c') INFO:    Remove Musicbrainz configuration file: ${app_base_dir}/lib/DBDefs.pm"
      rm "${app_base_dir}/lib/DBDefs.pm"
      echo "$(date '+%c') INFO:    Link ${app_base_dir}/lib/DBDefs.pm to ${config_dir}/musicbrainz/DBDefs.pm"
      ln -s "${config_dir}/musicbrainz/DBDefs.pm" "${app_base_dir}/lib/DBDefs.pm"
   elif [ -f "${app_base_dir}/lib/DBDefs.pm" ] && [ -L "${app_base_dir}/lib/DBDefs.pm" ]; then
      echo "$(date '+%c') INFO:    Link ${app_base_dir}/lib/DBDefs.pm to ${config_dir}/musicbrainz/DBDefs.pm already in place"
   else
      echo "$(date '+%c') INFO:    Link ${app_base_dir}/lib/DBDefs.pm to ${config_dir}/musicbrainz/DBDefs.pm"
      ln -s "${config_dir}/musicbrainz/DBDefs.pm" "${app_base_dir}/lib/DBDefs.pm"
   fi
   if [ "${web_address}" != "${previous_web_address}" ]; then
      echo "$(date '+%c') INFO:    Configure web server address: ${web_address}"
      sed -i \
         -e "s/sub WEB_SERVER  .*/sub WEB_SERVER { \"${web_address}\" }/" \
         "${config_dir}/musicbrainz/DBDefs.pm"
      cd "${app_base_dir}" || exit
      echo "$(date '+%c') INFO:    Build static web resources..."
      echo
      ./script/compile_resources.sh
      cd - >/dev/null
      echo
      echo "$(date '+%c') INFO:    Building web resources complete"
   fi
}

InitialisePostgres(){
   if [ -f "${data_dir}/musicbrainz_db/PG_VERSION" ]; then
      db_version="$(cat "${data_dir}/musicbrainz_db/PG_VERSION")"
   fi
   if [ -z "${db_version}" ]; then
      echo "$(date '+%c') INFO:    Initialise postgres version 12 database cluster..."
      echo
      su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl initdb --pgdata=${data_dir}/musicbrainz_db"
      echo
      echo "$(date '+%c') INFO:    Postgres database cluster initialisation complete"
      echo "$(date '+%c') INFO:    Configure connections"
      echo "local   all   all   trust" >> "${data_dir}/musicbrainz_db/pg_hba.conf"
      echo "host   all   all   0.0.0.0/0   md5" >> "${data_dir}/musicbrainz_db/pg_hba.conf"
      echo "$(date '+%c') INFO:    Set PostgreSQL to listen on 127.0.0.1"
      sed -i -r \
         -e "/^#listen_addresses = / s/^#//" \
         -e "s/^listen_addresses = '.*'(.*)/listen_addresses = '127.0.0.1'\1/" \
         "${data_dir}/musicbrainz_db/postgresql.conf"
      echo "$(date '+%c') INFO:    Start PostgreSQL..."
      echo
      su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl --pgdata=${data_dir}/musicbrainz_db  -w start"
      echo
      echo "$(date '+%c') INFO:    PostgreSQL startup complete"
      echo "$(date '+%c') INFO:    Create empty database..."
      echo
      su "${stack_user}" -c "/usr/bin/createdb"
      echo
      echo "$(date '+%c') INFO:    Database creation complete"
      echo "$(date '+%c') INFO:    Add superuser permission for user: ${stack_user}"
      su "${stack_user}" -c "/usr/bin/psql --command \"ALTER USER ${stack_user} WITH SUPERUSER;\""
      echo "$(date '+%c') INFO:    Stop PostgreSQL server..."
      echo
      su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl --pgdata=${data_dir}/musicbrainz_db -m fast -w stop"
      echo "$(date '+%c') INFO:    PostgreSQL server stop complete"
      echo "$(date '+%c') INFO:    Move configuration file to ${config_dir}/postgres directory"
      mv "${data_dir}/musicbrainz_db/postgresql.conf" "${config_dir}/postgres/postgresql.conf"
   fi
}

ImportDatabase(){
   if [ ! -f "${data_dir}/musicbrainz_db/mbdb_import" ]; then
      echo "$(date '+%c') INFO:    Import database"
      echo "Musicbrainz dump started: $(date '+%c')" >> "${data_dir}/musicbrainz_db/mbdb_import"
      if [ ! -d "${data_dir}/mbdump/mbtmp" ]; then mkdir --parents "${data_dir}/mbdump/mbtmp"; fi
      chown -R "${stack_user}":"${musicbrainz_group}" "${data_dir}/mbdump/mbtmp"
      cd "${app_base_dir}" || exit 1
      echo "$(date '+%c') INFO:    Start PostgreSQL server"
      su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl --pgdata=${data_dir}/musicbrainz_db -o \"-c max_wal_size=4096 -c config_file=${config_dir}/postgres/postgresql.conf\" -w start"
      echo "$(date '+%c') INFO:    Import data"
      su "${stack_user}" -c "./admin/InitDb.pl --createdb --import ${data_dir}/mbdump/mbdump*.tar.bz2 --echo --tmp-dir=${data_dir}/mbdump/mbtmp"
      echo "$(date '+%c') INFO:    Stop server"
      su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl --pgdata=${data_dir}/musicbrainz_db -m fast -w stop"
      cd - >/dev/null
      if [ -d "${data_dir}/mbdump/mbtmp" ]; then rm -r "${data_dir}/mbdump/mbtmp"; fi
      echo "Musicbrainz dump import completed: $(date '+%c')" >> "${data_dir}/musicbrainz_db/mbdb_import"
   fi
}

LaunchNGINX(){
   echo "$(date '+%c') INFO:    Launch NGINX"
   /usr/sbin/nginx -c /config/nginx/nginx.conf
}

LaunchRedis(){
   echo "$(date '+%c') INFO:    Launch Redis"
   /usr/bin/redis-server "${config_dir}/redis/redis.conf"
}

LaunchPostgres(){
   echo "$(date '+%c') INFO:    Launch PostgreSQL"
   su "${stack_user}" -c "/usr/lib/postgresql/12/bin/pg_ctl --pgdata=${data_dir}/musicbrainz_db -o \"-c config_file=${config_dir}/postgres/postgresql.conf\" -w start"
}

LaunchMusicbrainz(){
   if [ "$(grep -c "${config_dir}/musicbrainz/logs/server.log")" -gt 1000 ]; then
      echo "$(date '+%c') INFO:    Truncate server log to last 1000 lines"
      tail -1000 "${config_dir}/musicbrainz/logs/server.log" > "${config_dir}/musicbrainz/logs/server.bak"
      rm "${config_dir}/musicbrainz/logs/server.log"
      mv "${config_dir}/musicbrainz/logs/server.bak" "${config_dir}/musicbrainz/logs/server.log"
   fi
   plackup -I "${app_base_dir}/lib" --server FCGI --daemonize --env deployment --port 9000 --pid /run/fcgi.pid --keep-stderr=1 >> "${config_dir}/musicbrainz/logs/server.log" 
   echo "$(date '+%c') INFO:    Musicbrainz started with pid: $(cat /run/fcgi.pid)"
}


StartReplication(){
   if [ "$(grep -c "${config_dir}/musicbrainz/logs/replication.log")" -gt 1000 ]; then
      echo "$(date '+%c') INFO:    Truncate replication log to last 1000 lines"
      tail -1000 "${config_dir}/musicbrainz/logs/replication.log" > "${config_dir}/musicbrainz/logs/replication.bak"
      rm "${config_dir}/musicbrainz/logs/replication.log"
      mv "${config_dir}/musicbrainz/logs/replication.bak" "${config_dir}/musicbrainz/logs/replication.log"
   fi
   echo "$(date '+%c') INFO:    Start hourly replication"
   while :; do
      echo "$(date '+%c') INFO:    Begin replication"
      "${app_base_dir}/admin/replication/LoadReplicationChanges"
      echo "$(date '+%c') INFO:    Replication complete"
      sleep 3600
   done
}

##### Start Script #####
Initialise
CreateGroup
CreateUser
GetDBSnapshot
SetOwnerAndGroup
ConfigureNGINX
ConfigureRedis
ConfigureMusicbrainz
InitialisePostgres
ImportDatabase
LaunchNGINX
LaunchRedis
LaunchPostgres
LaunchMusicbrainz
StartReplication