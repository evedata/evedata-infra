# PostgreSQL Ansible Role Implementation Plan

This plan provides a step-by-step technical implementation guide for creating a production-grade PostgreSQL 18 Ansible role based on the requirements in SPEC.md and tuning parameters in INITIAL_TUNING.md.

## 1. Ansible Role Structure

### 1.1 Complete Directory Layout

```
infra/ansible/roles/postgres/
├── defaults/
│   └── main.yml                    # Default variables (lowest priority)
├── vars/
│   └── main.yml                    # Role-specific variables (high priority)
├── handlers/
│   └── main.yml                    # Service handlers and restart logic
├── tasks/
│   ├── main.yml                    # Main task orchestration
│   ├── validate.yml                # Pre-flight validation
│   ├── install.yml                 # Package installation
│   ├── user.yml                    # User and group management
│   ├── directories.yml             # Directory structure creation
│   ├── postgresql.yml              # PostgreSQL configuration
│   ├── pgbouncer.yml               # pgBouncer setup
│   ├── pgbackrest.yml              # pgBackRest configuration
│   ├── security.yml                # Security hardening
│   ├── ssl.yml                     # SSL/TLS certificate management
│   ├── firewall.yml                # Firewall configuration
│   ├── monitoring.yml              # Prometheus exporters
│   ├── systemd.yml                 # systemd service configuration
│   ├── kernel.yml                  # Kernel parameter tuning
│   ├── database.yml                # Database and user creation
│   └── backup-schedule.yml         # Backup scheduling
├── templates/
│   ├── postgresql.conf.j2          # Main PostgreSQL configuration
│   ├── pg_hba.conf.j2              # Authentication configuration
│   ├── pg_ident.conf.j2            # User mapping configuration
│   ├── pgbouncer.ini.j2            # pgBouncer configuration
│   ├── pgbouncer-userlist.txt.j2   # pgBouncer authentication
│   ├── pgbackrest.conf.j2          # pgBackRest configuration
│   ├── postgres.service.j2         # systemd service override
│   ├── postgresql.slice.j2         # systemd slice configuration
│   ├── postgres.apparmor.j2        # AppArmor profile
│   ├── postgres-ssl.conf.j2        # SSL certificate configuration
│   ├── 99-postgres-sysctl.conf.j2  # Kernel parameters
│   ├── pgpass.j2                   # Connection credentials
│   ├── backup-full.timer.j2        # systemd timer for full backups
│   ├── backup-diff.timer.j2        # systemd timer for diff backups
│   └── ufw-postgres.rules.j2       # UFW firewall rules
├── files/
│   ├── postgres-exporter.service   # Static systemd service files
│   ├── pgbouncer-exporter.service
│   ├── postgres-healthcheck.sh     # Health check scripts
│   └── postgres-logrotate          # Log rotation configuration
├── meta/
│   └── main.yml                    # Role metadata and dependencies
├── molecule/
│   ├── default/                    # Default test scenario
│   │   ├── molecule.yml
│   │   ├── converge.yml
│   │   ├── verify.yml
│   │   └── prepare.yml
│   ├── multi-node/                 # Multi-node testing scenario
│   └── upgrade/                    # Upgrade testing scenario
└── README.md                       # Usage documentation
```

### 1.2 File Implementation Order

Implementation should follow this sequence to ensure dependencies are handled correctly:

1. **defaults/main.yml** - Define all default variables
2. **meta/main.yml** - Set up role dependencies
3. **tasks/validate.yml** - System validation
4. **tasks/user.yml** - User management
5. **tasks/directories.yml** - Directory structure
6. **tasks/install.yml** - Package installation
7. **tasks/kernel.yml** - Kernel tuning
8. **tasks/systemd.yml** - Resource limits
9. **tasks/postgresql.yml** - PostgreSQL configuration
10. **tasks/ssl.yml** - SSL setup
11. **tasks/pgbouncer.yml** - Connection pooling
12. **tasks/pgbackrest.yml** - Backup configuration
13. **tasks/security.yml** - Security hardening
14. **tasks/firewall.yml** - Network security
15. **tasks/monitoring.yml** - Monitoring setup
16. **tasks/database.yml** - Database objects
17. **tasks/backup-schedule.yml** - Backup automation
18. **handlers/main.yml** - Service management

## 2. Task Organization and Implementation

### 2.1 Main Task File (tasks/main.yml)

```yaml
---
# Main task orchestration for PostgreSQL role
- name: "Include validation tasks"
  ansible.builtin.include_tasks: validate.yml
  tags: ['postgres', 'validate']

- name: "Include user management tasks"
  ansible.builtin.include_tasks: user.yml
  tags: ['postgres', 'users']

- name: "Include directory creation tasks"
  ansible.builtin.include_tasks: directories.yml
  tags: ['postgres', 'directories']

- name: "Include installation tasks"
  ansible.builtin.include_tasks: install.yml
  tags: ['postgres', 'install']

- name: "Include kernel tuning tasks"
  ansible.builtin.include_tasks: kernel.yml
  tags: ['postgres', 'kernel']
  when: postgres_kernel_tuning_enabled

- name: "Include systemd configuration tasks"
  ansible.builtin.include_tasks: systemd.yml
  tags: ['postgres', 'systemd']

- name: "Include PostgreSQL configuration tasks"
  ansible.builtin.include_tasks: postgresql.yml
  tags: ['postgres', 'config']

- name: "Include SSL configuration tasks"
  ansible.builtin.include_tasks: ssl.yml
  tags: ['postgres', 'ssl']
  when: postgres_ssl

- name: "Include pgBouncer tasks"
  ansible.builtin.include_tasks: pgbouncer.yml
  tags: ['postgres', 'pgbouncer']
  when: pgbouncer_enabled

- name: "Include pgBackRest tasks"
  ansible.builtin.include_tasks: pgbackrest.yml
  tags: ['postgres', 'backup']
  when: pgbackrest_enabled

- name: "Include security hardening tasks"
  ansible.builtin.include_tasks: security.yml
  tags: ['postgres', 'security']

- name: "Include firewall tasks"
  ansible.builtin.include_tasks: firewall.yml
  tags: ['postgres', 'firewall']
  when: postgres_firewall_enabled

- name: "Include monitoring tasks"
  ansible.builtin.include_tasks: monitoring.yml
  tags: ['postgres', 'monitoring']
  when: postgres_monitoring_enabled

- name: "Include database creation tasks"
  ansible.builtin.include_tasks: database.yml
  tags: ['postgres', 'database']

- name: "Include backup scheduling tasks"
  ansible.builtin.include_tasks: backup-schedule.yml
  tags: ['postgres', 'backup-schedule']
  when: pgbackrest_enabled

- name: "Ensure PostgreSQL is started and enabled"
  ansible.builtin.systemd_service:
    name: "postgresql@{{ postgres_version }}-{{ postgres_cluster_name }}"
    state: started
    enabled: true
  tags: ['postgres', 'service']
```

### 2.2 Validation Tasks (tasks/validate.yml)

```yaml
---
# Pre-flight validation tasks
- name: "Check minimum system requirements"
  ansible.builtin.assert:
    that:
      - ansible_memtotal_mb >= 4096
      - ansible_processor_vcpus >= 2
      - ansible_distribution == "Ubuntu"
      - ansible_distribution_version == "24.04"
    fail_msg: "System does not meet minimum requirements for PostgreSQL 18 on Ubuntu 24.04"
  tags: ['validation']

- name: "Calculate memory allocation"
  ansible.builtin.set_fact:
    postgres_calculated_shared_buffers: "{{ (ansible_memtotal_mb * 0.25) | int }}MB"
    postgres_calculated_effective_cache_size: "{{ (ansible_memtotal_mb * 0.75) | int }}MB"
    postgres_calculated_maintenance_work_mem: "{{ (ansible_memtotal_mb * 0.03125) | int }}MB"
  when: postgres_auto_tune_memory
  tags: ['validation']

- name: "Check disk space for data directory"
  ansible.builtin.shell: |
    df --output=avail {{ postgres_data_directory | dirname }} | tail -1
  register: postgres_disk_space
  changed_when: false
  tags: ['validation']

- name: "Ensure sufficient disk space"
  ansible.builtin.assert:
    that:
      - postgres_disk_space.stdout | int > 10485760  # 10GB in KB
    fail_msg: "Insufficient disk space for PostgreSQL data directory"
  tags: ['validation']

- name: "Check for conflicting PostgreSQL installations"
  ansible.builtin.shell: |
    dpkg -l | grep postgresql || true
  register: postgres_existing_packages
  changed_when: false
  tags: ['validation']

- name: "Warn about existing PostgreSQL packages"
  ansible.builtin.debug:
    msg: "Warning: Existing PostgreSQL packages detected: {{ postgres_existing_packages.stdout_lines }}"
  when: postgres_existing_packages.stdout != ""
  tags: ['validation']
```

