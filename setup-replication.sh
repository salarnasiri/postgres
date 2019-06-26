	#!/bin/bash

if [ "x$REPLICATION_HOST" == "x" ]; then

cat >> ${PGDATA}/postgresql.conf <<EOF
wal_level = hot_standby
max_wal_senders = $PG_MAX_WAL_SENDERS
wal_keep_segments = $PG_WAL_KEEP_SEGMENTS
hot_standby = on

max_connections = $PG_MAX_CONNECTIONS
wal_buffers = $PG_WAL_BUFFERS
checkpoint_timeout = $PG_CHECKPOINT_TIMEOUT
max_wal_size = $PG_MAX_WAL_SIZE
min_wal_size = $PG_MIN_WAL_SIZE
checkpoint_completion_target = $PG_CHECHPOINT_COMPLETION_TARGET
log_min_duration_statement = $PG_LOG_MIN_DURATION_STATEMENT

archive_mode = on
archive_command = 'cd .'

EOF

else

cat > ${PGDATA}/recovery.conf <<EOF
standby_mode = on
primary_conninfo = 'host=${REPLICATION_HOST} port=${REPLICATION_PORT} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD}'
recovery_target_timeline='latest'
trigger_file = '/tmp/touch_me_to_promote_me_to_master'
EOF
chown postgres ${PGDATA}/recovery.conf
chmod 600 ${PGDATA}/recovery.conf

fi
