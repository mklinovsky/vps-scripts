# VPS Scripts - Feature Roadmap

## Overview
Enhancement plan for VPS management toolkit to improve reliability, monitoring, automation, and developer experience.

---

## Phase 1: Foundation & Reliability (High Impact, Low Effort)

### 1.1 Health Check Monitor
**Priority:** HIGH | **Effort:** Small

**Description:** Automated health monitoring for deployed applications

**Implementation:**
- Create `check-health APP_NAME` script that:
  - Pings app's health endpoint (configurable URL)
  - Checks Docker container status
  - Verifies database connectivity
  - Returns exit code 0 (healthy) or 1 (unhealthy)
- Create `monitor-apps` script that:
  - Iterates through all deployed apps
  - Runs health checks
  - Sends email alerts on failure
  - Optionally restarts unhealthy containers
- Store health check config in app `.env` file:
  ```
  HEALTH_CHECK_URL=http://localhost:3000/health
  HEALTH_CHECK_INTERVAL=300
  AUTO_RESTART_ON_FAILURE=true
  ```

**Files to create/modify:**
- `scripts/check-health`
- `scripts/monitor-apps`
- Update `create-app` to add health check config to `.env`
- Add cron job: `*/5 * * * * /home/deploy/bin/monitor-apps`

**Benefits:** Proactive failure detection, reduced downtime

---

### 1.2 Backup Retention & Cleanup
**Priority:** HIGH | **Effort:** Small

**Description:** Automatic cleanup of old backups to prevent storage exhaustion

**Implementation:**
- Add to `backup-db`:
  - Keep last 7 daily backups locally
  - Keep last 30 daily backups on S3
  - Delete older backups automatically
- Create `cleanup-backups` script:
  ```bash
  # Local cleanup (keep 7 days)
  find $BACKUP_DIR -name "*.gz" -mtime +7 -delete
  
  # S3 cleanup (keep 30 days)
  aws s3 ls s3://$S3_BUCKET/backups/$DB_NAME/ --recursive | \
    awk '{print $4}' | \
    while read file; do
      # Parse date from filename and delete if older than 30 days
    done
  ```

**Configuration:**
```bash
BACKUP_RETENTION_DAYS_LOCAL=7
BACKUP_RETENTION_DAYS_S3=30
```

**Benefits:** Prevents disk full issues, reduces S3 costs

---

### 1.3 Log Aggregation & Management
**Priority:** HIGH | **Effort:** Small-Medium

**Implementation:**
- Create `scripts/view-logs`:
  ```bash
  # View logs for specific app
  view-logs APP_NAME [OPTIONS]
  
  # Shows docker compose logs with tail/follow options
  docker compose -p APP_NAME logs [OPTIONS]
  ```
- Create `scripts/rotate-logs`:
  - Rotates logs for all apps
  - Compresses old logs
  - Deletes logs older than X days
- Update `create-app` to configure Docker log rotation in `docker-compose.yml`:
  ```yaml
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
  ```

**Benefits:** Easier debugging, prevents disk overflow from logs

---

### 1.4 Secrets Management
**Priority:** HIGH | **Effort:** Small-Medium

**Implementation:**
- Create `scripts/encrypt-secrets`:
  - Uses `gpg` or `age` to encrypt sensitive env vars
  - Store encrypted file in repo: `.env.encrypted`
- Create `scripts/decrypt-secrets`:
  - Decrypts `.env.encrypted` to `.env` on VPS
  - Requires passphrase (prompt or from environment)
- Workflow:
  ```bash
  # Local: encrypt secrets before commit
  encrypt-secrets .env
  
  # VPS: decrypt after deployment
  decrypt-secrets .env.encrypted
  ```

**Alternative:** Use Vault or similar if multi-server support needed

**Benefits:** Secure storage of secrets, safe to commit to git

---

### 1.5 Deployment Rollback
**Priority:** HIGH | **Effort:** Small

**Implementation:**
- Create `scripts/rollback-app`:
  ```bash
  rollback-app APP_NAME [TAG]
  
  # If no TAG provided, rollback to previous tag
  # Checks out specified tag and redeploys
  ```
- Store deployment history in `$DEPLOY_DIR/.deploy_history`:
  ```
  v1.2.0 2025-02-08 10:30:00
  v1.2.1 2025-02-08 14:45:00
  v1.2.2 2025-02-09 09:15:00
  ```
- Updates `post-receive` hook to log deployments

**Benefits:** Quick recovery from bad deployments

---

## Phase 2: Enhanced Monitoring & Automation (Medium Priority, Medium Effort)

### 2.1 Zero-Downtime Deployments
**Priority:** MEDIUM | **Effort:** Medium

**Implementation:**
- Update `post-receive` hook for blue-green deployment:
  ```bash
  # Instead of immediate switch:
  # 1. Build new containers with different project name (APP_NAME-new)
  # 2. Run health checks on new containers
  # 3. If healthy: stop old containers and rename new to APP_NAME
  # 4. If unhealthy: keep old containers, alert
  ```
- Requires two compose files or labels for container naming
- Add deployment timeout (e.g., 5 minutes)

**Benefits:** Users never experience downtime during deploys

---

### 2.2 Multi-Database Support
**Priority:** MEDIUM | **Effort:** Medium

**Implementation:**
- Refactor `create-db` to `create-postgres-db`
- Add:
  - `create-mysql-db`
  - `create-redis-db`
  - `create-mongodb-db`
- Create unified `create-db` wrapper:
  ```bash
  create-db TYPE NAME [OPTIONS]
  # Example: create-db postgres myapp
  # Example: create-db redis mycache
  ```

**Benefits:** Support for diverse application stacks

---

### 2.3 App Status Dashboard
**Priority:** MEDIUM | **Effort:** Small-Medium