### 2.3 Installation Tasks (tasks/install.yml)

```yaml
---
# Package installation tasks
- name: "Install required system packages"
  ansible.builtin.apt:
    name:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
      - software-properties-common
      - python3-psycopg2
    state: present
    update_cache: true
  tags: ['install']

- name: "Add PGDG repository key"
  ansible.builtin.apt_key:
    url: "{{ postgres_pgdg_repo_key_url }}"
    state: present
  tags: ['install']

- name: "Add PGDG repository"
  ansible.builtin.apt_repository:
    repo: "{{ postgres_pgdg_repo }}"
    state: present
    update_cache: true
  tags: ['install']

- name: "Install PostgreSQL packages"
  ansible.builtin.apt:
    name:
      - "postgresql-{{ postgres_version }}"
      - "postgresql-client-{{ postgres_version }}"
      - "postgresql-contrib-{{ postgres_version }}"
      - postgresql-common
    state: present
  tags: ['install']
  notify:
    - restart postgresql

- name: "Install pgBouncer"
  ansible.builtin.apt:
    name: pgbouncer
    state: present
  when: pgbouncer_enabled
  tags: ['install']

- name: "Install pgBackRest"
  ansible.builtin.apt:
    name: pgbackrest
    state: present
  when: pgbackrest_enabled
  tags: ['install']

- name: "Install monitoring packages"
  ansible.builtin.apt:
    name:
      - prometheus-postgres-exporter
      - prometheus-pgbouncer-exporter
    state: present
  when: postgres_monitoring_enabled
  tags: ['install', 'monitoring']

- name: "Install security packages"
  ansible.builtin.apt:
    name:
      - apparmor-utils
      - ufw
    state: present
  tags: ['install', 'security']
```

### 2.4 PostgreSQL Configuration Tasks (tasks/postgresql.yml)

```yaml
---
# PostgreSQL configuration tasks
- name: "Stop PostgreSQL for configuration"
  ansible.builtin.systemd_service:
    name: "postgresql@{{ postgres_version }}-{{ postgres_cluster_name }}"
    state: stopped
  when: postgres_cluster_needs_init | default(false)
  tags: ['config']

- name: "Initialize PostgreSQL cluster"
  ansible.builtin.shell: |
    sudo -u postgres {{ postgres_bin_path }}/initdb \
      --pgdata="{{ postgres_data_directory }}" \
      --encoding=UTF8 \
      --locale=C.UTF-8 \
      --auth-local=peer \
      --auth-host=scram-sha-256
  when: postgres_cluster_needs_init | default(false)
  tags: ['config']

- name: "Generate PostgreSQL configuration"
  ansible.builtin.template:
    src: postgresql.conf.j2
    dest: "{{ postgres_config_directory }}/postgresql.conf"
    owner: postgres
    group: postgres
    mode: '0640'
    backup: true
  tags: ['config']
  notify:
    - reload postgresql

- name: "Generate pg_hba.conf"
  ansible.builtin.template:
    src: pg_hba.conf.j2
    dest: "{{ postgres_config_directory }}/pg_hba.conf"
    owner: postgres
    group: postgres
    mode: '0640'
    backup: true
  tags: ['config']
  notify:
    - reload postgresql

- name: "Generate pg_ident.conf"
  ansible.builtin.template:
    src: pg_ident.conf.j2
    dest: "{{ postgres_config_directory }}/pg_ident.conf"
    owner: postgres
    group: postgres
    mode: '0640'
    backup: true
  tags: ['config']
  notify:
    - reload postgresql

- name: "Create PostgreSQL extensions"
  community.postgresql.postgresql_ext:
    name: "{{ item }}"
    db: postgres
    login_user: postgres
    login_unix_socket: "{{ postgres_unix_socket_directories }}"
  loop: "{{ postgres_extensions }}"
  tags: ['config', 'extensions']
  become_user: postgres
```

## 3. Variable Management Strategy

### 3.1 Variable Hierarchy Implementation

#### defaults/main.yml (Complete structure)

