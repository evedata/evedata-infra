# PostgreSQL Initial Tuning Recommendations

Based on infrastructure discovery performed on 2025-01-11 using Ansible ad-hoc commands.

## Infrastructure Summary

### Hardware Specifications (Both Production and Staging)
- **CPU**: AMD EPYC 7502P 32-Core Processor (64 threads total)
- **Memory**: 128 GB RAM (125.77 GiB available)
- **Storage**:
  - Production: 7 TB RAID10 array (4x 3.5TB NVMe drives)
  - Staging: 3.5 TB RAID10 array (4x 1.7TB NVMe drives)
- **Network**: 1 Gbps private network, 10 Gbps public interface
- **OS**: Ubuntu 24.04 LTS (kernel 6.8.0-51-generic)
- **Architecture**: x86_64, single NUMA node

## Answers to Design Questions

### 1. Database Sizing and Workload

**Expected database size**:
- Initial: 100-500 GB based on available storage
- Growth: Plan for 1-2 TB within first year
- Storage available: 7 TB (production), 3.5 TB (staging)

**Workload type**: Mixed OLTP/OLAP
- Primary: OLTP for EVE Online market data ingestion
- Secondary: OLAP for analytics and reporting
- Read/write ratio: 70/30 expected

**Connection patterns**:
- Direct connections: 200 max
- Application connections via pgBouncer: 2000 max
- Expected concurrent active: 50-100

**Memory allocation**:
- PostgreSQL: 50% of system RAM (64 GB)
- Remaining 50% for OS cache and co-located services

**Storage configuration**:
- NVMe RAID10 provides excellent performance
- No separate volumes needed initially
- Consider partitioning for future growth

### 2. Backup Strategy

**Backup frequency**:
```yaml
pgbackrest_full_backup_schedule: "0 2 * * 0"     # Sunday 2 AM
pgbackrest_diff_backup_schedule: "0 2 * * 1-6"   # Mon-Sat 2 AM
pgbackrest_incr_backup_schedule: "0 */6 * * *"   # Every 6 hours
```

**Retention policy**:
- Full backups: 4 weeks
- Differential backups: 2 weeks
- WAL archives: 7 days
- Point-in-time recovery window: 7 days

**Backup storage**:
- Primary: Local disk (plenty of space available)
- Future: S3-compatible storage for offsite copies

**Recovery objectives**:
- RPO (Recovery Point Objective): 1 hour
- RTO (Recovery Time Objective): 4 hours

### 3. Network and Security

**Network interfaces**:
- PostgreSQL: Listen on private network only (10.0.0.0/16)
- pgBouncer: Listen on all interfaces for application access

**Allowed networks**:
```yaml
postgres_allowed_networks:
  - "10.0.0.0/16"        # Private network
  - "172.16.0.0/12"      # Docker networks (if needed)
```

**SSL/TLS requirements**:
- Mandatory TLS for all remote connections
- Self-signed certificates initially
- Let's Encrypt for production later

**Authentication**:
- Local: peer authentication
- Remote: SCRAM-SHA-256
- Application users: SCRAM-SHA-256 via pgBouncer

### 4. pgBouncer Configuration

**Pool mode**: Transaction pooling (optimal for web applications)

**Pool sizes**:
```yaml
pgbouncer_pool_mode: "transaction"
pgbouncer_max_client_conn: 2000
pgbouncer_default_pool_size: 25
pgbouncer_min_pool_size: 10
pgbouncer_reserve_pool_size: 5
```

**Connection limits**:
- Per database: 100
- Per user: 50
- Total server connections: 200

### 5. Resource Management

**CPU limits** (via cgroups v2):
- PostgreSQL: 50% of CPU (16 cores)
- Allows co-location with other services

**Memory limits**:
- PostgreSQL hard limit: 64 GB
- Shared buffers: 32 GB
- Remaining for work_mem and connections

**I/O throttling**:
- Not initially required due to NVMe performance
- Can add if needed: 500 MB/s limit

