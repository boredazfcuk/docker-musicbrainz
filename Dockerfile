#FROM debian:stable-slim
FROM ubuntu:latest
MAINTAINER boredazfcuk
# musicbrainz_version not used, just increment to force a rebuild
ARG musicbrainz_version="1.0.0"
ARG app_repo="metabrainz/musicbrainz-server"
ARG postgres_addon1="metabrainz/postgresql-musicbrainz-unaccent"
ARG postgres_addon2="metabrainz/postgresql-musicbrainz-collate"
ARG os_essentials="ca-certificates wget curl gnupg bzip2 pkg-config net-tools patch"
ARG build_dependencies="build-essential postgresql-server-dev-all locales-all libexpat1-dev libicu-dev libdb-dev libssl-dev zlib1g-dev"
ARG application_dependencies="cpanminus perl redis-server postgresql-12 postgresql-contrib-12 nginx yarn gettext expat git-core nodejs"
ARG cpan_libraries="FCGI FCGI::ProcManager Plack::Handler::Starlet Starlet Starlet::Server Plack::Middleware::Debug::Base Server::Starter Cache::Memcached::Fast Catalyst::Plugin::StackTrace Term::Size::Any"
ARG DEBIAN_FRONTEND=noninteractive
ENV app_base_dir="/Musicbrainz" \
   config_dir="/config" \
   data_dir="/data" \
   BABEL_DISABLE_CACHE="1"

RUN echo "$(date '+%c') | ***** BUILD STARTED FOR MUSICBRAINZ *****" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Create directories" && \
   mkdir --parents "${app_base_dir}" "${config_dir}" /defaults && \
   temp_dir="$(mktemp -d)" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Refresh apt repositories" && \
   apt-get update && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install build dependencies" && \
   apt-get install --yes --no-install-recommends ${os_essentials} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Add yarn apt repo" && \
   curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
   echo "deb https://dl.yarnpkg.com/debian/ stable main" >> /etc/apt/sources.list.d/yarn.list &&\
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set default locale" && \
   echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale && \
   echo "LANG=en_US.UTF-8" >> /etc/default/locale && \
   echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install build dependencies" && \
   apt-get install --yes --no-install-recommends ${build_dependencies} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Refresh apt repositories" && \
   apt-get update && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install application dependencies" && \
   apt-get install --yes --no-install-recommends ${application_dependencies} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install ${app_repo}" && \
   git clone --branch master --recursive "git://github.com/${app_repo}.git" "${app_base_dir}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Compile CPAN libraries" && \
   cd "${app_base_dir}" && \
   cpanm --notest --installdeps . && \
   cpanm --notest ${cpan_libraries} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install Yarn" && \
   yarn install && \
   yarn cache clean && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install ${app_repo}" && \
   cd "${temp_dir}" && \
   git clone "https://github.com/${postgres_addon1}.git" && \
   cd "${temp_dir}/postgresql-musicbrainz-unaccent" && \
	make && \
	make install && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install ${app_repo}" && \
   cd "${temp_dir}" && \
   git clone "https://github.com/${postgres_addon2}.git" && \
   cd "${temp_dir}/postgresql-musicbrainz-collate" && \
	make && \
	make install && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install clean-up and exit" && \
   apt-get clean && \
   rm -f /etc/nginx/conf.d/default.conf && \
   rm -rf /root/.cpanm /tmp/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY nginx/nginx.conf /defaults/nginx.conf
COPY nginx/musicbrainz.conf /defaults/musicbrainz.conf
COPY nginx/rewrites.conf /defaults/rewrites.conf

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set permissions on launch script" && \
   chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
  CMD /usr/local/bin/healthcheck.sh

VOLUME "${config_dir}" "${data_dir}"

WORKDIR "${app_base_dir}"

ENTRYPOINT "/usr/local/bin/entrypoint.sh"