```yaml
---
# PostgreSQL Role Defaults - Lowest Priority
# Based on INITIAL_TUNING.md recommendations

# === Installation Configuration ===
postgres_version: "18"
postgres_install_from: "pgdg"
postgres_pgdg_repo_key_url: "https://www.postgresql.org/media/keys/ACCC4CF8.asc"
postgres_pgdg_repo: "deb https://apt.postgresql.org/pub/repos/apt {{ ansible_distribution_release }}-pgdg main"

# === Cluster Configuration ===
postgres_cluster_name: "main"
postgres_data_directory: "/var/lib/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}"
postgres_config_directory: "/etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}"
postgres_bin_path: "/usr/lib/postgresql/{{ postgres_version }}/bin"
postgres_pid_file: "/var/run/postgresql/{{ postgres_version }}-{{ postgres_cluster_name }}.pid"
postgres_unix_socket_directories: "/var/run/postgresql"

# === Network Configuration ===
postgres_port: 5432
postgres_listen_addresses: "localhost"
postgres_max_connections: 200
postgres_superuser_reserved_connections: 5

# === Memory Configuration (Auto-calculated if not overridden) ===
postgres_auto_tune_memory: true
postgres_shared_buffers: "{{ postgres_calculated_shared_buffers | default('8GB') }}"
postgres_effective_cache_size: "{{ postgres_calculated_effective_cache_size | default('24GB') }}"
postgres_maintenance_work_mem: "{{ postgres_calculated_maintenance_work_mem | default('1GB') }}"
postgres_work_mem: "256MB"
postgres_hash_mem_multiplier: 2.0
postgres_logical_decoding_work_mem: "256MB"
postgres_huge_pages: "on"
postgres_huge_page_size: "2MB"

# === Storage and I/O Configuration ===
postgres_random_page_cost: 1.1  # NVMe optimized
postgres_effective_io_concurrency: 256  # NVMe optimized
postgres_maintenance_io_concurrency: 256
postgres_max_worker_processes: "{{ ansible_processor_vcpus }}"
postgres_max_parallel_workers: "{{ ansible_processor_vcpus }}"
postgres_max_parallel_workers_per_gather: 8
postgres_max_parallel_maintenance_workers: 8
postgres_parallel_leader_participation: true

# === WAL Configuration ===
postgres_wal_level: "replica"
postgres_wal_buffers: "64MB"
postgres_wal_compression: "lz4"
postgres_wal_init_zero: false
postgres_wal_recycle: true
postgres_wal_sync_method: "fdatasync"
postgres_full_page_writes: true
postgres_archive_mode: true
postgres_archive_command: "pgbackrest --stanza={{ pgbackrest_stanza }} archive-push %p"
postgres_archive_timeout: "5min"
postgres_max_wal_size: "16GB"
postgres_min_wal_size: "2GB"
postgres_wal_keep_size: "4GB"

# === Checkpoint Configuration ===
postgres_checkpoint_completion_target: 0.9
postgres_checkpoint_timeout: "30min"
postgres_checkpoint_warning: "10min"

# === Query Tuning ===
postgres_default_statistics_target: 100
postgres_enable_partitionwise_join: true
postgres_enable_partitionwise_aggregate: true
postgres_jit: true
postgres_jit_above_cost: 100000
postgres_geqo: true
postgres_geqo_threshold: 12
postgres_from_collapse_limit: 8
postgres_join_collapse_limit: 8

# === Autovacuum Configuration ===
postgres_autovacuum: true
postgres_autovacuum_max_workers: 8
postgres_autovacuum_naptime: "30s"
postgres_autovacuum_vacuum_scale_factor: 0.05
postgres_autovacuum_analyze_scale_factor: 0.02
postgres_autovacuum_vacuum_cost_delay: "2ms"
postgres_autovacuum_vacuum_cost_limit: 10000
postgres_autovacuum_freeze_max_age: 200000000
postgres_autovacuum_multixact_freeze_max_age: 400000000
postgres_vacuum_freeze_min_age: 50000000
postgres_vacuum_freeze_table_age: 150000000

# === Background Writer ===
postgres_bgwriter_delay: "200ms"
postgres_bgwriter_lru_maxpages: 1000
postgres_bgwriter_lru_multiplier: 4.0
postgres_bgwriter_flush_after: "512kB"

# === Lock Management ===
postgres_deadlock_timeout: "1s"
postgres_max_locks_per_transaction: 256
postgres_max_pred_locks_per_transaction: 256
postgres_max_pred_locks_per_relation: -2
postgres_max_pred_locks_per_page: 2

# === Logging Configuration ===
# PostgreSQL 18 native JSON structured logging (enhanced observability)
postgres_log_destination: "jsonlog"
postgres_logging_collector: true
postgres_log_directory: "/var/log/postgresql"
postgres_log_filename: "postgresql-%Y-%m-%d_%H%M%S.json"
postgres_log_file_mode: 0640
postgres_log_rotation_age: "1d"
postgres_log_rotation_size: "1GB"
postgres_log_truncate_on_rotation: false
postgres_log_min_messages: "warning"
postgres_log_min_error_statement: "error"
postgres_log_min_duration_statement: 1000
postgres_log_checkpoints: true
postgres_log_connections: true
postgres_log_disconnections: true
postgres_log_duration: false
postgres_log_error_verbosity: "default"
postgres_log_hostname: true
postgres_log_line_prefix: "%m [%p] %q%u@%d "
postgres_log_lock_waits: true
postgres_log_statement: "ddl"
postgres_log_temp_files: 0
postgres_log_timezone: "UTC"
postgres_log_autovacuum_min_duration: 1000

# JSON logging benefits:
# - Native PostgreSQL 18 feature for structured logging
# - Better integration with log aggregation systems (ELK, Splunk, etc.)
# - Consistent schema and timestamp formats
# - Enhanced monitoring and alerting capabilities
# - Easier parsing and analysis with standard JSON tools

# === SSL Configuration ===
postgres_ssl: false  # Default disabled, enable in group_vars
postgres_ssl_cert_file: "/etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}/server.crt"
postgres_ssl_key_file: "/etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}/server.key"
postgres_ssl_ca_file: "/etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}/ca.crt"
postgres_ssl_ciphers: "HIGH:MEDIUM:+3DES:!aNULL"
postgres_ssl_prefer_server_ciphers: true
postgres_ssl_ecdh_curve: "prime256v1"
postgres_ssl_dh_params_size: 2048
postgres_ssl_min_protocol_version: "TLSv1.2"
postgres_ssl_max_protocol_version: "TLSv1.3"

# === Authentication ===
postgres_password_encryption: "scram-sha-256"
postgres_scram_iterations: 4096

# === Extensions ===
postgres_extensions:
  - pg_stat_statements
  - pgcrypto
  - uuid-ossp
  - pg_trgm

# === Feature Toggles ===
postgres_kernel_tuning_enabled: true
postgres_firewall_enabled: true
postgres_monitoring_enabled: true
postgres_apparmor_enabled: true

# === pgBouncer Configuration ===
pgbouncer_enabled: false  # Default disabled
pgbouncer_listen_port: 6432
pgbouncer_listen_addr: "*"
pgbouncer_auth_type: "scram-sha-256"
pgbouncer_auth_file: "/etc/pgbouncer/userlist.txt"
pgbouncer_pool_mode: "transaction"
pgbouncer_max_client_conn: 2000
pgbouncer_default_pool_size: 25
pgbouncer_min_pool_size: 10
pgbouncer_reserve_pool_size: 5
pgbouncer_reserve_pool_timeout: 5
pgbouncer_max_db_connections: 100
pgbouncer_max_user_connections: 50
pgbouncer_server_reset_query: "DISCARD ALL"
pgbouncer_server_reset_query_always: false
pgbouncer_server_check_query: "SELECT 1"
pgbouncer_server_check_delay: 30
pgbouncer_server_lifetime: 3600
pgbouncer_server_idle_timeout: 600
pgbouncer_server_connect_timeout: 15
pgbouncer_server_login_retry: 15
pgbouncer_query_timeout: 0
pgbouncer_query_wait_timeout: 120
pgbouncer_client_idle_timeout: 0
pgbouncer_client_login_timeout: 60
pgbouncer_autodb_idle_timeout: 3600
pgbouncer_pkt_buf: 4096
pgbouncer_sbuf_loopcnt: 5
pgbouncer_tcp_defer_accept: true
pgbouncer_tcp_socket_buffer: 0
pgbouncer_tcp_keepalive: true
pgbouncer_tcp_keepcnt: 3
pgbouncer_tcp_keepidle: 600
pgbouncer_tcp_keepintvl: 60
pgbouncer_tcp_user_timeout: 0

# === pgBackRest Configuration ===
pgbackrest_enabled: false  # Default disabled
pgbackrest_stanza: "{{ inventory_hostname_short }}"
pgbackrest_repo_type: "posix"
pgbackrest_repo_path: "/var/lib/postgresql/backups"
pgbackrest_repo_retention_full: 4
pgbackrest_repo_retention_diff: 14
pgbackrest_repo_retention_archive: "7"
pgbackrest_compression_type: "lz4"
pgbackrest_compression_level: 3
pgbackrest_process_max: 8
pgbackrest_archive_async: true
pgbackrest_archive_push_queue_max: "4GiB"
pgbackrest_backup_standby: false
pgbackrest_start_fast: true
pgbackrest_stop_auto: true
pgbackrest_resume: true
pgbackrest_repo_bundle: true
pgbackrest_repo_bundle_size: "64MiB"
pgbackrest_repo_bundle_limit: 32
pgbackrest_io_timeout: 3600
pgbackrest_db_timeout: 3600
pgbackrest_protocol_timeout: 3660
pgbackrest_spool_path: "/var/spool/pgbackrest"
pgbackrest_buffer_size: "4MiB"

# === Backup Schedules ===
pgbackrest_full_backup_schedule: "0 2 * * 0"    # Sunday 2 AM
pgbackrest_diff_backup_schedule: "0 2 * * 1-6"  # Mon-Sat 2 AM
pgbackrest_incr_backup_schedule: "0 */6 * * *"  # Every 6 hours

# === Monitoring Configuration ===
postgres_exporter_enabled: true
postgres_exporter_port: 9187
pgbouncer_exporter_enabled: true
pgbouncer_exporter_port: 9127

# === Kernel Tuning ===
postgres_kernel_params:
  vm.swappiness: 5
  vm.overcommit_memory: 2
  vm.overcommit_ratio: 95
  vm.dirty_background_ratio: 5
  vm.dirty_ratio: 40
  vm.dirty_expire_centisecs: 3000
  vm.dirty_writeback_centisecs: 500
  vm.nr_hugepages: "{{ (postgres_shared_buffers | regex_replace('[^0-9]', '') | int * 1024 / 2048) | int }}"
  vm.hugetlb_shm_group: 115  # postgres group
  net.core.rmem_max: 134217728
  net.core.wmem_max: 134217728
  net.ipv4.tcp_rmem: "4096 87380 134217728"
  net.ipv4.tcp_wmem: "4096 65536 134217728"
  net.core.netdev_max_backlog: 5000
  net.ipv4.tcp_tw_recycle: 0
  net.ipv4.tcp_tw_reuse: 1
  net.ipv4.tcp_max_syn_backlog: 8192
  net.core.somaxconn: 65535
  net.ipv4.tcp_keepalive_time: 600
  net.ipv4.tcp_keepalive_probes: 3
  net.ipv4.tcp_keepalive_intvl: 60
  fs.file-max: 2097152
  fs.aio-max-nr: 1048576
  kernel.shmmax: "{{ (ansible_memtotal_mb * 1024 * 1024 * 0.5) | int }}"
  kernel.shmall: "{{ (ansible_memtotal_mb * 1024 / 4) | int }}"
  kernel.shmmni: 4096
  kernel.sem: "500 2048000 200 40960"

# === systemd Resource Limits ===
postgres_systemd_slice: "postgresql.slice"
postgres_systemd_limits:
  CPUQuota: "50%"
  MemoryMax: "{{ (ansible_memtotal_mb * 1024 * 1024 * 0.5) | int }}"
  MemoryHigh: "{{ (ansible_memtotal_mb * 1024 * 1024 * 0.47) | int }}"
  TasksMax: 8192
  IOWeight: 100

# === systemd Service Hardening ===
postgres_systemd_hardening:
  PrivateTmp: true
  ProtectSystem: strict
  ProtectHome: true
  NoNewPrivileges: true
  RestrictSUIDSGID: true
  RemoveIPC: false
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

# === AppArmor Configuration ===
postgres_apparmor_mode: "enforce"  # or "complain"

# === Firewall Rules ===
postgres_ufw_rules:
  - port: "{{ postgres_port }}"
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "PostgreSQL from private network"
  - port: "{{ pgbouncer_listen_port }}"
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "pgBouncer from private network"
  - port: "{{ postgres_exporter_port }}"
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "PostgreSQL exporter"
  - port: "{{ pgbouncer_exporter_port }}"
    proto: "tcp"
    src: "10.0.0.0/16"
    comment: "pgBouncer exporter"

# === Database and User Management ===
postgres_databases: []
postgres_users: []

# Example structure for databases and users:
# postgres_databases:
#   - name: myapp
#     owner: myapp_user
#     encoding: UTF8
#     locale: en_US.UTF-8
#     template: template0
#
# postgres_users:
#   - name: myapp_user
#     password: "{{ vault_myapp_password }}"
#     encrypted: true
#     role_attr_flags: CREATEDB,NOSUPERUSER
#     db: myapp
#     priv: "ALL"
```