### 6. Monitoring and Observability

**Metrics collection**:
- Prometheus exporters (postgres_exporter, pgbouncer_exporter)
- Metrics port: 9187 (PostgreSQL), 9127 (pgBouncer)

**Log aggregation**:
- Local logs with rotation
- Future: Ship to centralized logging

**Alerting thresholds**:
- Connection pool > 80% utilized
- Disk space > 80% used
- Replication lag > 60 seconds
- Long-running queries > 5 minutes

### 7. High Availability

**Initial deployment**: Single-node (no HA initially)

**Future HA strategy**:
- Streaming replication to standby
- Manual failover initially
- Consider Patroni for automated failover

### 8. Maintenance and Operations

**Update strategy**:
- Security patches: Automatic
- Minor versions: Monthly maintenance window
- Major versions: Quarterly planning

**Maintenance windows**:
- Sunday 3-5 AM UTC

**Required extensions**:
```yaml
postgres_extensions:
  - pg_stat_statements  # Query performance monitoring
  - pgcrypto           # Encryption functions
  - uuid-ossp          # UUID generation
  - pg_trgm            # Trigram similarity
```

## PostgreSQL Performance Tuning Parameters

### Memory Configuration
```yaml
# Based on 128 GB RAM
postgres_shared_buffers: "32GB"              # 25% of RAM
postgres_effective_cache_size: "96GB"        # 75% of RAM
postgres_maintenance_work_mem: "4GB"         # For VACUUM, CREATE INDEX
postgres_work_mem: "256MB"                   # Per operation
postgres_hash_mem_multiplier: 2.0            # For hash operations
postgres_logical_decoding_work_mem: "256MB"  # For replication

# Huge pages configuration
postgres_huge_pages: "on"                    # Requires OS configuration
postgres_huge_page_size: "2MB"
```

### Connection Settings
```yaml
postgres_max_connections: 200                # Direct connections
postgres_superuser_reserved_connections: 5   # Admin access
postgres_max_prepared_transactions: 0        # Not using 2PC
postgres_track_activities: true
postgres_track_counts: true
postgres_track_io_timing: true               # Important for monitoring
```

### Checkpoint and WAL Configuration
```yaml
# Optimized for NVMe storage
postgres_checkpoint_segments: 64             # Legacy, for reference
postgres_checkpoint_completion_target: 0.9   # Spread checkpoint I/O
postgres_checkpoint_timeout: "30min"         # Longer for stability
postgres_checkpoint_warning: "10min"         # Alert on slow checkpoints
postgres_max_wal_size: "16GB"                # Plenty of space available
postgres_min_wal_size: "2GB"
postgres_wal_keep_size: "4GB"               # For replication slots
postgres_wal_buffers: "64MB"                # Auto-tuned from shared_buffers
postgres_wal_compression: "lz4"             # NVMe can handle it
postgres_wal_init_zero: false               # Faster WAL creation
postgres_wal_recycle: true
postgres_wal_sync_method: "fdatasync"       # Best for Linux
postgres_full_page_writes: true             # Data safety
postgres_wal_level: "replica"               # For backups and replication
postgres_archive_mode: true                 # Enable WAL archiving
postgres_archive_command: "pgbackrest --stanza=main archive-push %p"
postgres_archive_timeout: "5min"            # Force archive on quiet periods
```

### Storage Optimization (NVMe RAID10)
```yaml
# Tuned for NVMe SSD
postgres_random_page_cost: 1.1              # Nearly sequential performance
postgres_effective_io_concurrency: 256      # NVMe parallel I/O
postgres_maintenance_io_concurrency: 256    # For maintenance operations
postgres_max_worker_processes: 32           # Match CPU cores
postgres_max_parallel_workers: 32           # Parallel query execution
postgres_max_parallel_workers_per_gather: 8 # Per query parallelism
postgres_max_parallel_maintenance_workers: 8 # For CREATE INDEX, VACUUM
postgres_parallel_leader_participation: true

# Background writer tuning
postgres_bgwriter_delay: "200ms"
postgres_bgwriter_lru_maxpages: 1000
postgres_bgwriter_lru_multiplier: 4.0
postgres_bgwriter_flush_after: "512kB"
```

