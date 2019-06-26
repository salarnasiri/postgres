FROM postgres:10.9
MAINTAINER SALAR

ENV PG_MAX_WAL_SENDERS 5
ENV PG_WAL_KEEP_SEGMENTS 60
ENV PG_MAX_CONNECTIONS 500
ENV PG_WAL_BUFFERS 16MB
ENV PG_CHECKPOINT_TIMEOUT 30min
ENV PG_MAX_WAL_SIZE 1GB
ENV PG_MIN_WAL_SIZE 500MB
ENV PG_CHECHPOINT_COMPLETION_TARGET 0.8
ENV PG_LOG_MIN_DURATION_STATEMENT 100

COPY setup-replication.sh /docker-entrypoint-initdb.d/
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY create_db.sh /create_db.sh
RUN chmod +x /docker-entrypoint-initdb.d/setup-replication.sh /docker-entrypoint.sh /create_db.sh
