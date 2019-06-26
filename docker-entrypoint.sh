#!/bin/bash

IFS=';' read -r -a user_array <<< "$POSTGRES_USER"
IFS=';' read -r -a pass_array <<< "$POSTGRES_PASSWORD"

export POSTGRES_USER=${user_array[0]}
export POSTGRES_PASSWORD=${pass_array[0]}

user_array=("${user_array[@]:1}")
pass_array=("${pass_array[@]:1}")

if [ "x$REPLICATION_HOST" == "x" ]; then
	IFS=';' read -r -a db_array <<< "$POSTGRES_DB"
	export POSTGRES_DB=${db_array[0]}
	db_array=("${db_array[@]:1}")
fi


if [ "x$OTHER_USER_PRIVILEGES" == "x" ]; then
    export OTHER_USER_PRIVILEGES="CREATEDB"
else
	export OTHER_USER_PRIVILEGES="${OTHER_USER_PRIVILEGES//;/ }"
fi

echo $OTHER_USER_PRIVILEGES


# Backwards compatibility for old variable names (deprecated)
if [ "x$PGUSER"     != "x" ]; then
    POSTGRES_USER=$PGUSER
fi
if [ "x$PGPASSWORD" != "x" ]; then
    POSTGRES_PASSWORD=$PGPASSWORD
fi

# Forwards-compatibility for old variable names (pg_basebackup uses them)
if [ "x$PGPASSWORD" = "x" ]; then
    export PGPASSWORD=$POSTGRES_PASSWORD
fi

if [ "x$REPLICATION_PORT" == "x" ]; then
    REPLICATION_PORT=5432
fi


# Based on official postgres package's entrypoint script (https://hub.docker.com/_/postgres/)
# Modified to be able to set up a slave. The docker-entrypoint-initdb.d hook provided is inadequate.

set -e

if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi

if [ "$1" = 'postgres' ]; then
	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"
	chown -R postgres "$PGDATA"

	mkdir -p /run/postgresql
	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
	    if [ "x$REPLICATION_HOST" == "x" ]; then
			eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"
	    else
        	until ping -c 1 -W 1 ${REPLICATION_HOST}
        	do
            	echo "Waiting for master to ping..."
            	sleep 1s
        	done
        	until gosu postgres pg_basebackup -h ${REPLICATION_HOST} -p ${REPLICATION_PORT} -D ${PGDATA} -U ${POSTGRES_USER} -vP -w
        	do
            	echo "Waiting for master to connect..."
            	sleep 1s
        	done
	    fi

		# check password first so we can output the warning before postgres
		# messes it up
		if [ "$POSTGRES_PASSWORD" ]; then
			pass="PASSWORD '$POSTGRES_PASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.

				         Use "-e POSTGRES_PASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			pass=
			authMethod=trust
		fi

		if [ "x$REPLICATION_HOST" == "x" ]; then

			{ echo; echo "host replication all 0.0.0.0/0 $authMethod"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
			{ echo; echo "host all all 0.0.0.0/0 $authMethod"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null

			# internal start of server in order to allow set-up using psql-client		
			# does not listen on external TCP/IP and waits until start finishes
			gosu postgres pg_ctl -D "$PGDATA" \
				-o "-c listen_addresses='localhost'" \
				-w start

			: ${POSTGRES_USER:=postgres}
			: ${POSTGRES_DB:=$POSTGRES_USER}
			export POSTGRES_USER POSTGRES_DB

			psql=( psql -v ON_ERROR_STOP=1 )

			if [ "$POSTGRES_DB" != 'postgres' ]; then
				"${psql[@]}" --username postgres <<-EOSQL
					CREATE DATABASE "$POSTGRES_DB" ;
				EOSQL
				echo
			fi

			if [ "$POSTGRES_USER" = 'postgres' ]; then
				op='ALTER'
			else
				op='CREATE'
			fi
			"${psql[@]}" --username postgres <<-EOSQL
				$op User "$POSTGRES_USER" WITH SUPERUSER $pass ;
			EOSQL
			echo
		
		fi
		psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		if [ "x$REPLICATION_HOST" == "x" ]; then
		
			echo "Number Of Databases: ${#db_array[@]}"

			if [ "${#db_array[@]}" -ge "1" ]; then

				echo "Number Of Users: ${#user_array[@]}"

				if [ "${#user_array[@]}" -eq "0" ]; then

					echo "************* Creating Databases with default User ***************"

					for db in "${db_array[@]}"
					do
						echo "Creating database: ${db}"
						"${psql[@]}" --username postgres <<-EOSQL
							CREATE DATABASE ${db} OWNER ${POSTGRES_USER};
						EOSQL
					done

				else
					echo "************* Creating Databases with **DIFFERENT** Users ***************"

					idx=0
					for user in "${user_array[@]}"
					do
						echo "Creating user: ${user} with pass: ${pass_array[${idx}]}"
						"${psql[@]}" --username postgres <<-EOSQL
							CREATE USER ${user_array[${idx}]} WITH $OTHER_USER_PRIVILEGES PASSWORD '${pass_array[${idx}]}';
						EOSQL
						let idx=${idx}+1
					done

					idx=0
					for db in "${db_array[@]}"
					do
						echo "Creating database: ${db}"
						"${psql[@]}" --username postgres <<-EOSQL
							CREATE DATABASE ${db} OWNER ${user_array[${idx}]};
						EOSQL
						let idx=${idx}+1
					done
				fi
			fi
		fi

	if [ "x$REPLICATION_HOST" == "x" ]; then
		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
		echo '****************'
		echo 'I AM MASTER'
		echo '****************'
    else
        echo '****************'
        echo 'I AM SLAVE'
        echo '****************'

	fi

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

	exec gosu postgres "$@"
fi

exec "$@"