### Query Planning
```yaml
postgres_default_statistics_target: 100     # Better statistics
postgres_enable_partitionwise_join: true    # For partitioned tables
postgres_enable_partitionwise_aggregate: true
postgres_jit: true                          # JIT compilation
postgres_jit_above_cost: 100000            # JIT threshold
postgres_geqo: true                         # Genetic query optimizer
postgres_geqo_threshold: 12                # For complex joins
postgres_from_collapse_limit: 8
postgres_join_collapse_limit: 8
```

### Autovacuum Configuration
```yaml
# Aggressive autovacuum for OLTP workload
postgres_autovacuum: true
postgres_autovacuum_max_workers: 8          # Plenty of CPU available
postgres_autovacuum_naptime: "30s"          # Frequent checks
postgres_autovacuum_vacuum_scale_factor: 0.05  # 5% of table
postgres_autovacuum_analyze_scale_factor: 0.02 # 2% of table
postgres_autovacuum_vacuum_cost_delay: "2ms"
postgres_autovacuum_vacuum_cost_limit: 10000   # Aggressive
postgres_autovacuum_freeze_max_age: 200000000
postgres_autovacuum_multixact_freeze_max_age: 400000000
postgres_vacuum_freeze_min_age: 50000000
postgres_vacuum_freeze_table_age: 150000000
```

### Lock Management
```yaml
postgres_deadlock_timeout: "1s"
postgres_max_locks_per_transaction: 256     # Increase for many tables
postgres_max_pred_locks_per_transaction: 256
postgres_max_pred_locks_per_relation: -2    # Auto
postgres_max_pred_locks_per_page: 2
```

### Logging Configuration
```yaml
postgres_log_destination: "csvlog"
postgres_logging_collector: true
postgres_log_directory: "/var/log/postgresql"
postgres_log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
postgres_log_file_mode: 0640
postgres_log_rotation_age: "1d"
postgres_log_rotation_size: "1GB"
postgres_log_truncate_on_rotation: false

# What to log
postgres_log_min_messages: "warning"
postgres_log_min_error_statement: "error"
postgres_log_min_duration_statement: 1000   # Log slow queries > 1s
postgres_log_checkpoints: true
postgres_log_connections: true
postgres_log_disconnections: true
postgres_log_duration: false                # Too verbose
postgres_log_error_verbosity: "default"
postgres_log_hostname: true
postgres_log_line_prefix: "%m [%p] %q%u@%d "
postgres_log_lock_waits: true
postgres_log_statement: "ddl"               # Log schema changes
postgres_log_temp_files: 0                  # Log all temp files
postgres_log_timezone: "UTC"
postgres_log_autovacuum_min_duration: 1000  # Log slow autovacuum
```

## pgBouncer Tuning Parameters

```yaml
# Connection pooling configuration
pgbouncer_listen_port: 6432
pgbouncer_listen_addr: "*"
pgbouncer_auth_type: "scram-sha-256"
pgbouncer_auth_file: "/etc/pgbouncer/userlist.txt"

# Pool configuration
pgbouncer_pool_mode: "transaction"
pgbouncer_max_client_conn: 2000
pgbouncer_default_pool_size: 25
pgbouncer_min_pool_size: 10
pgbouncer_reserve_pool_size: 5
pgbouncer_reserve_pool_timeout: 5
pgbouncer_max_db_connections: 100
pgbouncer_max_user_connections: 50

# Performance tuning
pgbouncer_server_reset_query: "DISCARD ALL"
pgbouncer_server_reset_query_always: false
pgbouncer_server_check_query: "SELECT 1"
pgbouncer_server_check_delay: 30
pgbouncer_server_lifetime: 3600            # 1 hour
pgbouncer_server_idle_timeout: 600         # 10 minutes
pgbouncer_server_connect_timeout: 15
pgbouncer_server_login_retry: 15
pgbouncer_query_timeout: 0                 # No limit
pgbouncer_query_wait_timeout: 120          # 2 minutes
pgbouncer_client_idle_timeout: 0           # No limit
pgbouncer_client_login_timeout: 60
pgbouncer_autodb_idle_timeout: 3600

# Buffer sizes
pgbouncer_pkt_buf: 4096
pgbouncer_sbuf_loopcnt: 5
pgbouncer_tcp_defer_accept: true
pgbouncer_tcp_socket_buffer: 0             # OS default
pgbouncer_tcp_keepalive: true
pgbouncer_tcp_keepcnt: 3
pgbouncer_tcp_keepidle: 600
pgbouncer_tcp_keepintvl: 60
pgbouncer_tcp_user_timeout: 0
```

