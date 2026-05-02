# NerveCentre

Splippers **NerveCentre** — unified LAN web entry for Splippers apps (landing page + nginx reverse proxy, redirects, and optional load balancing).

Repository: [github.com/splippers/NerveCentre](https://github.com/splippers/NerveCentre)

There is **no single canonical hostname**: deploy this repo on **Eddie**, **Marvin**, a **dedicated LB**, or behind a **floating VIP**. nginx can spread **Brickwise** across multiple Gluster nodes; Archive and SIC redirects can target whichever host runs those services.

## Clone or update (any host)

Requires `git` and a writable parent directory (use `sudo` only if the parent path requires it).

```bash
bash deploy/install-repo.sh
```

Environment overrides:

| Variable | Meaning |
|----------|---------|
| **`NERVECENTRE_ROOT`** | Destination directory (default **`~/Projects/NerveCentre`**) |
| **`NERVECENTRE_REPO_URL`** | Git remote (default `https://github.com/splippers/NerveCentre.git`) |

Examples:

```bash
NERVECENTRE_ROOT=/mnt/EDDIE-SANDIEGO/Projects/NerveCentre bash deploy/install-repo.sh
NERVECENTRE_ROOT=/mnt/SANDIEGO/Projects/NerveCentre bash deploy/install-repo.sh
```

If `NERVECENTRE_ROOT` already exists with a `.git` folder, the script runs `git pull --ff-only` instead of cloning.

## Unified Splippers portal (port 80)

1. Install nginx (`sudo apt install nginx` on Debian/Ubuntu).
2. Ensure Splippers backends are running where you intend (Brickwise on Gluster nodes, Archive/SIC as you deploy them).
3. From this repo:

   ```bash
   sudo bash deploy/portal/install-portal.sh
   ```

### Load-balanced Brickwise (Eddie + Marvin)

Point nginx at **both** Brickwise listeners (same port on each node is typical):

```bash
sudo BRICKWISE_BACKENDS="10.0.0.1:8756 10.0.0.2:8756" \
  bash deploy/portal/install-portal.sh
```

Use your LAN IPs or DNS names. Optional **`BRICKWISE_LB_METHOD`**: `least_conn` (default), `round_robin`, or `ip_hash` (sticky by client IP).

If **`BRICKWISE_BACKENDS`** is unset, nginx uses **`127.0.0.1:$BW_PORT`** (default **`BW_PORT=8756`**) — colocated Brickwise only.

### Redirects for Archive / SIC on a specific node

If Splippers Archive or SIC runs only on one host (not on the VIP), pin the HTTP redirects:

```bash
sudo ARCHIVE_REDIRECT_HOST=marvin.lan SIC_REDIRECT_HOST=eddie.lan \
  bash deploy/portal/install-portal.sh
```

Override ports with **`ARCHIVE_PORT`** (default **8000**) and **`SIC_PORT`** (default **8787**). If **`ARCHIVE_REDIRECT_HOST`** / **`SIC_REDIRECT_HOST`** are unset, redirects use **`http://$host:port/`** (same hostname the client used).

Static assets install under **`/var/www/splippers-portal/`**; the nginx site defaults to **`splippers-portal`**.

## Layout

| Path | Role |
|------|------|
| `deploy/portal/index.html` | Landing page UI |
| `deploy/portal/install-portal.sh` | Writes nginx site (upstream + server block) and reloads nginx |
| `deploy/install-repo.sh` | Clone / pull this repository |

The former **`deploy/marvin-portal/`** path is retired; use **`deploy/portal/`** only.