### 3.2 Group Variables Structure

#### group_vars/all.yml (Shared across all environments)

```yaml
---
# PostgreSQL configuration shared across all environments
postgres_version: "18"
postgres_monitoring_enabled: true
postgres_kernel_tuning_enabled: true
postgres_apparmor_enabled: true

# Common extensions
postgres_extensions:
  - pg_stat_statements
  - pgcrypto
  - uuid-ossp
  - pg_trgm

# Common logging configuration
postgres_log_min_duration_statement: 1000
postgres_log_checkpoints: true
postgres_log_connections: true
postgres_log_lock_waits: true

# Security defaults
postgres_password_encryption: "scram-sha-256"
postgres_ssl_min_protocol_version: "TLSv1.2"
```

#### group_vars/hzl.yml (Horizontal services)

```yaml
---
# PostgreSQL configuration for horizontal services
postgres_listen_addresses: "localhost,10.0.0.10"
postgres_max_connections: 100
postgres_shared_buffers: "16GB"
postgres_effective_cache_size: "48GB"
postgres_work_mem: "128MB"

# Smaller resource allocation for shared environment
postgres_systemd_limits:
  CPUQuota: "25%"
  MemoryMax: "32G"
  MemoryHigh: "30G"

pgbouncer_enabled: true
pgbouncer_max_client_conn: 500
pgbouncer_default_pool_size: 15

pgbackrest_enabled: true
pgbackrest_process_max: 4
```

#### group_vars/stg.yml (Staging environment)

```yaml
---
# PostgreSQL configuration for staging
postgres_listen_addresses: "localhost,10.0.0.20"
postgres_max_connections: 150
postgres_shared_buffers: "24GB"
postgres_effective_cache_size: "72GB"
postgres_work_mem: "192MB"

# Medium resource allocation
postgres_systemd_limits:
  CPUQuota: "40%"
  MemoryMax: "48G"
  MemoryHigh: "45G"

pgbouncer_enabled: true
pgbouncer_max_client_conn: 1000
pgbouncer_default_pool_size: 20

pgbackrest_enabled: true
pgbackrest_process_max: 6
pgbackrest_repo_retention_full: 2
pgbackrest_repo_retention_diff: 7
```

#### group_vars/prd.yml (Production environment)

```yaml
---
# PostgreSQL configuration for production
postgres_listen_addresses: "localhost,10.0.0.30"
postgres_max_connections: 200
postgres_shared_buffers: "32GB"
postgres_effective_cache_size: "96GB"
postgres_work_mem: "256MB"

# Full resource allocation based on INITIAL_TUNING.md
postgres_systemd_limits:
  CPUQuota: "50%"
  MemoryMax: "64G"
  MemoryHigh: "60G"

# Enable all production features
postgres_ssl: true
postgres_firewall_enabled: true

pgbouncer_enabled: true
pgbouncer_max_client_conn: 2000
pgbouncer_default_pool_size: 25

pgbackrest_enabled: true
pgbackrest_process_max: 8
pgbackrest_repo_retention_full: 4
pgbackrest_repo_retention_diff: 14

# Production monitoring
postgres_exporter_enabled: true
pgbouncer_exporter_enabled: true
```

### 3.3 Vault Secrets Structure

#### group_vars/vault.yml (Encrypted secrets)

```yaml
---
# Encrypted secrets for PostgreSQL role
# Encrypt using: ansible-vault encrypt group_vars/vault.yml

# PostgreSQL superuser password
postgres_superuser_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66396439663431343963373534386636...

# Application database passwords
vault_evedata_db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          33653634343066383762633831376133...

vault_analytics_db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          64346464326136633233616665383062...

# pgBouncer authentication
vault_pgbouncer_stats_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          61313164326435383739643536373734...

# SSL certificate passwords (if using encrypted keys)
vault_ssl_key_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          35396264343633326533313264396435...

# S3 credentials for remote backups (future use)
vault_s3_access_key: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          39663137373664326464323536373734...

vault_s3_secret_key: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          61343064346438646133663135396435...

# Monitoring credentials
vault_postgres_exporter_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66353834353636333735653337396435...
```

## 4. Template Files Implementation

### 4.1 Main PostgreSQL Configuration (templates/postgresql.conf.j2)