## pgBackRest Configuration

```yaml
# Repository configuration
pgbackrest_stanza: "main"
pgbackrest_repo1_type: "posix"
pgbackrest_repo1_path: "/var/lib/postgresql/backups"
pgbackrest_repo1_retention_full: 4         # 4 full backups
pgbackrest_repo1_retention_diff: 14        # 2 weeks of diffs
pgbackrest_repo1_retention_archive: "7"    # 7 days of WAL

# Future S3 configuration (commented out initially)
# pgbackrest_repo2_type: "s3"
# pgbackrest_repo2_s3_bucket: "evedata-postgres-backups"
# pgbackrest_repo2_s3_region: "eu-central-1"
# pgbackrest_repo2_s3_key: "{{ vault_s3_access_key }}"
# pgbackrest_repo2_s3_key_secret: "{{ vault_s3_secret_key }}"

# Performance tuning for NVMe
pgbackrest_process_max: 8                  # Parallel processes
pgbackrest_compress_type: "lz4"            # Fast compression
pgbackrest_compress_level: 3               # Balanced compression
pgbackrest_archive_async: true             # Async WAL archiving
pgbackrest_archive_push_queue_max: "4GiB"  # Large queue for bursts
pgbackrest_backup_standby: false           # No standby yet
pgbackrest_start_fast: true                # Don't wait for checkpoint
pgbackrest_stop_auto: true                 # Stop backup if needed
pgbackrest_resume: true                    # Resume failed backups
pgbackrest_repo1_bundle: true              # Bundle small files
pgbackrest_repo1_bundle_size: "64MiB"      # Bundle size
pgbackrest_repo1_bundle_limit: 32          # Parallel bundles

# Network/transfer settings
pgbackrest_repo1_host_cmd: "/usr/bin/pgbackrest"
pgbackrest_io_timeout: 3600                # 1 hour timeout
pgbackrest_db_timeout: 3600
pgbackrest_protocol_timeout: 3660          # Slightly more than io
pgbackrest_spool_path: "/var/spool/pgbackrest"
pgbackrest_buffer_size: "4MiB"             # Transfer buffer
```

## System Kernel Tuning

```yaml
# Kernel parameters for PostgreSQL
postgres_kernel_params:
  # Memory
  vm.swappiness: 5                         # Minimize swapping
  vm.overcommit_memory: 2                  # Don't overcommit
  vm.overcommit_ratio: 95                  # Use most RAM
  vm.dirty_background_ratio: 5             # Start writing at 5%
  vm.dirty_ratio: 40                       # Block at 40%
  vm.dirty_expire_centisecs: 3000          # 30 seconds
  vm.dirty_writeback_centisecs: 500        # 5 seconds

  # Huge pages (requires calculation based on shared_buffers)
  vm.nr_hugepages: 16384                   # 32GB / 2MB
  vm.hugetlb_shm_group: 115               # postgres group

  # Network tuning
  net.core.rmem_max: 134217728
  net.core.wmem_max: 134217728
  net.ipv4.tcp_rmem: "4096 87380 134217728"
  net.ipv4.tcp_wmem: "4096 65536 134217728"
  net.core.netdev_max_backlog: 5000
  net.ipv4.tcp_tw_recycle: 0              # Disabled for safety
  net.ipv4.tcp_tw_reuse: 1
  net.ipv4.tcp_max_syn_backlog: 8192
  net.core.somaxconn: 65535
  net.ipv4.tcp_keepalive_time: 600
  net.ipv4.tcp_keepalive_probes: 3
  net.ipv4.tcp_keepalive_intvl: 60

  # File system
  fs.file-max: 2097152
  fs.aio-max-nr: 1048576

  # IPC
  kernel.shmmax: 68719476736               # 64GB
  kernel.shmall: 16777216                  # 64GB / 4KB pages
  kernel.shmmni: 4096
  kernel.sem: "500 2048000 200 40960"
```

