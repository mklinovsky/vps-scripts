# VPS Scripts

Collection of bash scripts for managing applications, databases, backups, and monitoring on VPS.

Sometimes a cheap VPS (like Hetzner) is all you need to host your apps. You don't need any managed platform - just a Linux with Docker. You'll also learn a lot more about how things work along the way.

## Quick Start

### 1. Setup Configuration

Create the configuration file. `install.sh` connects to `VPS_USER@VPS_IP` from it and deploys it to the VPS as the scripts' runtime configuration:
```bash
cp .env.remote.example .env.remote
```

Required variables:
- `PROJECTS_DIR` - Directory for projects (default: `projects`)
- `VPS_USER` - SSH user (I am using `deploy`)
- `VPS_IP` - VPS IP address
- `BACKUP_DBS` - Comma-separated database names to backup
- `S3_BUCKET` - S3 bucket for backups
- `MAILEROO_API_KEY` - Maileroo API key for email notifications
- `EMAIL_FROM` - Email sender
- `EMAIL_TO` - Email recipient for notifications

Only for `init-caddy`:
- `CADDY_DOMAIN` - Parent domain of the app names (e.g. `example.com`)
- `CADDY_CERT`, `CADDY_KEY` - Shared certificate and key for `*.$CADDY_DOMAIN`

### 2. Install Scripts to VPS

```bash
./install.sh
```

This will:
- Build the mailer binary for Linux
- Copy all scripts to `/home/<VPS_USER>/bin/` on VPS
- Set proper permissions
- Copy `.env.remote` as `/home/<VPS_USER>/bin/.env` on the VPS (backing up existing as `/home/<VPS_USER>/bin/.env.bak`)

For another server, create `.env.remote.<target>` the same way and run `./install.sh <target>`.

---

## How Deployment Works

This system uses simple **git-based deployments** with a bare repository and post-receive hook on the VPS.

### The Mechanism

When you run `create-app APP_NAME` on the VPS, it:

1. **Creates a bare git repository** at `/home/<VPS_USER>/<PROJECTS_DIR>/APP_NAME/repo.git`
   - A bare repo has no working directory - it only receives git pushes

2. **Installs a `post-receive` hook** that triggers after every push
   - The hook only responds to **tag pushes** (ignores branch pushes)

### What Happens on Tag Push

When the tag is pushed to the `deploy` remote:

```bash
git push deploy v1.0.0
```

The `post-receive` hook automatically:

1. **Checks out the tagged code** into `/home/<VPS_USER>/<PROJECTS_DIR>/APP_NAME/release/`
2. **Copies the app's `.env` file** into the release directory
3. **Runs `docker compose up -d --build`**
4. Docker Compose rebuilds and restarts the containers with the new code

### Using `git-tag.sh`

The `git-tag.sh` script automates version bumping and deployment:

```bash
# Bump patch version (1.0.0 → 1.0.1) and deploy
./git-tag.sh

# Bump minor version (1.0.1 → 1.1.0) and deploy
./git-tag.sh minor

# Bump major version (1.1.0 → 2.0.0) and deploy
./git-tag.sh major
```