```jinja2
# PostgreSQL configuration file
# Generated by Ansible - Do not edit manually
# Template: postgresql.conf.j2

#------------------------------------------------------------------------------
# FILE LOCATIONS
#------------------------------------------------------------------------------

data_directory = '{{ postgres_data_directory }}'
hba_file = '{{ postgres_config_directory }}/pg_hba.conf'
ident_file = '{{ postgres_config_directory }}/pg_ident.conf'
external_pid_file = '{{ postgres_pid_file }}'

#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------

listen_addresses = '{{ postgres_listen_addresses }}'
port = {{ postgres_port }}
max_connections = {{ postgres_max_connections }}
superuser_reserved_connections = {{ postgres_superuser_reserved_connections }}
unix_socket_directories = '{{ postgres_unix_socket_directories }}'
{% if postgres_ssl %}
ssl = on
ssl_cert_file = '{{ postgres_ssl_cert_file }}'
ssl_key_file = '{{ postgres_ssl_key_file }}'
{% if postgres_ssl_ca_file is defined %}
ssl_ca_file = '{{ postgres_ssl_ca_file }}'
{% endif %}
ssl_ciphers = '{{ postgres_ssl_ciphers }}'
ssl_prefer_server_ciphers = {{ postgres_ssl_prefer_server_ciphers | lower }}
ssl_ecdh_curve = '{{ postgres_ssl_ecdh_curve }}'
ssl_min_protocol_version = '{{ postgres_ssl_min_protocol_version }}'
ssl_max_protocol_version = '{{ postgres_ssl_max_protocol_version }}'
{% endif %}
password_encryption = {{ postgres_password_encryption }}
{% if postgres_password_encryption == 'scram-sha-256' %}
scram_iterations = {{ postgres_scram_iterations }}
{% endif %}

#------------------------------------------------------------------------------
# RESOURCE USAGE (except WAL)
#------------------------------------------------------------------------------

shared_buffers = {{ postgres_shared_buffers }}
{% if postgres_huge_pages != 'off' %}
huge_pages = {{ postgres_huge_pages }}
{% endif %}
effective_cache_size = {{ postgres_effective_cache_size }}
maintenance_work_mem = {{ postgres_maintenance_work_mem }}
work_mem = {{ postgres_work_mem }}
hash_mem_multiplier = {{ postgres_hash_mem_multiplier }}
logical_decoding_work_mem = {{ postgres_logical_decoding_work_mem }}

# Parallelism
max_worker_processes = {{ postgres_max_worker_processes }}
max_parallel_workers = {{ postgres_max_parallel_workers }}
max_parallel_workers_per_gather = {{ postgres_max_parallel_workers_per_gather }}
max_parallel_maintenance_workers = {{ postgres_max_parallel_maintenance_workers }}
parallel_leader_participation = {{ postgres_parallel_leader_participation | lower }}

# Background writer
bgwriter_delay = {{ postgres_bgwriter_delay }}
bgwriter_lru_maxpages = {{ postgres_bgwriter_lru_maxpages }}
bgwriter_lru_multiplier = {{ postgres_bgwriter_lru_multiplier }}
bgwriter_flush_after = {{ postgres_bgwriter_flush_after }}

#------------------------------------------------------------------------------
# WRITE AHEAD LOG
#------------------------------------------------------------------------------

wal_level = {{ postgres_wal_level }}
wal_buffers = {{ postgres_wal_buffers }}
wal_compression = {{ postgres_wal_compression }}
wal_init_zero = {{ postgres_wal_init_zero | lower }}
wal_recycle = {{ postgres_wal_recycle | lower }}
wal_sync_method = {{ postgres_wal_sync_method }}
full_page_writes = {{ postgres_full_page_writes | lower }}

# Archiving
{% if postgres_archive_mode %}
archive_mode = on
archive_command = '{{ postgres_archive_command }}'
archive_timeout = {{ postgres_archive_timeout }}
{% else %}
archive_mode = off
{% endif %}

# WAL file management
max_wal_size = {{ postgres_max_wal_size }}
min_wal_size = {{ postgres_min_wal_size }}
wal_keep_size = {{ postgres_wal_keep_size }}

#------------------------------------------------------------------------------
# REPLICATION
#------------------------------------------------------------------------------

# Currently disabled - will be enabled for HA setup
# max_wal_senders = 3
# wal_sender_timeout = 60s
# synchronous_standby_names = ''

#------------------------------------------------------------------------------
# QUERY TUNING
#------------------------------------------------------------------------------

# Planner configuration
random_page_cost = {{ postgres_random_page_cost }}
effective_io_concurrency = {{ postgres_effective_io_concurrency }}
maintenance_io_concurrency = {{ postgres_maintenance_io_concurrency }}

# Statistics
default_statistics_target = {{ postgres_default_statistics_target }}

# Query optimization
enable_partitionwise_join = {{ postgres_enable_partitionwise_join | lower }}
enable_partitionwise_aggregate = {{ postgres_enable_partitionwise_aggregate | lower }}
jit = {{ postgres_jit | lower }}
{% if postgres_jit %}
jit_above_cost = {{ postgres_jit_above_cost }}
{% endif %}

# Genetic query optimizer
geqo = {{ postgres_geqo | lower }}
{% if postgres_geqo %}
geqo_threshold = {{ postgres_geqo_threshold }}
{% endif %}
from_collapse_limit = {{ postgres_from_collapse_limit }}
join_collapse_limit = {{ postgres_join_collapse_limit }}

#------------------------------------------------------------------------------
# CHECKPOINT
#------------------------------------------------------------------------------

checkpoint_completion_target = {{ postgres_checkpoint_completion_target }}
checkpoint_timeout = {{ postgres_checkpoint_timeout }}
checkpoint_warning = {{ postgres_checkpoint_warning }}

#------------------------------------------------------------------------------
# ERROR REPORTING AND LOGGING
#------------------------------------------------------------------------------

log_destination = '{{ postgres_log_destination }}'
logging_collector = {{ postgres_logging_collector | lower }}
log_directory = '{{ postgres_log_directory }}'
log_filename = '{{ postgres_log_filename }}'
log_file_mode = {{ postgres_log_file_mode }}
log_rotation_age = {{ postgres_log_rotation_age }}
log_rotation_size = {{ postgres_log_rotation_size }}
log_truncate_on_rotation = {{ postgres_log_truncate_on_rotation | lower }}

# What to log
log_min_messages = {{ postgres_log_min_messages }}
log_min_error_statement = {{ postgres_log_min_error_statement }}
log_min_duration_statement = {{ postgres_log_min_duration_statement }}
log_checkpoints = {{ postgres_log_checkpoints | lower }}
log_connections = {{ postgres_log_connections | lower }}
log_disconnections = {{ postgres_log_disconnections | lower }}
log_duration = {{ postgres_log_duration | lower }}
log_error_verbosity = {{ postgres_log_error_verbosity }}
log_hostname = {{ postgres_log_hostname | lower }}
log_line_prefix = '{{ postgres_log_line_prefix }}'
log_lock_waits = {{ postgres_log_lock_waits | lower }}
log_statement = '{{ postgres_log_statement }}'
log_temp_files = {{ postgres_log_temp_files }}
log_timezone = '{{ postgres_log_timezone }}'

# Autovacuum logging
log_autovacuum_min_duration = {{ postgres_log_autovacuum_min_duration }}

#------------------------------------------------------------------------------
# AUTOVACUUM PARAMETERS
#------------------------------------------------------------------------------

autovacuum = {{ postgres_autovacuum | lower }}
{% if postgres_autovacuum %}
autovacuum_max_workers = {{ postgres_autovacuum_max_workers }}
autovacuum_naptime = {{ postgres_autovacuum_naptime }}
autovacuum_vacuum_scale_factor = {{ postgres_autovacuum_vacuum_scale_factor }}
autovacuum_analyze_scale_factor = {{ postgres_autovacuum_analyze_scale_factor }}
autovacuum_vacuum_cost_delay = {{ postgres_autovacuum_vacuum_cost_delay }}
autovacuum_vacuum_cost_limit = {{ postgres_autovacuum_vacuum_cost_limit }}
autovacuum_freeze_max_age = {{ postgres_autovacuum_freeze_max_age }}
autovacuum_multixact_freeze_max_age = {{ postgres_autovacuum_multixact_freeze_max_age }}
vacuum_freeze_min_age = {{ postgres_vacuum_freeze_min_age }}
vacuum_freeze_table_age = {{ postgres_vacuum_freeze_table_age }}
{% endif %}

#------------------------------------------------------------------------------
# LOCK MANAGEMENT
#------------------------------------------------------------------------------

deadlock_timeout = {{ postgres_deadlock_timeout }}
max_locks_per_transaction = {{ postgres_max_locks_per_transaction }}
max_pred_locks_per_transaction = {{ postgres_max_pred_locks_per_transaction }}
max_pred_locks_per_relation = {{ postgres_max_pred_locks_per_relation }}
max_pred_locks_per_page = {{ postgres_max_pred_locks_per_page }}

#------------------------------------------------------------------------------
# VERSION/PLATFORM COMPATIBILITY
#------------------------------------------------------------------------------

# PostgreSQL 18 optimized for Ubuntu 24.04 LTS
# Native compatibility with systemd 247+, Python 3.10+, and modern kernel features

#------------------------------------------------------------------------------
# ERROR HANDLING
#------------------------------------------------------------------------------

# Use defaults for error handling

#------------------------------------------------------------------------------
# CONFIG FILE INCLUDES
#------------------------------------------------------------------------------

# Include files are not used in this configuration

#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

# Extensions
shared_preload_libraries = '{% for ext in postgres_extensions %}{{ ext }}{% if not loop.last %},{% endif %}{% endfor %}'

# Track query statistics
track_activities = {{ postgres_track_activities | default('on') | lower }}
track_counts = {{ postgres_track_counts | default('on') | lower }}
track_io_timing = {{ postgres_track_io_timing | default('on') | lower }}
track_functions = {{ postgres_track_functions | default('none') }}

# pg_stat_statements configuration
{% if 'pg_stat_statements' in postgres_extensions %}
pg_stat_statements.max = 10000
pg_stat_statements.track = all
pg_stat_statements.save = on
{% endif %}
```

### 4.2 pgBouncer Configuration (templates/pgbouncer.ini.j2)