## Systemd Resource Limits

```yaml
# systemd slice configuration for PostgreSQL
postgres_systemd_slice: "postgresql.slice"
postgres_systemd_limits:
  CPUQuota: "50%"                          # 16 cores
  MemoryMax: "64G"                         # Hard limit
  MemoryHigh: "60G"                        # Soft limit
  TasksMax: 8192
  IOWeight: 100                            # Default priority
  # IOReadBandwidthMax: "/dev/nvme0n1 500M" # If throttling needed
  # IOWriteBandwidthMax: "/dev/nvme0n1 500M"

# systemd service hardening
postgres_systemd_hardening:
  PrivateTmp: true
  ProtectSystem: strict
  ProtectHome: true
  NoNewPrivileges: true
  RestrictSUIDSGID: true
  RemoveIPC: false                         # PostgreSQL needs IPC
  RestrictRealtime: true
  RestrictNamespaces: true
  LockPersonality: true
  ProtectKernelTunables: true
  ProtectKernelModules: true
  ProtectControlGroups: true
  PrivateDevices: true
  RestrictAddressFamilies: "AF_UNIX AF_INET AF_INET6"
  SystemCallFilter: "@system-service"
  SystemCallErrorNumber: "EPERM"
```

## Security Hardening

```yaml
# AppArmor profile
postgres_apparmor_enabled: true
postgres_apparmor_mode: "enforce"          # or "complain" for testing

# SSL/TLS configuration
postgres_ssl: true
postgres_ssl_ciphers: "HIGH:MEDIUM:+3DES:!aNULL"
postgres_ssl_prefer_server_ciphers: true
postgres_ssl_ecdh_curve: "prime256v1"
postgres_ssl_dh_params_size: 2048
postgres_ssl_min_protocol_version: "TLSv1.2"
postgres_ssl_max_protocol_version: "TLSv1.3"

# Authentication
postgres_password_encryption: "scram-sha-256"
postgres_scram_iterations: 4096

# Firewall rules (UFW)
postgres_ufw_rules:
  - port: 5432
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "PostgreSQL from private network"
  - port: 6432
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "pgBouncer from private network"
  - port: 9187
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "PostgreSQL exporter"
  - port: 9127
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "pgBouncer exporter"
```

## Complete Ansible Variable File Example

