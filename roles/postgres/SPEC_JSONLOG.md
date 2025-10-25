# PostgreSQL Native JSON Logging Specification

## Overview

PostgreSQL 15+ includes native JSON logging support through the `jsonlog` destination. This specification defines a simplified implementation that replaces the current CSV logging approach with PostgreSQL's built-in JSON logging capability - no external tools, extensions, or complex processing pipelines required.

### Native JSON Logging Benefits

**Current State**: PostgreSQL logs use `log_destination = 'csvlog'` requiring custom parsing.

**Target State**: PostgreSQL's native `log_destination = 'jsonlog'` provides:
- Built-in JSON formatting (no external tools required)
- Structured logs ready for direct ingestion by log aggregation systems
- Better field type preservation and searchability
- Standard JSON schema across all PostgreSQL installations
- Simplified configuration and maintenance

## Technical Requirements

### PostgreSQL Version Compatibility
- **Target Version**: PostgreSQL 16 (current deployment standard)
- **Minimum Version**: PostgreSQL 15+ (native jsonlog support)
- **Extensions Required**: None
- **External Tools Required**: None

### Ubuntu 24.04 Compatibility
- **systemd-journald**: Full compatibility with JSON structured logging
- **Log Rotation**: Works with existing logrotate configuration
- **File Permissions**: Maintains existing security model
- **Monitoring**: Compatible with existing postgres_exporter and monitoring stack

## Simple Implementation

### Configuration Changes Needed

The implementation requires minimal changes to the existing logging configuration:

#### 1. Update defaults/main.yml (lines 103-126)

```yaml
# === Logging Configuration ===
postgres_log_destination: "jsonlog"  # Changed from "csvlog"
postgres_logging_collector: true
postgres_log_directory: "/var/log/postgresql"
postgres_log_filename: "postgresql-%Y-%m-%d_%H%M%S.json"  # Changed extension
postgres_log_file_mode: 0640
postgres_log_rotation_age: "1d"
postgres_log_rotation_size: "1GB"
postgres_log_truncate_on_rotation: false

# JSON logging doesn't use log_line_prefix - remove or comment out
# postgres_log_line_prefix: "%m [%p] %q%u@%d "

# Other logging settings remain unchanged
postgres_log_min_messages: "warning"
postgres_log_min_error_statement: "error"
postgres_log_min_duration_statement: 1000
postgres_log_checkpoints: true
postgres_log_connections: true
postgres_log_disconnections: true
postgres_log_duration: false
postgres_log_error_verbosity: "default"
postgres_log_hostname: true
postgres_log_lock_waits: true
postgres_log_statement: "ddl"
postgres_log_temp_files: 0
postgres_log_timezone: "UTC"
postgres_log_autovacuum_min_duration: 1000
```

#### 2. Update postgresql.conf.j2 Template

The template changes are minimal since most logging parameters remain the same:

```jinja2
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

# JSON logging doesn't use log_line_prefix
{% if postgres_log_destination != 'jsonlog' %}
log_line_prefix = '{{ postgres_log_line_prefix }}'
{% endif %}

# Remaining logging configuration unchanged
log_min_messages = {{ postgres_log_min_messages }}
log_min_error_statement = {{ postgres_log_min_error_statement }}
log_min_duration_statement = {{ postgres_log_min_duration_statement }}
log_checkpoints = {{ postgres_log_checkpoints | lower }}
log_connections = {{ postgres_log_connections | lower }}
log_disconnections = {{ postgres_log_disconnections | lower }}
log_duration = {{ postgres_log_duration | lower }}
log_error_verbosity = {{ postgres_log_error_verbosity }}
log_hostname = {{ postgres_log_hostname | lower }}
log_lock_waits = {{ postgres_log_lock_waits | lower }}
log_statement = '{{ postgres_log_statement }}'
log_temp_files = {{ postgres_log_temp_files }}
log_timezone = '{{ postgres_log_timezone }}'
log_autovacuum_min_duration = {{ postgres_log_autovacuum_min_duration }}
```

## JSON Log Schema

PostgreSQL's native JSON logging produces a consistent schema with these fields:

```json
{
  "timestamp": "2024-10-11 21:00:00.000 UTC",
  "pid": 12345,
  "session_id": "6541abc123.30e3",
  "line_num": 1,
  "ps": "idle",
  "session_start": "2024-10-11 20:55:00 UTC",
  "vxid": "4/0",
  "txid": 0,
  "error_severity": "LOG",
  "state_code": "00000",
  "message": "database system is ready to accept connections",
  "detail": null,
  "hint": null,
  "query": null,
  "query_pos": null,
  "location": null,
  "application_name": "",
  "user_name": "",
  "database_name": "",
  "remote_host": "",
  "remote_port": null,
  "command_tag": null,
  "session_line_num": 1,
  "backend_type": "postmaster"
}
```

## Benefits of Native JSON Logging

### 1. Simplicity
- **No External Dependencies**: Built into PostgreSQL 16
- **Zero Configuration Complexity**: Single parameter change
- **No Processing Pipeline**: Direct JSON output
- **Standard Schema**: Consistent across all PostgreSQL installations

### 2. Enhanced Integration
- **Log Aggregation Systems**: Direct ingestion by ELK Stack, Loki, etc.
- **Cloud Logging**: Native compatibility with AWS CloudWatch, GCP Cloud Logging
- **Monitoring Tools**: Better integration with observability platforms
- **Structured Queries**: Complex filtering without regex parsing

### 3. Operational Benefits
- **Debugging**: Structured search capabilities
- **Performance Analysis**: Built-in query duration and timing fields
- **Audit Compliance**: Structured user and database tracking
- **Monitoring**: Improved metrics extraction

## Testing Strategy

### 1. JSON Format Validation

```bash
# Test JSON structure integrity
tail -f /var/log/postgresql/postgresql-*.json | jq '.'

# Verify required fields are present
cat /var/log/postgresql/postgresql-*.json | jq '.timestamp, .pid, .error_severity, .message'

# Test query logging with duration
psql -c "SELECT pg_sleep(2);"
# Check JSON log for duration field
```

### 2. Log Aggregation Testing

```bash
# Test ELK Stack compatibility
curl -X POST 'localhost:9200/postgres-logs/_doc' \
  -H 'Content-Type: application/json' \
  -d @/var/log/postgresql/sample.json

# Test Loki ingestion
promtail --config.file=/etc/promtail/config.yml --dry-run
```

### 3. Performance Validation

```bash
# Compare log file sizes (JSON vs CSV)
du -h /var/log/postgresql/postgresql-*.json
du -h /var/log/postgresql/postgresql-*.csv

# Monitor logging performance impact
SELECT * FROM pg_stat_bgwriter;
```

## Migration Strategy

### Phase 1: Configuration Update
1. Update `defaults/main.yml` with JSON logging settings
2. Modify `postgresql.conf.j2` template
3. Test configuration with `ansible-playbook --check`

### Phase 2: Staged Deployment
1. **Staging Environment**: Deploy and validate JSON logging
2. **Horizontal Services**: Deploy to hzl group
3. **Production**: Deploy to prd group after validation

### Phase 3: Validation
1. Verify JSON log format and content
2. Confirm log aggregation system compatibility
3. Validate monitoring and alerting functionality
4. Clean up old CSV log files

### Rollback Plan

Simple rollback by reverting two variables:
```yaml
postgres_log_destination: "csvlog"
postgres_log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
```

## Compatibility Notes

### PostgreSQL 16 Features
- Full native JSON logging support
- Consistent JSON schema
- Performance optimized JSON output
- Complete field coverage

### Existing Monitoring Integration
- **postgres_exporter**: No changes required
- **Custom Metrics**: Enhanced extraction from structured JSON
- **Alerting**: More precise alert conditions
- **Dashboards**: Improved visualization capabilities

### Log Rotation
- Works with existing logrotate configuration
- JSON files rotate normally with `.json` extension
- No changes to rotation policies required

## Success Criteria

- [ ] JSON logs are properly formatted and parseable with `jq`
- [ ] Log aggregation systems successfully ingest JSON logs
- [ ] No performance degradation in database operations
- [ ] All existing monitoring and alerting functionality preserved
- [ ] Log file sizes remain reasonable
- [ ] Emergency rollback capability verified

## Conclusion

PostgreSQL's native JSON logging provides a simple, robust solution that eliminates the complexity of external log processing tools while delivering superior structured logging capabilities. The implementation requires minimal configuration changes and provides immediate benefits for log analysis, monitoring, and observability.