```jinja2
;; pgBouncer configuration
;; Generated by Ansible - Do not edit manually

[databases]
{% for db in postgres_databases %}
{{ db.name }} = host=localhost port={{ postgres_port }} dbname={{ db.name }}
{% endfor %}

[pgbouncer]
listen_port = {{ pgbouncer_listen_port }}
listen_addr = {{ pgbouncer_listen_addr }}
auth_type = {{ pgbouncer_auth_type }}
auth_file = {{ pgbouncer_auth_file }}

pool_mode = {{ pgbouncer_pool_mode }}
max_client_conn = {{ pgbouncer_max_client_conn }}
default_pool_size = {{ pgbouncer_default_pool_size }}
min_pool_size = {{ pgbouncer_min_pool_size }}
reserve_pool_size = {{ pgbouncer_reserve_pool_size }}
reserve_pool_timeout = {{ pgbouncer_reserve_pool_timeout }}
max_db_connections = {{ pgbouncer_max_db_connections }}
max_user_connections = {{ pgbouncer_max_user_connections }}

server_reset_query = {{ pgbouncer_server_reset_query }}
server_reset_query_always = {{ pgbouncer_server_reset_query_always | int }}
server_check_query = select 1
server_check_delay = {{ pgbouncer_server_check_delay }}
server_lifetime = {{ pgbouncer_server_lifetime }}
server_idle_timeout = {{ pgbouncer_server_idle_timeout }}
server_connect_timeout = {{ pgbouncer_server_connect_timeout }}
server_login_retry = {{ pgbouncer_server_login_retry }}

query_timeout = {{ pgbouncer_query_timeout }}
query_wait_timeout = {{ pgbouncer_query_wait_timeout }}
client_idle_timeout = {{ pgbouncer_client_idle_timeout }}
client_login_timeout = {{ pgbouncer_client_login_timeout }}
autodb_idle_timeout = {{ pgbouncer_autodb_idle_timeout }}

pkt_buf = {{ pgbouncer_pkt_buf }}
sbuf_loopcnt = {{ pgbouncer_sbuf_loopcnt }}

tcp_defer_accept = {{ pgbouncer_tcp_defer_accept | int }}
tcp_socket_buffer = {{ pgbouncer_tcp_socket_buffer }}
tcp_keepalive = {{ pgbouncer_tcp_keepalive | int }}
tcp_keepcnt = {{ pgbouncer_tcp_keepcnt }}
tcp_keepidle = {{ pgbouncer_tcp_keepidle }}
tcp_keepintvl = {{ pgbouncer_tcp_keepintvl }}
tcp_user_timeout = {{ pgbouncer_tcp_user_timeout }}

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

admin_users = postgres
stats_users = stats, postgres
```

### 4.3 pgBackRest Configuration (templates/pgbackrest.conf.j2)

```jinja2
# pgBackRest configuration
# Generated by Ansible - Do not edit manually

[global]
repo-type={{ pgbackrest_repo_type }}
repo-path={{ pgbackrest_repo_path }}
repo-retention-full={{ pgbackrest_repo_retention_full }}
repo-retention-diff={{ pgbackrest_repo_retention_diff }}
repo-retention-archive={{ pgbackrest_repo_retention_archive }}

compress-type={{ pgbackrest_compression_type }}
compress-level={{ pgbackrest_compression_level }}
process-max={{ pgbackrest_process_max }}

archive-async={{ pgbackrest_archive_async | lower }}
archive-push-queue-max={{ pgbackrest_archive_push_queue_max }}
backup-standby={{ pgbackrest_backup_standby | lower }}
start-fast={{ pgbackrest_start_fast | lower }}
stop-auto={{ pgbackrest_stop_auto | lower }}
resume={{ pgbackrest_resume | lower }}

{% if pgbackrest_repo_bundle %}
repo-bundle={{ pgbackrest_repo_bundle | lower }}
repo-bundle-size={{ pgbackrest_repo_bundle_size }}
repo-bundle-limit={{ pgbackrest_repo_bundle_limit }}
{% endif %}

io-timeout={{ pgbackrest_io_timeout }}
db-timeout={{ pgbackrest_db_timeout }}
protocol-timeout={{ pgbackrest_protocol_timeout }}
spool-path={{ pgbackrest_spool_path }}
buffer-size={{ pgbackrest_buffer_size }}

[{{ pgbackrest_stanza }}]
pg1-path={{ postgres_data_directory }}
pg1-port={{ postgres_port }}
pg1-socket-path={{ postgres_unix_socket_directories }}

{% if postgres_archive_mode %}
# Archive command for PostgreSQL configuration:
# archive_command = 'pgbackrest --stanza={{ pgbackrest_stanza }} archive-push %p'
{% endif %}
```

### 4.4 systemd Service Override (templates/postgres.service.j2)

```jinja2
[Unit]
Description=PostgreSQL database server
Documentation=man:postgres(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor={{ postgres_data_directory }}

[Service]
Type=notify
User=postgres
ExecStart={{ postgres_bin_path }}/postgres -D {{ postgres_data_directory }}
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=300

# systemd hardening
{% for key, value in postgres_systemd_hardening.items() %}
{{ key }}={{ value }}
{% endfor %}

# Resource limits
{% for key, value in postgres_systemd_limits.items() %}
{{ key }}={{ value }}
{% endfor %}

[Install]
WantedBy=multi-user.target
```

## 5. Handler Implementation

### 5.1 Handlers (handlers/main.yml)

```yaml
---
# PostgreSQL role handlers
- name: restart postgresql
  ansible.builtin.systemd_service:
    name: "postgresql@{{ postgres_version }}-{{ postgres_cluster_name }}"
    state: restarted
  listen: "restart postgresql"

- name: reload postgresql
  ansible.builtin.systemd_service:
    name: "postgresql@{{ postgres_version }}-{{ postgres_cluster_name }}"
    state: reloaded
  listen: "reload postgresql"

- name: restart pgbouncer
  ansible.builtin.systemd_service:
    name: pgbouncer
    state: restarted
  when: pgbouncer_enabled
  listen: "restart pgbouncer"

- name: reload pgbouncer
  ansible.builtin.systemd_service:
    name: pgbouncer
    state: reloaded
  when: pgbouncer_enabled
  listen: "reload pgbouncer"

- name: reload systemd
  ansible.builtin.systemd_service:
    daemon_reload: true
  listen: "reload systemd"

- name: apply sysctl
  ansible.builtin.shell: sysctl -p /etc/sysctl.d/99-postgres.conf
  listen: "apply sysctl"

- name: reload ufw
  community.general.ufw:
    state: reloaded
  when: postgres_firewall_enabled
  listen: "reload ufw"

- name: restart postgres-exporter
  ansible.builtin.systemd_service:
    name: prometheus-postgres-exporter
    state: restarted
  when: postgres_exporter_enabled
  listen: "restart postgres-exporter"

- name: restart pgbouncer-exporter
  ansible.builtin.systemd_service:
    name: prometheus-pgbouncer-exporter
    state: restarted
  when: pgbouncer_exporter_enabled
  listen: "restart pgbouncer-exporter"

- name: reload apparmor
  ansible.builtin.shell: apparmor_parser -r /etc/apparmor.d/usr.lib.postgresql.*
  when: postgres_apparmor_enabled
  listen: "reload apparmor"
```

## 6. Molecule Testing Structure

### 6.1 Molecule Configuration (molecule/default/molecule.yml)

