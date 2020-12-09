#!/bin/sh
if ! wget --quiet --tries=1 --spider "http://musicbrainz:5000"; then
   echo "Webserver not responding on http://musicbrainz:5000"
   exit 1
fi

if [ -z "$(netstat -plnt | grep "127.0.0.1:5432")" ]; then
   echo "PostgreSQL database not listening on 127.0.0.1:5432"
   exit 1
fi

if [ -z "$(netstat -plnt | grep "127.0.0.1:6379")" ]; then
   echo "Redis server not listening on 127.0.0.1:6379"
   exit 1
fi

if [ -z "$(netstat -plnt | grep "0.0.0.0:5000")" ]; then
   echo "NGINX web server not listening on 0.0.0.0:5000"
   exit 1
fi

if [ -z "$(netstat -plnt | grep "0.0.0.0:9000")" ]; then
   echo "NGINX web server not listening on 0.0.0.0:9000"
   exit 1
fi

echo "PostgreSQL, Redis, NGINX and FCGI all listening for connections"
exit 0