The script:
- Reads the latest git tag
- Increments the version according to [semantic versioning](https://semver.org/)
- Creates an annotated tag
- Pushes the tag to the `deploy` remote (which triggers the deployment)

### Deployment Flow Summary

```
Local Machine                    VPS
─────────────                    ───
./git-tag.sh         ──push──>   repo.git (bare)
    │                                 │
    │                                 ↓
    │                            post-receive hook
    │                                 │
    │                                 ↓
    │                            checkout → release/
    │                                 │
    │                                 ↓
    │                            docker compose up -d --build
    │                                 │
    └──────────────────────────────>  App Running
```

---

## Scripts

### Application Management

#### `create-app`
Creates a new application deployment structure with git-based deployment.

```bash
create-app APP_NAME
```

**What it does:**
- Creates directory structure in `/home/<VPS_USER>/<PROJECTS_DIR>/APP_NAME`
- Initializes a bare git repository for deployments
- Sets up post-receive hook for tag-based deployments
- Creates `.env` file for environment variables
- Configures Docker Compose deployment on tag push

**After creation:**
```bash
git remote add deploy ssh://<VPS_USER>@<VPS_IP>/home/<VPS_USER>/<PROJECTS_DIR>/APP_NAME/repo.git
git push deploy --tags
```

**Tag-based deployment:** Only git tags trigger deployments, not regular pushes.

---

### Database Management

#### `create-db`
Creates a new PostgreSQL database and user with generated credentials.

```bash
create-db <db_name> [db_host]
```

**Parameters:**
- `db_name` - Name for database and user
- `db_host` - Optional, defaults to `127.0.0.1`

**What it does:**
- Generates secure random password
- Creates PostgreSQL user and database in the `postgres` container (psql -U admin)
- Outputs `DATABASE_URL` connection string

**Example:**
```bash
create-db myapp
# Output: DATABASE_URL=postgresql://myapp:generatedpassword@127.0.0.1:5432/myapp
```

---

### Nginx & SSL Setup

#### `init-nginx`
Configures Nginx reverse proxy and SSL certificate for an application.

```bash
init-nginx APP_NAME SERVER_NAME PORT
```

**Parameters:**
- `APP_NAME` - Application identifier
- `SERVER_NAME` - Domain name (e.g., `app.example.com`)
- `PORT` - Local port where app is running

**What it does:**
- Creates Nginx configuration with reverse proxy
- Enables site in Nginx
- Tests and reloads Nginx
- Requests SSL certificate via Certbot
- Reloads fail2ban rules

**Example:**
```bash
init-nginx myapp myapp.example.com 3000
```

---

### Caddy Setup

#### `init-caddy`
Serves an application as `https://APP_NAME.$CADDY_DOMAIN` through Caddy, for hosts that run Caddy instead of Nginx.

```bash
init-caddy APP_NAME PORT
```

**Parameters:**
- `APP_NAME` - Application identifier, also the subdomain
- `PORT` - Local port the app's container publishes on `127.0.0.1`

**What it does:**
- Writes `/etc/caddy/sites/APP_NAME.caddy`: the site bound to `$VPS_IP`, TLS from `$CADDY_CERT`/`$CADDY_KEY`, reverse proxy to `127.0.0.1:PORT`
- Refuses when the name is already defined in the main Caddyfile or the port is already proxied by another site
- Validates the Caddy configuration and restores the previous site file if validation fails
- Restarts Caddy (the admin API is off, so it cannot reload)

Running it again for the same app rewrites its site file. Uses `sudo` internally, like `init-nginx`.

**One-time setup:** the main `/etc/caddy/Caddyfile` must contain:
```
import /etc/caddy/sites/*.caddy
```

**Example:**
```bash
init-caddy myapp 3000
# https://myapp.example.com -> 127.0.0.1:3000
```

DNS for the name is not handled here.

---

### Backup Scripts

#### `backup-db`
Backs up a single PostgreSQL database to local storage and S3.

```bash
backup-db <db_name> <s3_bucket_name>
```

**What it does:**
- Dumps database from Docker postgres container
- Compresses backup with gzip
- Uploads to S3 bucket
- Logs all operations to `/home/<VPS_USER>/log/backup-db.log`

**Backup location:**
- Local: `/home/<VPS_USER>/backups/<db_name>/dump_<db_name>_YYYY_MM_DD.sql.gz`
- S3: `s3://<bucket>/backups/<db_name>/dump_<db_name>_YYYY_MM_DD.sql.gz`

---

#### `backup-all-dbs`
Backs up multiple databases in sequence.

```bash
backup-all-dbs
```

Reads `$BACKUP_DBS` (comma-separated database names) and `$S3_BUCKET` from `/home/<VPS_USER>/bin/.env` and backs them all up.

---

### Monitoring

#### `stats-email`
Generates and emails VPS statistics report.

```bash
stats-email
```

**Report includes:**
- System uptime, CPU load, memory, disk usage
- Docker container statistics
- Fail2ban jail status

**Email is sent via the `mailer` utility using Maileroo API.**

Note: `stats-email` currently sources `/home/deploy/bin/.env` and runs `/home/deploy/bin/mailer` (hard-coded).

---

## Typical Deployment Workflow

1. **Create application structure:**
   ```bash
   create-app myapp
   ```

2. **Create database:**
   ```bash
   create-db myapp
   ```

3. **Configure environment:**
   ```bash
   vim /home/<VPS_USER>/<PROJECTS_DIR>/myapp/.env
   # Add DATABASE_URL and other vars
   ```

4. **Setup Nginx & SSL:**
   ```bash
   init-nginx myapp myapp.example.com 3000
   ```

5. **Deploy from local machine:**
   ```bash
   git remote add deploy ssh://<VPS_USER>@<VPS_IP>/home/<VPS_USER>/<PROJECTS_DIR>/myapp/repo.git
   git tag v1.0.0
   git push deploy v1.0.0
   ```

---

## Mailer

The `mailer` utility sends HTML emails via the Maileroo API. It's used by `stats-email` for notifications.

**Usage:**
```bash
mailer "Subject" "<html>Email body</html>"
```

**Environment variables:**
- `MAILEROO_API_KEY` - Your Maileroo API key
- `EMAIL_FROM` - Sender email address
- `EMAIL_TO` - Recipient email address

---

## Prerequisites

**VPS must have:**
- Docker & Docker Compose
- Nginx
- Certbot
- PostgreSQL container named `postgres` with `admin` role available
- AWS CLI configured (for S3 backups)
- fail2ban

**Local machine must have:**
- Go 1.25+ (for building mailer)
- rsync
- SSH access to VPS configured

**Required permissions:**
- Scripts assume `deploy` user with sudo access where needed
- SSH key-based authentication configured

---

## Directory Structure

**On VPS:**
```
/home/<VPS_USER>/
├── <PROJECTS_DIR>/
│   └── <APP_NAME>/
│       ├── repo.git/          # Bare git repo
│       ├── release/           # Deployed code
│       └── .env               # App-specific environment variables
├── backups/
│   └── <DB_NAME>/             # Database backups
├── bin/
│   ├── .env                   # Runtime configuration (deployed from .env.remote)
│   ├── create-app
│   ├── create-db
│   ├── init-nginx
│   ├── init-caddy
│   ├── backup-db
│   ├── backup-all-dbs
│   ├── stats-email
│   └── mailer
└── log/
    └── backup-db.log          # Backup logs
```

**In this repo:**
```
vps-scripts/
├── scripts/              # Bash scripts
├── mailer/              # Go source for email utility
├── install.sh           # Installation script
├── git-tag.sh           # Semver tag & deploy helper
├── .env.remote.example  # Configuration template (install target + VPS runtime)
├── .gitignore
└── README.md
```

---

## Automation

Set up cron jobs on the VPS for automated tasks:

**Deploy user crontab** (`crontab -e`):
```bash
# Daily database backups at 3 AM
0 3 * * * /home/<VPS_USER>/bin/backup-all-dbs
```

**Root crontab** (`sudo crontab -e`):
```bash
# Daily stats email at 7:02 AM (requires root for fail2ban-client)
2 7 * * * /home/<VPS_USER>/bin/stats-email
```
