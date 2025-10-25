# PostgreSQL Ansible Role Specification

## 1. Overview and Purpose

This role provisions and configures a production-grade PostgreSQL 18 database server on Ubuntu 24.04 LTS hosts. The role is designed for single-host deployments that may be co-located with other services, providing robust isolation, security hardening, connection pooling via pgBouncer, and backup capabilities through pgBackRest.

### Key Capabilities

- PostgreSQL 18 installation from official PGDG repositories
- Native JSON structured logging for enhanced observability
- Internal hardening for service isolation on shared hosts
- External hardening for network security
- Connection pooling with pgBouncer
- Automated backups with pgBackRest
- Performance tuning based on workload characteristics
- Monitoring integration hooks
- Maintenance window support with minimal downtime

## 2. Key Design Questions Requiring User Input

### 2.1 Database Sizing and Workload

- **Expected database size**: Initial size and growth projections (GB/TB)?
- **Connection patterns**: Maximum concurrent connections expected?
- **Workload type**: OLTP, OLAP, or mixed? Read/write ratio?
- **Memory allocation**: What percentage of system RAM should PostgreSQL use?
- **Storage type**: SSD/NVMe? Separate volumes for data/WAL/backups?
- **Table sizes**: Expected largest tables? Partitioning requirements?

### 2.2 Backup Strategy

- **Backup frequency**: Full and incremental backup schedules?
- **Retention policy**: How many days/weeks/months of backups to retain?
- **Backup storage**: Local disk, remote server via SSH, or S3-compatible storage?
- **Recovery objectives**: RPO (Recovery Point Objective) and RTO (Recovery Time Objective)?
- **Point-in-time recovery**: Required time window for PITR capability?
- **Backup verification**: Automated restore testing requirements?

### 2.3 Network and Security

