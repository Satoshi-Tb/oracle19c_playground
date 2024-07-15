FROM iamseth/oracledb_exporter

COPY custom-metrics.toml /

ENTRYPOINT ["/oracledb_exporter", "--custom.metrics", "/custom-metrics.toml"]