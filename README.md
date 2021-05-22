# docker-musicbrainz
A Musicbrainz container, with added health check

# Variables
**stack_user**: This is the name of the user account that the postgres databse will be created under. If it is not set, it will default to **stackman**

**stack_uid**: This is the ID number of the user account. If it is not set, it will default to **1000**

**musicbrainz_group** This is the name of the group that the user account will be added to. If this is not set, it will default to **musicbrainz**

**musicbrainz_group_id**: This is the ID number of the group. If it is not set, it will default to **1000**

**stack_password**: This is the password for the user account that postgres will be run under. If it is not set, it will default to **Skibidibbydibyodadubdub**

**app_base_dir**: This is the base directory for the application. If it is not set, it will default to **/Musicbrainz**

**config_dir**: This is the base directory for the configuration files. If it is not set, it will default to **/config**

**replication_token**: This is the replication token received from Musicbrainz with which it can replicate date from upstream

**web_address**: This is the web address used so that CSS can be generated correctly. If this is not set, it will default to musicbrainz:5000

**MUSICBRAINZ_USE_PROXY**: This variable tells musicbrainz that it is behind a reverse proxy. Set this variable to 1 or 0. 

Litecoin: LfmogjcqJXHnvqGLTYri5M8BofqqXQttk4