**Implementation:**
- Create `scripts/list-apps`:
  ```
  APP       STATUS   VERSION  URL                    PORT
  myapp     running  v1.2.0   myapp.example.com      3000
  api       stopped  v1.1.5   api.example.com        4000
  frontend  running  v1.0.0   frontend.example.com   5000
  ```

- Shows:
  - App status (running/stopped/healthy/unhealthy)
  - Current deployed version (from git tag)
  - Domain/URL
  - Port
  - Last deployment time
  - Resource usage

**Implementation details:**
- Parse docker ps output
- Read git tags from release directory
- Check Nginx config for domains
- Get health status

**Benefits:** Single command overview of entire VPS

---

### 2.4 SSL Certificate Monitoring
**Priority:** MEDIUM | **Effort:** Small

**Implementation:**
- Create `scripts/check-ssl`:
  - Checks all SSL certs for expiration
  - Alerts if < 30 days to expiration
- Add to `stats-email` or create separate cron job
- Update `init-nginx` to store cert info in app directory

**Benefits:** Prevents SSL expiration surprises

---

### 2.5 Docker Resource Limits
**Priority:** MEDIUM | **Effort:** Small-Medium

**Implementation:**
- Create `templates/docker-compose-with-limits.yml`:
  ```yaml
  services:
    app:
      deploy:
        resources:
          limits:
            cpus: '0.50'
            memory: 512M
          reservations:
            cpus: '0.25'
            memory: 256M
  ```
- Update `create-app` to include resource limits template
- Create `scripts/set-resource-limits APP_NAME` to adjust limits

**Benefits:** Prevents one app from consuming all resources

---

## Phase 3: Advanced Features (Lower Priority, Higher Effort)

### 3.1 Pre-deployment Testing
**Priority:** LOW | **Effort:** Medium-Large

**Implementation:**
- Update `post-receive` hook:
  ```bash
  # Before deployment:
  # 1. Run tests: docker compose run --rm app npm test
  # 2. Build Docker image and test start
  # 3. Only deploy if tests pass
  ```
- Add test result notifications
- Configurable per-app

**Benefits:** Catch errors before production

---

### 3.2 Backup Integrity Verification
**Priority:** LOW | **Effort:** Medium

**Implementation:**
- Create `scripts/verify-backup`:
  - Downloads backup from S3
  - Attempts to restore to temporary database
  - Runs basic queries to verify integrity
  - Cleans up temp database
- Run weekly via cron
- Reports success/failure

**Benefits:** Confidence that backups are actually usable

---

### 3.3 GitHub/GitLab Integration
**Priority:** LOW | **Effort:** Medium-Large

**Implementation:**
- Create webhook receiver:
  - Listens for GitHub push events
  - Auto-deploys when specific conditions met (e.g., tag pushed)
  - Or auto-deploy main branch to staging
- Requires simple HTTP server on VPS or external service

**Benefits:** Streamlined CI/CD workflow

---

### 3.4 App Templates
**Priority:** LOW | **Effort:** Medium

**Implementation:**
- Create app templates:
  - `nextjs-app` - Next.js with PostgreSQL
  - `nodejs-api` - Node.js API with Redis
  - `static-site` - Static site with Nginx
- Each template includes:
  - Pre-configured docker-compose.yml
  - Health check endpoint
  - Environment variable templates
  - README with app-specific commands

**Usage:**
```bash
create-app myapp --template nextjs
```

**Benefits:** Faster setup for common app types

---

### 3.5 Centralized Logging with Loki/Prometheus
**Priority:** LOW | **Effort:** Large

**Implementation:**
- Deploy Loki or similar for log aggregation
- Deploy Prometheus for metrics
- Deploy Grafana for visualization
- Configure all apps to send logs/metrics to central instance
- Create default dashboards

**Benefits:** Centralized observability across all apps

---

## Implementation Order Recommendation

**Phase 1 (MVP):** Features 1.1 -> 1.2 -> 1.3 -> 1.4 -> 1.5
- Focus on reliability and basic monitoring
- Quick wins with high impact

**Phase 2:** Features 2.1 -> 2.4 -> 2.3 -> 2.5 -> 2.2
- Zero-downtime deployments first (ops value)
- Then visibility and monitoring improvements
- Multi-DB support last (depends on actual usage)

**Phase 3:** Features 3.2 -> 3.4 -> 3.1 -> 3.3
- Backup verification (critical data protection)
- Templates (developer experience)
- Webhook integration (only if needed)
- Advanced observability (large effort but valuable)

---

## Configuration Management

All features should be configurable via `.env.remote`:
```bash
# Health checks
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_INTERVAL=300
AUTO_RESTART_ON_FAILURE=true

# Backups
BACKUP_RETENTION_DAYS_LOCAL=7
BACKUP_RETENTION_DAYS_S3=30
VERIFY_BACKUPS_ENABLED=true

# Monitoring
SSL_EXPIRY_ALERT_DAYS=30
RESOURCE_LIMITS_ENABLED=true
```

---

## Documentation Updates Needed

For each feature:
1. Update README.md with usage examples
2. Create feature-specific documentation
3. Update `.env.remote.example` with new variables
4. Add inline comments in scripts
5. Create troubleshooting guide

---

## Testing Strategy

- Test each script in isolation
- Test integration between scripts
- Test on staging VPS before production
- Document test scenarios for each feature

---

## Maintenance Considerations

- Update dependencies (Docker, Docker Compose, AWS CLI)
- Monitor disk usage patterns after implementing cleanup
- Review backup logs weekly
- Test restore process quarterly
- Update secrets encryption keys periodically

This plan provides a solid foundation for evolving the VPS management toolkit while maintaining simplicity and reliability.