```yaml
---
dependency:
  name: galaxy
  options:
    requirements-file: collections/requirements.yml

driver:
  name: docker

platforms:
  - name: ubuntu2404-postgres
    image: ubuntu:24.04
    privileged: true
    command: /sbin/init
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    capabilities:
      - SYS_ADMIN
    environment:
      DEBIAN_FRONTEND: noninteractive
    groups:
      - postgres_servers

provisioner:
  name: ansible
  inventory:
    group_vars:
      postgres_servers:
        postgres_version: "18"
        postgres_max_connections: 100
        postgres_shared_buffers: "1GB"
        postgres_effective_cache_size: "3GB"
        postgres_ssl: false
        pgbouncer_enabled: true
        pgbackrest_enabled: true
        # JSON logging configuration for PostgreSQL 18
        postgres_log_destination: "jsonlog"
        postgres_log_filename: "postgresql-%Y-%m-%d_%H%M%S.json"
        postgres_databases:
          - name: testdb
            owner: testuser
        postgres_users:
          - name: testuser
            password: testpass123
            db: testdb
            priv: "ALL"

verifier:
  name: ansible

scenario:
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

### 6.2 Molecule Verification (molecule/default/verify.yml)

```yaml
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: "Check PostgreSQL is running"
      ansible.builtin.systemd_service:
        name: "postgresql@18-main"
      register: postgres_service
      failed_when: postgres_service.status.ActiveState != "active"

    - name: "Test PostgreSQL connection"
      community.postgresql.postgresql_ping:
        login_host: localhost
        login_user: postgres
        login_unix_socket: /var/run/postgresql
      register: postgres_ping
      failed_when: postgres_ping.is_available != true

    - name: "Check pgBouncer is running"
      ansible.builtin.systemd_service:
        name: pgbouncer
      register: pgbouncer_service
      failed_when: pgbouncer_service.status.ActiveState != "active"
      when: pgbouncer_enabled

    - name: "Test pgBouncer connection"
      ansible.builtin.shell: |
        echo "SHOW pools;" | psql -h localhost -p 6432 -U postgres pgbouncer
      register: pgbouncer_test
      failed_when: pgbouncer_test.rc != 0
      when: pgbouncer_enabled

    - name: "Check database exists"
      community.postgresql.postgresql_query:
        login_host: localhost
        login_user: postgres
        login_unix_socket: /var/run/postgresql
        query: "SELECT datname FROM pg_database WHERE datname = 'testdb'"
      register: db_check
      failed_when: db_check.rowcount != 1

    - name: "Check user exists"
      community.postgresql.postgresql_query:
        login_host: localhost
        login_user: postgres
        login_unix_socket: /var/run/postgresql
        query: "SELECT usename FROM pg_user WHERE usename = 'testuser'"
      register: user_check
      failed_when: user_check.rowcount != 1

    - name: "Test pgBackRest configuration"
      ansible.builtin.shell: |
        sudo -u postgres pgbackrest --stanza=ubuntu2404-postgres check
      register: pgbackrest_check
      failed_when: pgbackrest_check.rc != 0
      when: pgbackrest_enabled

    - name: "Check monitoring endpoints"
      ansible.builtin.uri:
        url: "http://localhost:9187/metrics"
        method: GET
      register: postgres_exporter_check
      failed_when: postgres_exporter_check.status != 200
      when: postgres_exporter_enabled

    - name: "Validate JSON log format"
      ansible.builtin.shell: |
        ls -la /var/log/postgresql/*.json | head -1
      register: json_log_check
      failed_when: json_log_check.rc != 0

    - name: "Test JSON log parsing"
      ansible.builtin.shell: |
        tail -n 1 /var/log/postgresql/postgresql-*.json | jq '.timestamp'
      register: json_parse_check
      failed_when: json_parse_check.rc != 0
      when: postgres_log_destination == "jsonlog"

    - name: "Check configuration files exist"
      ansible.builtin.stat:
        path: "{{ item }}"
      register: config_files
      failed_when: not config_files.stat.exists
      loop:
        - /etc/postgresql/18/main/postgresql.conf
        - /etc/postgresql/18/main/pg_hba.conf
        - /etc/postgresql/18/main/pg_ident.conf
        - /etc/pgbouncer/pgbouncer.ini
        - /etc/pgbackrest/pgbackrest.conf

    - name: "Check systemd hardening is active"
      ansible.builtin.shell: |
        systemctl show postgresql@18-main --property=PrivateTmp
      register: systemd_hardening
      failed_when: "'PrivateTmp=yes' not in systemd_hardening.stdout"

    - name: "Check resource limits are applied"
      ansible.builtin.shell: |
        systemctl show postgresql@18-main --property=MemoryMax
      register: memory_limits
      failed_when: "'MemoryMax=' not in memory_limits.stdout"
```

## 7. Security Implementation Details

### 7.1 AppArmor Profile (templates/postgres.apparmor.j2)

```jinja2
# AppArmor profile for PostgreSQL
# Generated by Ansible - Do not edit manually

#include <tunables/global>

/usr/lib/postgresql/{{ postgres_version }}/bin/postgres {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/user-tmp>

  capability dac_read_search,
  capability setgid,
  capability setuid,
  capability sys_nice,
  capability sys_resource,

  # PostgreSQL binary
  /usr/lib/postgresql/{{ postgres_version }}/bin/postgres mr,

  # Configuration files
  /etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}/ r,
  /etc/postgresql/{{ postgres_version }}/{{ postgres_cluster_name }}/* r,

  # Data directory
  {{ postgres_data_directory }}/ rw,
  {{ postgres_data_directory }}/** rwk,

  # Log directory
  {{ postgres_log_directory }}/ rw,
  {{ postgres_log_directory }}/** rw,

  # Socket directory
  {{ postgres_unix_socket_directories }}/ rw,
  {{ postgres_unix_socket_directories }}/.s.PGSQL.* rw,

  # System libraries
  /lib/x86_64-linux-gnu/** mr,
  /usr/lib/x86_64-linux-gnu/** mr,

  # Proc filesystem
  @{PROC}/sys/kernel/shmmax r,
  @{PROC}/meminfo r,
  @{PROC}/stat r,
  @{PROC}/version r,
  @{PROC}/sys/vm/overcommit_memory r,

  # Backup access (for pgBackRest)
  {{ pgbackrest_repo1_path }}/ rw,
  {{ pgbackrest_repo1_path }}/** rw,

  # Deny dangerous operations
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,
  deny /home/** rw,
  deny mount,
  deny ptrace,
  deny @{PROC}/sys/kernel/core_pattern w,
}
```

### 7.2 UFW Rules Template (templates/ufw-postgres.rules.j2)

```jinja2
# UFW rules for PostgreSQL
# Generated by Ansible - Do not edit manually

{% for rule in postgres_ufw_rules %}
# {{ rule.comment }}
ufw allow from {{ rule.src }} to any port {{ rule.port }} proto {{ rule.proto }}
{% endfor %}

# Deny all other PostgreSQL traffic
ufw deny {{ postgres_port }}/tcp
ufw deny {{ pgbouncer_listen_port }}/tcp
```

## 8. Dependency Management

### 8.1 Role Metadata (meta/main.yml)

```yaml
---
galaxy_info:
  role_name: postgres
  author: EVEData Infrastructure Team
  description: Production-grade PostgreSQL with pgBouncer and pgBackRest
  license: MIT
  min_ansible_version: "2.14"
  platforms:
    - name: Ubuntu
      versions:
        - "24.04"
  galaxy_tags:
    - database
    - postgresql
    - backup
    - monitoring
    - security

dependencies: []

collections:
  - community.postgresql
  - ansible.posix
  - community.general
```

### 8.2 Collections Requirements (collections/requirements.yml)

```yaml
---
collections:
  - name: community.postgresql
    version: ">=3.4.0"
    source: https://galaxy.ansible.com
  - name: ansible.posix
    version: ">=1.5.4"
    source: https://galaxy.ansible.com
  - name: community.general
    version: ">=8.6.0"
    source: https://galaxy.ansible.com
```

## 9. Idempotency Implementation Strategy

### 9.1 Configuration Change Detection

```yaml
# Example from tasks/postgresql.yml
- name: "Check if PostgreSQL configuration changed"
  ansible.builtin.template:
    src: postgresql.conf.j2
    dest: "{{ postgres_config_directory }}/postgresql.conf"
    owner: postgres
    group: postgres
    mode: '0640'
    backup: true
  register: postgres_config_changed
  notify:
    - reload postgresql

- name: "Check if restart is required"
  ansible.builtin.set_fact:
    postgres_restart_required: true
  when: postgres_config_changed.changed and (
    postgres_config_changed.diff is defined and (
      'shared_buffers' in postgres_config_changed.diff.after or
      'max_connections' in postgres_config_changed.diff.after or
      'wal_level' in postgres_config_changed.diff.after
    )
  )

- name: "Warn about restart requirement"
  ansible.builtin.debug:
    msg: "PostgreSQL restart required for configuration changes - schedule maintenance window"
  when: postgres_restart_required | default(false)
```

### 9.2 Database Object Idempotency

```yaml
# Example from tasks/database.yml
- name: "Create PostgreSQL databases"
  community.postgresql.postgresql_db:
    name: "{{ item.name }}"
    owner: "{{ item.owner | default(omit) }}"
    encoding: "{{ item.encoding | default('UTF8') }}"
    lc_collate: "{{ item.locale | default('en_US.UTF-8') }}"
    lc_ctype: "{{ item.locale | default('en_US.UTF-8') }}"
    template: "{{ item.template | default('template0') }}"
    state: present
    login_host: localhost
    login_user: postgres
    login_unix_socket: "{{ postgres_unix_socket_directories }}"
  loop: "{{ postgres_databases }}"
  when: postgres_databases is defined and postgres_databases | length > 0

- name: "Create PostgreSQL users"
  community.postgresql.postgresql_user:
    name: "{{ item.name }}"
    password: "{{ item.password | default(omit) }}"
    encrypted: "{{ item.encrypted | default(true) }}"
    role_attr_flags: "{{ item.role_attr_flags | default('NOSUPERUSER,NOCREATEDB') }}"
    db: "{{ item.db | default(omit) }}"
    priv: "{{ item.priv | default(omit) }}"
    state: present
    login_host: localhost
    login_user: postgres
    login_unix_socket: "{{ postgres_unix_socket_directories }}"
  loop: "{{ postgres_users }}"
  when: postgres_users is defined and postgres_users | length > 0
  no_log: true  # Prevent password exposure in logs
```

## 10. Error Handling and Rollback Implementation

### 10.1 Pre-flight Validation

```yaml
# Enhanced validation in tasks/validate.yml
- name: "Validate configuration before applying"
  block:
    - name: "Check PostgreSQL configuration syntax"
      ansible.builtin.shell: |
        {{ postgres_bin_path }}/postgres --config-file={{ postgres_config_directory }}/postgresql.conf --check-config
      register: config_syntax_check
      failed_when: config_syntax_check.rc != 0
      become_user: postgres

    - name: "Validate memory settings"
      ansible.builtin.assert:
        that:
          - (postgres_shared_buffers | regex_replace('[^0-9]', '') | int) <= (ansible_memtotal_mb * 0.4)
        fail_msg: "shared_buffers too large for available memory"

    - name: "Check disk space for backups"
      ansible.builtin.shell: |
        df --output=avail {{ pgbackrest_repo1_path | dirname }} | tail -1
      register: backup_disk_space
      when: pgbackrest_enabled

    - name: "Ensure backup disk space sufficient"
      ansible.builtin.assert:
        that:
          - backup_disk_space.stdout | int > 52428800  # 50GB in KB
        fail_msg: "Insufficient disk space for backups"
      when: pgbackrest_enabled

  rescue:
    - name: "Validation failed - stopping deployment"
      ansible.builtin.fail:
        msg: "Pre-flight validation failed. Please fix errors and retry."
```

### 10.2 Rollback Procedures

```yaml
# Rollback handler in handlers/main.yml
- name: rollback configuration
  block:
    - name: "Restore previous configuration files"
      ansible.builtin.shell: |
        if [ -f {{ postgres_config_directory }}/postgresql.conf.{{ ansible_date_time.epoch }}.bak ]; then
          cp {{ postgres_config_directory }}/postgresql.conf.{{ ansible_date_time.epoch }}.bak {{ postgres_config_directory }}/postgresql.conf
        fi
      when: postgres_config_changed is defined and postgres_config_changed.backup_file is defined

    - name: "Restart PostgreSQL with previous configuration"
      ansible.builtin.systemd_service:
        name: "postgresql@{{ postgres_version }}-{{ postgres_cluster_name }}"
        state: restarted

    - name: "Verify PostgreSQL is working after rollback"
      community.postgresql.postgresql_ping:
        login_host: localhost
        login_user: postgres
        login_unix_socket: "{{ postgres_unix_socket_directories }}"
      register: rollback_test
      retries: 3
      delay: 10

  rescue:
    - name: "Emergency recovery failed"
      ansible.builtin.fail:
        msg: "CRITICAL: PostgreSQL rollback failed. Manual intervention required."
  listen: "rollback configuration"
```

## 11. Implementation Timeline and Testing Strategy

### 11.1 Development Phases

**Phase 1: Core Infrastructure (Week 1)**
- Implement defaults/main.yml with all variables
- Create basic installation and configuration tasks
- Implement systemd service management
- Create molecule testing framework

**Phase 2: Configuration Templates (Week 1-2)**
- Implement postgresql.conf.j2 with full tuning
- Create pg_hba.conf and pg_ident.conf templates
- Add kernel tuning and systemd hardening
- Test idempotency and configuration validation

**Phase 3: Connection Pooling (Week 2)**
- Implement pgBouncer configuration and templates
- Add connection pool monitoring
- Test transaction pooling behavior
- Verify connection limits and failover

**Phase 4: Backup System (Week 2-3)**
- Implement pgBackRest configuration
- Create backup scheduling with systemd timers
- Test backup and restore procedures
- Add backup monitoring and alerting

**Phase 5: Security Hardening (Week 3)**
- Implement SSL/TLS configuration
- Create AppArmor profile
- Add firewall rules and network security
- Test security compliance

**Phase 6: Monitoring Integration (Week 3-4)**
- Implement Prometheus exporters
- Add health check scripts with JSON log parsing
- Create monitoring dashboards
- Test alerting thresholds
- Validate JSON structured logging integration

### 11.3 PostgreSQL 18 Specific Improvements

**Enhanced Features in PostgreSQL 18:**
- Native JSON structured logging for better observability
- Enhanced pg_upgrade performance and reliability
- Better parallel processing during upgrades and operations
- Improved compatibility checking for major version upgrades
- Enhanced logging during upgrade processes (JSON format)
- Improved query performance and optimization capabilities

### 11.2 Testing Strategy

**Unit Testing (Molecule)**
- Test role on clean Ubuntu 24.04 containers
- Verify idempotency (no changes on second run)
- Test error conditions and rollback scenarios
- Validate security hardening implementation

**Integration Testing**
- Test with real workloads using pgbench
- Verify backup and restore procedures
- Test monitoring and alerting
- Performance validation against baselines

**Security Testing**
- CIS PostgreSQL Benchmark compliance
- Penetration testing of exposed services
- SSL/TLS configuration validation
- AppArmor policy effectiveness testing

**Upgrade Testing**
- Test PostgreSQL minor version upgrades
- Verify configuration migration
- Test rollback procedures
- Validate data integrity after upgrades

## 12. Usage Examples and Documentation

### 12.1 Basic Usage

```yaml
# inventory/host_vars/db-server.yml
---
postgres_databases:
  - name: evedata
    owner: evedata_user
  - name: analytics
    owner: analytics_user

postgres_users:
  - name: evedata_user
    password: "{{ vault_evedata_password }}"
    db: evedata
    priv: "ALL"
  - name: analytics_user
    password: "{{ vault_analytics_password }}"
    db: analytics
    priv: "ALL"
    role_attr_flags: "CREATEDB,NOSUPERUSER"

pgbouncer_enabled: true
pgbackrest_enabled: true
postgres_ssl: true
```

### 12.2 Playbook Integration

```yaml
# playbooks/database.yml
---
- name: "Deploy PostgreSQL database servers"
  hosts: postgres_servers
  become: true
  roles:
    - postgres
  tags: ['database']

  post_tasks:
    - name: "Verify PostgreSQL deployment"
      community.postgresql.postgresql_ping:
        login_host: localhost
        login_user: postgres
        login_unix_socket: /var/run/postgresql
      tags: ['verify']

    - name: "Display connection information"
      ansible.builtin.debug:
        msg:
          - "PostgreSQL listening on {{ postgres_listen_addresses }}:{{ postgres_port }}"
          - "pgBouncer available on port {{ pgbouncer_listen_port }}"
          - "Monitoring endpoints: :{{ postgres_exporter_port }}, :{{ pgbouncer_exporter_port }}"
      tags: ['info']
```

This comprehensive implementation plan provides a complete roadmap for developing the PostgreSQL Ansible role. Each section includes specific file structures, code patterns, and implementation details that ensure the role meets all requirements from the SPEC.md and incorporates the optimized tuning parameters from INITIAL_TUNING.md.

The plan emphasizes security, performance, monitoring, and operational excellence while maintaining clear separation of concerns and following Ansible best practices for production environments.