- **Network interfaces**: Which interfaces should PostgreSQL listen on?
- **Allowed networks**: CIDR blocks for client connections?
- **SSL/TLS requirements**:
  - Mandatory TLS for all connections?
  - Client certificate authentication?
  - Certificate management (self-signed, Let's Encrypt, custom CA)?
- **Firewall rules**: UFW or iptables preference?
- **VPN/tunnel requirements**: WireGuard or other VPN for remote access?

### 2.4 Authentication and Users

- **Authentication methods**:
  - Local users: peer, md5, or scram-sha-256?
  - Remote users: password, certificate, or LDAP/AD?
- **Database users**: List of application users and their privileges?
- **Admin access**: Separate admin users for different teams?
- **Password rotation**: Automated rotation requirements?

### 2.5 Monitoring and Observability

- **Metrics collection**: Prometheus, Telegraf, or custom?
- **Log aggregation**: Destination for logs (local, syslog, ELK, etc.)?
- **Alerting thresholds**:
  - Connection pool exhaustion?
  - Replication lag (if applicable)?
  - Disk space utilization?
  - Long-running queries?
- **Query performance**: pg_stat_statements configuration?

### 2.6 High Availability and Disaster Recovery

- **Replication requirements**: Streaming replication to standby servers?
- **Failover strategy**: Manual or automated failover?
- **Load balancing**: Read replica requirements?
- **Cross-region backups**: Geographic redundancy needs?

### 2.7 Resource Management

- **CPU limits**: cgroup CPU quota/shares?
- **Memory limits**: Hard memory limits vs soft limits?
- **I/O throttling**: Disk I/O bandwidth limits?
- **Process limits**: Maximum number of PostgreSQL processes?
- **Nice levels**: Process priority adjustments?

### 2.8 pgBouncer Configuration

- **Pool mode**: session, transaction, or statement pooling?
- **Pool sizes**: Default, minimum, and maximum pool sizes?
- **Authentication**: pgBouncer auth file or auth_query?
- **Connection limits**: Per-database and per-user limits?
- **Timeout settings**: Client, server, and query timeouts?

### 2.9 Maintenance and Operations

- **Maintenance windows**: Scheduled downtime windows?
- **Automatic updates**: Security patches only or all updates?
- **VACUUM strategy**: Autovacuum tuning parameters?
- **Statistics updates**: ANALYZE frequency?
- **Extension management**: Required PostgreSQL extensions?

## 3. Architecture Decisions

### 3.1 Component Layout

```
/var/lib/postgresql/
├── 18/                       # PostgreSQL 18 data directory
│   └── main/
├── backups/                  # pgBackRest local repository
└── wal_archive/             # WAL archive directory

/etc/postgresql/
├── 18/
│   └── main/
│       ├── postgresql.conf  # Main configuration
│       ├── pg_hba.conf      # Host-based authentication
│       └── pg_ident.conf    # User name mapping
├── pgbouncer/
│   ├── pgbouncer.ini       # pgBouncer configuration
│   └── userlist.txt        # pgBouncer authentication
└── pgbackrest/
    └── pgbackrest.conf      # pgBackRest configuration

/var/log/postgresql/         # PostgreSQL JSON logs
/var/log/pgbouncer/         # pgBouncer logs
/var/log/pgbackrest/        # pgBackRest logs
```

### 3.2 Service Architecture

- **PostgreSQL**: Primary database service running under postgres user
- **pgBouncer**: Connection pooler running on port 6432 (default)
- **pgBackRest**: Backup daemon for scheduled backups
- **systemd integration**: All services managed via systemd with proper dependencies

#### pgBouncer Connection Architecture

**Version 1.0 Architecture Decision**: Applications may connect either directly to PostgreSQL (port 5432) or through pgBouncer (port 6432). This role supports both patterns:

1. **Direct Connection Pattern**:
   - Applications connect directly to PostgreSQL on port 5432
   - pgBouncer is available for administrative/monitoring connections
   - Use when applications require PostgreSQL features incompatible with transaction pooling (prepared statements, advisory locks, LISTEN/NOTIFY)

2. **Pooled Connection Pattern**:
   - Applications connect exclusively through pgBouncer on port 6432
   - Direct PostgreSQL access restricted to localhost in pg_hba.conf
   - Recommended for high-concurrency applications with simple query patterns

**Configuration Impact**: Set `postgresql_pgbouncer_mandatory: true` to restrict direct PostgreSQL access and force all external connections through pgBouncer.

### 3.3 Port Allocation

- PostgreSQL: 5432 (configurable)
- pgBouncer: 6432 (configurable)
- Monitoring exporters: 9187 (postgres_exporter), 9127 (pgbouncer_exporter)

**Security Note**: Monitoring exporter ports should be restricted to monitoring systems only via firewall rules. Consider enabling authentication for these endpoints in production environments.

## 4. Security Model

### 4.1 Internal Hardening (Service Isolation)

- **User isolation**: Dedicated postgres system user with minimal privileges
- **File permissions**:
  - Data directory: 0700 (postgres:postgres)
  - Configuration files: 0640 (postgres:postgres)
  - SSL certificates: 0600 (postgres:postgres)
- **systemd hardening**:
  - PrivateTmp=true
  - ProtectSystem=strict
  - ProtectHome=true
  - NoNewPrivileges=true
  - RestrictSUIDSGID=true
  - RemoveIPC=true
- **Resource limits via cgroups v2** (see implementation details below):
  - Memory limits with memory.max
  - CPU limits with cpu.max
  - I/O limits with io.max
- **AppArmor profile**: Restrict file access to PostgreSQL directories only
- **Network namespace isolation** (optional): Separate network stack

### 4.2 External Hardening

- **Network security**:
  - UFW firewall rules restricting access to specific sources
  - SSL/TLS enforcement for all remote connections
  - Certificate validation for mutual TLS
- **Authentication hardening**:
  - SCRAM-SHA-256 as default auth method
  - Strong password policy enforcement
  - Connection attempt rate limiting
  - Failed authentication logging and alerting
- **Query security**:
  - Statement timeout defaults
  - SQL injection prevention guidelines
- **Audit logging**:
  - pgAudit extension for compliance
  - Log all DDL statements
  - Connection/disconnection logging

### 4.3 Certificate Management Strategy

**Version 1.0 Approach**: This role expects SSL certificates to be provided externally and does not handle certificate provisioning or renewal.

**Certificate Requirements**:
- Server certificate and private key must exist at specified paths before role execution
- Certificates should be readable by the postgres user (0600 permissions)
- Certificate paths are configurable via variables:
  ```yaml
  postgresql_ssl_cert_file: "/etc/postgresql/server.crt"
  postgresql_ssl_key_file: "/etc/postgresql/server.key"
  postgresql_ssl_ca_file: "/etc/postgresql/ca.crt"  # Optional for client cert auth
  ```

**Recommended External Solutions**:
- Let's Encrypt with manual certificate deployment
- Organization PKI with certificate deployment automation
- Cloud provider certificate management services

**Future Enhancement**: v1.4 will include Let's Encrypt integration and automated certificate renewal.

### 4.5 Resource Limits Implementation

**cgroups v2 Configuration**: This role creates dedicated systemd service units with resource limits for PostgreSQL services:

```yaml
# Resource limit variables
postgresql_memory_limit: "{{ (ansible_memtotal_mb * 0.8) | int }}MB"  # 80% of system RAM
postgresql_cpu_quota: "80%"  # 80% of total CPU capacity
postgresql_io_weight: 100  # Default I/O weight (1-10000)
postgresql_io_read_bandwidth_max: "500M"  # Max read bandwidth
postgresql_io_write_bandwidth_max: "300M"  # Max write bandwidth
```

**Implementation Approach**:
1. **Memory Limits**: Set as "soft" limits allowing bursting but preventing runaway memory usage
2. **CPU Limits**: Configure CPU quota to prevent PostgreSQL from monopolizing CPU on shared hosts
3. **I/O Limits**: Throttle disk I/O to ensure other services remain responsive
4. **Monitoring**: Resource usage tracked via systemd metrics and included in monitoring exports

**Validation**: The role validates that cgroup limits are compatible with PostgreSQL memory settings (shared_buffers + work_mem * max_connections < memory_limit).

**systemd Configuration**:
```ini
# /etc/systemd/system/postgresql@18-main.service.d/resources.conf
[Service]
MemoryMax={{ postgresql_memory_limit }}
CPUQuota={{ postgresql_cpu_quota }}
IOWeight={{ postgresql_io_weight }}
```

### 4.4 Variable Validation Strategy

**Input Validation**: The role validates critical variables using Ansible's `assert` module to prevent configuration errors:

```yaml
# Example validations performed
- name: "Validate PostgreSQL configuration"
  assert:
    that:
      - postgresql_max_connections | int > 0
      - postgresql_shared_buffers is match('^[0-9]+[KMGT]?B$')
      - postgresql_version in ['18']
      - postgresql_port | int >= 1024 and postgresql_port | int <= 65535
    fail_msg: "Invalid PostgreSQL configuration detected"
```

**Memory Configuration Validation**: Auto-calculated memory settings are validated to ensure reasonable limits:
- shared_buffers warnings if >40% of system RAM or >32GB
- effective_cache_size warnings if >90% of system RAM
- work_mem warnings if total potential usage exceeds available RAM

## 5. Configuration Management Approach

### 5.1 Variable Hierarchy

```yaml
# defaults/main.yml - Role defaults (lowest priority)
postgresql_version: "18"
postgresql_listen_addresses: "localhost"
postgresql_max_connections: 100

# group_vars/<group>.yml - Group-specific overrides
postgresql_max_connections: 200
postgresql_backup_schedule: "0 2 * * *"

# host_vars/<host>.yml - Host-specific overrides
postgresql_shared_buffers: "4GB"
postgresql_effective_cache_size: "12GB"

# group_vars/vault.yml - Encrypted secrets
postgresql_admin_password: !vault |
  $ANSIBLE_VAULT...
# Note: Replication passwords will be added in v1.2 with streaming replication support
```

### 5.2 Configuration Templates

- **postgresql.conf.j2**: Main configuration with performance tuning
- **pg_hba.conf.j2**: Authentication rules
- **pgbouncer.ini.j2**: Connection pooler configuration
- **pgbackrest.conf.j2**: Backup configuration
- **.pgpass.j2**: Connection credentials for automation

### 5.3 Idempotency Guarantees

- Configuration changes trigger graceful reloads when possible
- Restart-required changes are flagged for maintenance windows
- Backup configuration changes don't interrupt running backups
- User/database creation is idempotent with "IF NOT EXISTS"

## 6. Variable Structure for Tuning

### 6.1 Core Performance Variables

```yaml
# Memory settings (auto-calculated based on system RAM if not specified)
# WARNING: Auto-calculated values should be validated for production use
# Large systems (>64GB RAM) may need manual tuning to avoid excessive shared_buffers
postgresql_shared_buffers: "{{ (ansible_memtotal_mb * 0.25) | int }}MB"
postgresql_effective_cache_size: "{{ (ansible_memtotal_mb * 0.75) | int }}MB"
postgresql_maintenance_work_mem: "{{ (ansible_memtotal_mb * 0.0625) | int }}MB"
postgresql_work_mem: "4MB"
postgresql_huge_pages: "try"

# Connection settings
postgresql_max_connections: 100
postgresql_superuser_reserved_connections: 3
postgresql_max_prepared_transactions: 0

# Checkpoint settings
postgresql_checkpoint_completion_target: 0.9
postgresql_checkpoint_timeout: "15min"
postgresql_max_wal_size: "4GB"
postgresql_min_wal_size: "1GB"

# Write performance
postgresql_wal_buffers: "16MB"
postgresql_wal_compression: true
postgresql_wal_level: "replica"
postgresql_synchronous_commit: "on"
postgresql_commit_delay: 0

# Query tuning
postgresql_random_page_cost: 1.1  # For SSD
postgresql_effective_io_concurrency: 200  # For SSD
postgresql_default_statistics_target: 100
postgresql_jit: true

# Autovacuum settings
postgresql_autovacuum_max_workers: 4
postgresql_autovacuum_naptime: "30s"
postgresql_autovacuum_vacuum_scale_factor: 0.1
postgresql_autovacuum_analyze_scale_factor: 0.05
```

### 6.2 pgBouncer Variables

```yaml
postgresql_pgbouncer_pool_mode: "transaction"
postgresql_pgbouncer_max_client_conn: 1000
postgresql_pgbouncer_default_pool_size: 25
postgresql_pgbouncer_min_pool_size: 5
postgresql_pgbouncer_reserve_pool_size: 5
postgresql_pgbouncer_reserve_pool_timeout: 5
postgresql_pgbouncer_server_lifetime: 3600
postgresql_pgbouncer_server_idle_timeout: 600
postgresql_pgbouncer_query_timeout: 0
postgresql_pgbouncer_query_wait_timeout: 120
postgresql_pgbouncer_client_idle_timeout: 0
postgresql_pgbouncer_client_login_timeout: 60
```

### 6.3 pgBackRest Variables

```yaml
postgresql_pgbackrest_stanza: "{{ inventory_hostname_short }}"
postgresql_pgbackrest_repo_path: "/var/lib/postgresql/backups"
postgresql_pgbackrest_repo_retention_full: 2
postgresql_pgbackrest_repo_retention_diff: 4
postgresql_pgbackrest_repo_retention_archive: "7"  # days
postgresql_pgbackrest_compression_type: "lz4"
postgresql_pgbackrest_compression_level: 3
postgresql_pgbackrest_process_max: 2
postgresql_pgbackrest_archive_async: true
postgresql_pgbackrest_archive_push_queue_max: "4GiB"
postgresql_pgbackrest_backup_standby: false
postgresql_pgbackrest_start_fast: true
postgresql_pgbackrest_stop_auto: true
postgresql_pgbackrest_resume: true

# Backup schedule (cron format)
postgresql_pgbackrest_full_backup_schedule: "0 2 * * 0"  # Sunday 2 AM
postgresql_pgbackrest_diff_backup_schedule: "0 2 * * 1-6"  # Mon-Sat 2 AM
```

## 7. Backup and Recovery Design

### 7.1 Backup Strategy

- **Full backups**: Weekly by default, configurable schedule
- **Differential backups**: Daily, building on last full backup
- **Incremental backups**: Optional, building on last diff/full
- **WAL archiving**: Continuous archiving for point-in-time recovery
- **Parallel backup**: Multiple processes for faster backups
- **Compression**: LZ4 by default for speed/ratio balance
- **Encryption**: Optional AES-256-CBC encryption
- **Checksums**: SHA-256 verification of all backup files

### 7.2 Backup Storage Options

```yaml
# Local repository (default)
postgresql_pgbackrest_repo_type: "posix"
postgresql_pgbackrest_repo_path: "/var/lib/postgresql/backups"

# Remote repository via SSH
postgresql_pgbackrest_repo_type: "posix"
postgresql_pgbackrest_repo_host: "backup-server.example.com"
postgresql_pgbackrest_repo_host_user: "postgres"
postgresql_pgbackrest_repo_path: "/backups/postgres"

# S3-compatible storage
postgresql_pgbackrest_repo_type: "s3"
postgresql_pgbackrest_repo_s3_bucket: "company-postgres-backups"
postgresql_pgbackrest_repo_s3_region: "us-east-1"
postgresql_pgbackrest_repo_s3_key: "{{ vault_s3_access_key }}"
postgresql_pgbackrest_repo_s3_key_secret: "{{ vault_s3_secret_key }}"
```

### 7.3 Recovery Procedures

- **Point-in-time recovery**: Restore to any point within retention window
- **Selective recovery**: Restore specific databases or tables
- **Recovery testing**: Automated monthly restore verification (see implementation below)
- **Recovery metrics**: Track RTO achievement

### 7.4 Automated Backup Verification Implementation

**Monthly Restore Testing Process**:

```yaml
postgresql_backup_verification_enabled: true
postgresql_backup_verification_schedule: "0 3 1 * *"  # First day of month, 3 AM
postgresql_backup_verification_target_dir: "/tmp/postgres_restore_test"
postgresql_backup_verification_retention_days: 7
```

**Verification Workflow**:
1. **Backup Selection**: Automatically select the most recent full backup
2. **Restore Execution**: Restore to isolated test directory using pgBackRest
3. **Validation Checks**:
   - PostgreSQL starts successfully with restored data
   - All expected databases and tables present
   - Row counts match expected ranges (configurable thresholds)
   - Key application tables can be queried successfully
4. **Cleanup**: Remove test restoration after validation
5. **Reporting**: Log results and send notifications on failure

**Validation Queries**:
```yaml
postgresql_backup_verification_queries:
  - database: "myapp"
    query: "SELECT count(*) FROM users"
    min_rows: 1000
    max_rows: 1000000
  - database: "myapp"
    query: "SELECT 1 FROM pg_tables WHERE tablename = 'critical_table'"
    expected_rows: 1
```

**Failure Handling**: Failed restore tests trigger immediate alerts and are logged with detailed error information for investigation.

## 8. Monitoring Hooks

### 8.1 Metrics Exporters

```yaml
# PostgreSQL Exporter for Prometheus
postgresql_exporter_enabled: true
postgresql_exporter_port: 9187
postgresql_exporter_queries:
  - pg_stat_database
  # pg_stat_replication will be added in v1.2 with streaming replication support
  - pg_stat_activity
  - pg_stat_statements
  - pg_locks

# pgBouncer Exporter
postgresql_pgbouncer_exporter_enabled: true
postgresql_pgbouncer_exporter_port: 9127
```

### 8.2 Log Integration

```yaml
# JSON structured logging (default)
postgresql_log_destination: "jsonlog"
postgresql_logging_collector: true
postgresql_log_directory: "/var/log/postgresql"
postgresql_log_filename: "postgresql-%Y-%m-%d_%H%M%S.json"
postgresql_log_rotation_age: "1d"
postgresql_log_rotation_size: "1GB"
postgresql_log_min_duration_statement: 1000  # Log slow queries > 1s
postgresql_log_checkpoints: true
postgresql_log_connections: true
postgresql_log_disconnections: true
postgresql_log_lock_waits: true
postgresql_log_temp_files: 0

# JSON logging benefits:
# - Native PostgreSQL 18 feature for structured logging
# - Better integration with log aggregation systems (ELK, Splunk, etc.)
# - Consistent schema and timestamp formats
# - Enhanced monitoring and alerting capabilities
# - Easier parsing and analysis with standard JSON tools

# Example JSON log entry:
# {
#   "timestamp": "2024-01-15 14:30:15.123 UTC",
#   "user": "myapp_user",
#   "database": "myapp",
#   "process_id": 12345,
#   "connection_from": "192.168.1.100:54321",
#   "session_id": "65a5f2e7.3039",
#   "command_tag": "SELECT",
#   "error_severity": "LOG",
#   "message": "statement: SELECT * FROM users WHERE id = $1",
#   "query": "SELECT * FROM users WHERE id = $1",
#   "application_name": "myapp"
# }

# Syslog integration (optional)
postgresql_syslog_facility: "LOCAL0"
postgresql_syslog_ident: "postgres"
postgresql_syslog_sequence_numbers: true
postgresql_syslog_split_messages: true
```

### 8.3 Health Checks

```yaml
postgresql_health_checks:
  - name: "connection_check"
    query: "SELECT 1"
    interval: "30s"
  # Note: Replication lag monitoring will be added in v1.2 with streaming replication support
  - name: "disk_space"
    command: "df -h /var/lib/postgresql"
    threshold: "90%"
    interval: "5m"
  - name: "long_running_queries"
    query: "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle' AND query_start < now() - interval '1 hour'"
    threshold: 5
    interval: "5m"
```

## 9. Testing Strategy

### 9.1 Unit Tests (Molecule)

```yaml
# molecule/default/molecule.yml
driver:
  name: docker
platforms:
  - name: ubuntu2404
    image: ubuntu:24.04
    privileged: true
    command: /sbin/init
scenarios:
  - name: default
    test_sequence:
      - dependency
      - syntax
      - create
      - prepare
      - converge
      - idempotence
      - verify
      - destroy
```

### 9.2 Integration Tests

- **Installation verification**: Package versions, file permissions
- **Configuration validation**: postgresql.conf syntax and values
- **Service health**: All services running and responding
- **Authentication tests**: User login and permission verification
- **Backup tests**: Backup creation and restore verification
- **Performance baseline**: pgbench with standard workload
- **Security compliance**: CIS PostgreSQL Benchmark checks

### 9.3 Acceptance Criteria

- Clean installation on Ubuntu 24.04
- Idempotent execution (no changes on second run)
- Graceful handling of configuration changes
- Successful backup and restore cycle
- Connection pooling via pgBouncer working
- Monitoring endpoints accessible
- All security controls in place

## 10. Migration and Upgrade Paths

### 10.1 Version Upgrades

```yaml
# Minor version upgrades (e.g., 18.1 -> 18.2)
postgresql_upgrade_strategy: "rolling"  # or "immediate"
postgresql_upgrade_check_compatibility: true
postgresql_upgrade_backup_before: true

# Major version upgrades (e.g., 16 -> 18)
postgresql_major_upgrade_method: "pg_upgrade"  # or "pg_dump"
postgresql_upgrade_link_mode: true  # Use hard links for speed
postgresql_upgrade_jobs: 4  # Parallel jobs for pg_upgrade
postgresql_upgrade_check_mode: true  # Run compatibility check first

# PostgreSQL 18 specific improvements:
# - Enhanced pg_upgrade performance and reliability
# - Better parallel processing during upgrades
# - Improved compatibility checking
# - Enhanced logging during upgrade process (JSON format)
```

### 10.2 Migration from Existing PostgreSQL

- **Dump and restore**: For small databases (<100GB)
- **Streaming replication**: For minimal downtime migration
- **Logical replication**: For gradual migration with testing
- **pg_upgrade**: For in-place upgrades on same host

### 10.3 Rollback Procedures

- **Configuration rollback**: Previous configs backed up before changes
- **Binary rollback**: Old PostgreSQL binaries retained for N days
- **Data rollback**: Point-in-time recovery to pre-upgrade state
- **Automated rollback**: On failed health checks post-upgrade

## 11. Operational Procedures

### 11.1 Day-0 Operations

- Initial provisioning
- Security hardening
- Baseline performance tuning
- Backup configuration
- Monitoring setup

### 11.2 Day-1 Operations

- Database and user creation
- Application configuration
- Performance validation
- Backup verification
- Security audit

### 11.3 Day-2 Operations

- Performance tuning based on workload
- Capacity planning
- Maintenance scheduling
- Incident response procedures
- Disaster recovery drills

## 12. Dependencies

### 12.1 System Requirements

- Ubuntu 24.04 LTS
- Minimum 2 CPU cores
- Minimum 4GB RAM (8GB+ recommended)
- Minimum 20GB disk space (plus data requirements)
- systemd 247+
- Python 3.10+ (for Ansible modules)

### 12.2 Ansible Requirements

```yaml
# collections/requirements.yml
collections:
  - name: community.postgresql
    version: ">=4.1.0"
  - name: ansible.posix
    version: ">=2.1.0"
  - name: community.general
    version: ">=8.0.0"
```

### 12.3 External Dependencies

- PGDG APT repository
- pgBackRest repository
- Optional: Prometheus/Grafana for monitoring
- Optional: S3-compatible storage for backups

## 13. Configuration Examples

### 13.1 Minimal Configuration

```yaml
# host_vars/myserver.yml
postgresql_databases:
  - name: myapp
    owner: myapp_user

postgresql_users:
  - name: myapp_user
    password: "{{ vault_myapp_password }}"
    db: myapp
    priv: "ALL"
```

### 13.2 Production Configuration

```yaml
# group_vars/production.yml
postgresql_version: "18"
postgresql_listen_addresses: "*"  # Consider restricting if using mandatory pgBouncer
postgresql_max_connections: 500
postgresql_shared_buffers: "8GB"
postgresql_effective_cache_size: "24GB"

# JSON structured logging for production observability
postgresql_log_destination: "jsonlog"
postgresql_log_filename: "postgresql-%Y-%m-%d_%H%M%S.json"

postgresql_ssl: true
postgresql_ssl_cert_file: "/etc/postgresql/server.crt"
postgresql_ssl_key_file: "/etc/postgresql/server.key"
postgresql_ssl_ca_file: "/etc/postgresql/ca.crt"

postgresql_pgbouncer_enabled: true
postgresql_pgbouncer_pool_mode: "transaction"
postgresql_pgbouncer_max_client_conn: 2000
postgresql_pgbouncer_default_pool_size: 50
# Set to true to force all external connections through pgBouncer
postgresql_pgbouncer_mandatory: false

postgresql_pgbackrest_enabled: true
postgresql_pgbackrest_repo_type: "s3"
postgresql_pgbackrest_repo_s3_bucket: "prod-postgres-backups"
postgresql_pgbackrest_retention_full: 4
postgresql_pgbackrest_retention_diff: 7

postgresql_monitoring_enabled: true
postgresql_exporter_enabled: true
postgresql_pgbouncer_exporter_enabled: true
```

## 14. Disaster Recovery Procedures

### 14.1 Failure Scenarios

1. **Disk failure**: Restore from backup to new disk
2. **Corruption**: Point-in-time recovery before corruption
3. **Accidental deletion**: Restore specific objects from backup
4. **Performance degradation**: Failover to standby (if configured)
5. **Security breach**: Restore to known-good state, rotate credentials

### 14.2 Recovery Workflows

```bash
# Full restore to new system
pgbackrest --stanza=main --type=time --target="2024-01-15 14:30:00" restore

# Restore specific database
pgbackrest --stanza=main --db-include=myapp restore

# Verify backup integrity
pgbackrest --stanza=main verify
```

## 15. Compliance and Auditing

### 15.1 Compliance Standards

- PCI DSS (encryption at rest and in transit)
- SOC 2 (security controls, availability)

### 15.2 Audit Requirements

- All superuser actions logged
- DDL statements tracked
- Failed authentication attempts recorded
- Data access patterns monitored
- Regular compliance reports generated

## 16. Future Enhancements

### 16.1 Planned Features

- Patroni integration for HA clustering
- Automated performance tuning based on workload analysis
- Machine learning-based anomaly detection
- Kubernetes operator support
- Multi-region replication setup
- Automated security scanning

### 16.2 Version Roadmap

- v1.0: Core PostgreSQL 18 with JSON logging, pgBouncer and pgBackRest
- v1.1: Monitoring and alerting integration with JSON log parsing
- v1.2: Streaming replication support
- v1.3: Patroni HA clustering

## Appendix A: Security Checklist

- [ ] PostgreSQL listening only on required interfaces
- [ ] SSL/TLS configured for all remote connections
- [ ] Strong passwords enforced (min 16 characters)
- [ ] SCRAM-SHA-256 authentication enabled
- [ ] Superuser access restricted
- [ ] Application users have minimal required privileges
- [ ] Row-level security configured where appropriate
- [ ] Audit logging enabled via pgAudit
- [ ] Backups encrypted at rest
- [ ] Network traffic encrypted in transit
- [ ] Firewall rules configured and tested
- [ ] AppArmor/SELinux profile active
- [ ] Resource limits configured via cgroups
- [ ] Regular security updates applied
- [ ] Monitoring and alerting operational

## Appendix B: Performance Tuning Matrix

**IMPORTANT**: These are starting point recommendations only. Production tuning requires workload-specific analysis and performance testing.

| Workload Type | shared_buffers | work_mem | maintenance_work_mem | effective_cache_size |
|--------------|----------------|----------|---------------------|---------------------|
| OLTP Small   | 25% RAM        | 4MB      | 64MB                | 75% RAM             |
| OLTP Large   | 25% RAM        | 8MB      | 256MB               | 75% RAM             |
| OLAP         | 40% RAM        | 64MB     | 2GB                 | 80% RAM             |
| Mixed        | 30% RAM        | 16MB     | 512MB               | 75% RAM             |
| Web App      | 25% RAM        | 4MB      | 128MB               | 75% RAM             |

**Tuning Considerations**:
- **shared_buffers**: Never exceed 40% of RAM or 32GB, whichever is smaller
- **work_mem**: Consider max_connections × work_mem should not exceed available RAM
- **Storage Impact**: SSD vs HDD storage significantly affects optimal settings
- **Connection Patterns**: High-concurrency applications may need lower work_mem
- **Query Complexity**: Analytics workloads may benefit from higher work_mem
- **Monitoring Required**: Use pg_stat_statements to identify actual query patterns

**Validation Process**:
1. Start with matrix recommendations
2. Monitor query performance with pg_stat_statements
3. Adjust based on actual workload characteristics
4. Load test configuration changes before production deployment

## Appendix C: Troubleshooting Guide

### Common Issues and Solutions

1. **Connection refused**
   - Check PostgreSQL is running: `systemctl status postgresql`
   - Verify listen_addresses in postgresql.conf
   - Check pg_hba.conf for authentication rules
   - Verify firewall rules

2. **Performance degradation**
   - Check slow query log (JSON format in PostgreSQL 18)
   - Parse JSON logs for query performance patterns: `jq '.message | select(contains("duration"))' /var/log/postgresql/*.json`
   - Run VACUUM ANALYZE
   - Review pg_stat_statements
   - Check for lock contention
   - Verify autovacuum is running

3. **Backup failures**
   - Check pgBackRest logs
   - Verify backup destination has space
   - Check network connectivity (for remote backups)
   - Verify pgBackRest configuration

4. **High memory usage**
   - Review shared_buffers setting
   - Check for connection leaks
   - Verify work_mem isn't too high
   - Review query plans for large sorts/hashes

# Note: Replication lag troubleshooting will be added in v1.2 with streaming replication support