```yaml
# group_vars/database.yml
---
# PostgreSQL version and installation
postgres_version: "16"
postgres_install_from: "pgdg"
postgres_pgdg_repo_key_url: "https://www.postgresql.org/media/keys/ACCC4CF8.asc"
postgres_pgdg_repo: "deb https://apt.postgresql.org/pub/repos/apt {{ ansible_distribution_release }}-pgdg main"

# Basic configuration
postgres_cluster_name: "main"
postgres_data_directory: "/var/lib/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}"
postgres_config_directory: "/etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}"
postgres_pid_file: "/var/run/postgresql/{{ postgres_version }}-{{ postgres_cluster_name }}.pid"
postgres_port: 5432
postgres_unix_socket_directories: "/var/run/postgresql"
postgres_listen_addresses: "localhost,10.0.0.{{ ansible_hostname.split('-')[-1].split('srv')[-1] }}"

# Resource allocation (50% of system resources for co-location)
postgres_shared_buffers: "32GB"
postgres_effective_cache_size: "96GB"
postgres_maintenance_work_mem: "4GB"
postgres_work_mem: "256MB"
postgres_huge_pages: "on"
postgres_max_connections: 200

# Performance tuning for NVMe
postgres_random_page_cost: 1.1
postgres_effective_io_concurrency: 256
postgres_max_worker_processes: 32
postgres_max_parallel_workers: 32
postgres_max_parallel_workers_per_gather: 8
postgres_jit: true

# WAL and checkpoints
postgres_wal_level: "replica"
postgres_max_wal_size: "16GB"
postgres_min_wal_size: "2GB"
postgres_checkpoint_completion_target: 0.9
postgres_checkpoint_timeout: "30min"
postgres_wal_compression: "lz4"
postgres_archive_mode: true
postgres_archive_command: "pgbackrest --stanza=main archive-push %p"

# Autovacuum
postgres_autovacuum: true
postgres_autovacuum_max_workers: 8
postgres_autovacuum_naptime: "30s"
postgres_autovacuum_vacuum_scale_factor: 0.05
postgres_autovacuum_analyze_scale_factor: 0.02

# Logging
postgres_log_destination: "csvlog"
postgres_logging_collector: true
postgres_log_min_duration_statement: 1000
postgres_log_checkpoints: true
postgres_log_connections: true
postgres_log_lock_waits: true

# Security
postgres_ssl: true
postgres_password_encryption: "scram-sha-256"

# pgBouncer
pgbouncer_enabled: true
pgbouncer_pool_mode: "transaction"
pgbouncer_max_client_conn: 2000
pgbouncer_default_pool_size: 25

# pgBackRest
pgbackrest_enabled: true
pgbackrest_stanza: "main"
pgbackrest_repo1_retention_full: 4
pgbackrest_repo1_retention_diff: 14
pgbackrest_process_max: 8
pgbackrest_compress_type: "lz4"

# Monitoring
postgres_exporter_enabled: true
pgbouncer_exporter_enabled: true

# Users and databases (to be defined per environment)
postgres_users: []
postgres_databases: []
```

## Implementation Priority

1. **Phase 1 - Core PostgreSQL** (Week 1)
   - Basic PostgreSQL installation from PGDG
   - Memory and performance tuning
   - Basic security (local access only)

2. **Phase 2 - Connection Pooling** (Week 1-2)
   - pgBouncer installation and configuration
   - Application user setup
   - Connection pool tuning

3. **Phase 3 - Backups** (Week 2)
   - pgBackRest installation
   - Local backup configuration
   - Backup schedule and testing

4. **Phase 4 - Hardening** (Week 3)
   - SSL/TLS configuration
   - Firewall rules
   - Resource limits via systemd
   - AppArmor profile

5. **Phase 5 - Monitoring** (Week 3-4)
   - Prometheus exporters
   - Log aggregation
   - Alerting setup

6. **Phase 6 - High Availability** (Future)
   - Streaming replication
   - Standby server configuration
   - Failover procedures

## Testing Checklist

- [ ] PostgreSQL installs successfully from PGDG
- [ ] Memory parameters are correctly calculated
- [ ] pgBouncer handles connection pooling
- [ ] pgBackRest performs successful backups
- [ ] Restore from backup works
- [ ] SSL/TLS connections work
- [ ] Firewall rules are active
- [ ] Resource limits are enforced
- [ ] Monitoring endpoints are accessible
- [ ] Performance meets expectations (pgbench)

## Notes

1. These settings are optimized for your AMD EPYC processors and NVMe storage
2. The 50% resource allocation allows for co-location with other services
3. Adjust work_mem based on actual query patterns
4. Monitor and tune autovacuum based on workload
5. Consider enabling log_statement='all' temporarily for workload analysis
6. Test all settings thoroughly in staging before production deployment