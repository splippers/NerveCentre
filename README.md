# NerveCentre

Splippers **NerveCentre** — unified LAN web entry for Splippers apps (landing page + nginx reverse proxy, redirects, and optional load balancing).

Repository: [github.com/splippers/NerveCentre](https://github.com/splippers/NerveCentre)

There is **no single canonical hostname**: deploy this repo on **Eddie**, **Marvin**, a **dedicated LB**, or behind a **floating VIP**. nginx can spread **Brickwise** across multiple Gluster nodes; **Archive** and **SIC** can use **HTTP redirects** to `:8000` / `:8787`, or (**optional**) **`ARCHIVE_BACKENDS`** / **`SIC_BACKENDS`** for load-balanced **`/archive/`** and **`/sic/`** reverse proxies — see below.

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

## All-in-one install (single host)

From **`Projects/NerveCentre`**, with sibling clones **`../Brickwise`**, **`../Splippers-Archive`**, **`../massdeb8`**, and optionally **`../Monyatron`**, **`../jonotron`**, and **`../Deanotron`**:

```bash
cd Projects/NerveCentre   # or your path to this repo
sudo ./deploy/install-all-splippers.sh
```

This script:

1. Installs or upgrades **Brickwise** into **`/opt/brickwise-venv`**, installs **`brickwise-dashboard.service`**, and enables **`brickwise-dashboard`** (root; Gluster CLI).
2. Creates **`splippers-api/.venv`**, builds **`splippers-ui`**, runs **`scripts/install-splippers-service.sh`**, and enables **`splippers-archive`** (runs as `SUDO_USER` when you used `sudo`).
3. Creates **`massdeb8/.venv`**, builds **`ui/`**, writes **`sic-arena.service`**, and enables **`sic-arena`** (same non-root user when applicable).
4. If **`../Monyatron`** exists (with **`requirements-web.txt`** and **`web/backend/app.py`**), creates **`Monyatron/.venv`**, writes **`monyatron.service`** (Flask + Ollama station desk on **`MONYATRON_PORT`**, default **5050**), and enables **`monyatron`**.
5. If **`../jonotron`** exists, runs **`scripts/install.sh`**, sets **`JONOTRON_PORT`** in **`.env`** (default **8011**, distinct from Splippers Archive on **8000**), runs **`scripts/install-service.sh`**, and enables **`jonotron`** (upstream **`jonotron.service`** template).
6. If **`../Deanotron`** exists, runs **`deploy/deanotron/enroll.sh`** (wraps Deanotron’s **`deploy/install-deanotron.sh`**: Node ≥ 20.19, **`npm ci`**, **`deanotron-web`** on **`DEANOTRON_PORT`**, default **8791**).
7. If **`../moneymakers/projectscan.py`** exists, runs **`deploy/projectscan/install-service.sh`** (**`projectscan-dashboard.service`** on **`PROJECTSCAN_PORT`**, default **8765**).
8. Runs **`deploy/portal/install-portal.sh`** for nginx on port **80** unless **`SKIP_PORTAL=1`**.

Prerequisites: **`python3`**, **`python3-venv`**, **`npm`** (Node.js), and **`nginx`** if you want the portal step (otherwise install nginx later and run `deploy/portal/install-portal.sh` yourself).

Useful options:

| Env / flag | Meaning |
|------------|---------|
| **`./deploy/install-all-splippers.sh --dry-run`** | Print resolved paths only |
| **`REBUILD_UI=1`** | Force `npm install && npm run build` for both UIs |
| **`SKIP_PORTAL=1`** | Skip nginx portal install |
| **`RUN_USER=name`** | User for Splippers + SIC venvs and UI builds (default: invoking user behind `sudo`) |
| **`SPLIPPERS_PORT`**, **`MASSDEB8_PORT`**, **`MONYATRON_PORT`**, **`JONOTRON_PORT`**, **`DEANOTRON_PORT`**, **`PROJECTSCAN_PORT`** | Listener ports (defaults **8000**, **8787**, **5050**, **8011**, **8791**, **8765**); **`PROJECTSCAN_PORT`** is used by **`install-portal.sh`** and **`deploy/projectscan/install-service.sh`**; use **`sudo -E`** so variables survive `sudo` |
| **`SKIP_PORTAL=1`** then **`deploy/portal/install-portal.sh` with **`ARCHIVE_BACKENDS`**, **`SIC_BACKENDS`**, **`BRICKWISE_BACKENDS`**, … | Run the all-in-one on **each** backend without nginx, then configure the VIP/LB once with both Marvin + Eddie in **`_*_BACKENDS`** (see **Full Splippers stack replicated on Marvin and Eddie**) |

## Unified Splippers portal (port 80)

**`http://<host>/` and `http://<host>:80/`** serve the NerveCentre **`index.html`** (unified landing page). **Brickwise**, **Monyatron**, **Jonotron**, and the **project prioritiser** are reverse-proxied under **`/brickwise/`**, **`/monyatron/`**, **`/jonotron/`**, **`/projects/`**. **Archive** and **SIC** use **HTTP redirects** to **`:8000`** / **`:8787`** by default, or optional **`ARCHIVE_BACKENDS`** / **`SIC_BACKENDS`** for load-balanced **`/archive/`** / **`/sic/`** (see **Load-balanced Splippers Archive and SIC**). **Deanotron** uses a **redirect** to **`:8791`** (Expo web — see `Deanotron/deploy/`).

1. Install nginx (`sudo apt install nginx` on Debian/Ubuntu).
2. Ensure Splippers backends are running where you intend (Brickwise on Gluster nodes, Archive/SIC, Monyatron, Jonotron, Deanotron, and **`projectscan-dashboard`** for **`/projects/`** — see **Project prioritiser** below).
3. From this repo:

   ```bash
   sudo bash deploy/portal/install-portal.sh
   ```

Do **not** set **`JONOTRON_HTTP_PREFIX`** in **`jonotron/.env`** when using this portal — nginx strips **`/jonotron/`** toward the backend and rewrites **`/api`** and **`/ui`** in HTML/JS responses.

### Load-balanced Brickwise (Eddie + Marvin)

Point nginx at **both** Brickwise listeners (same port on each node is typical):

```bash
sudo BRICKWISE_BACKENDS="10.0.0.1:8756 10.0.0.2:8756" \
  bash deploy/portal/install-portal.sh
```

Use your LAN IPs or DNS names. Optional **`BRICKWISE_LB_METHOD`**: `least_conn` (default), `round_robin`, or `ip_hash` (sticky by client IP).

If **`BRICKWISE_BACKENDS`** is unset, nginx uses **`127.0.0.1:$BW_PORT`** (default **`BW_PORT=8756`**) — colocated Brickwise only.

### Load-balanced Monyatron (optional)

Same idea as Brickwise — multiple Flask backends:

```bash
sudo MONYATRON_BACKENDS="10.0.0.1:5050 10.0.0.2:5050" \
  bash deploy/portal/install-portal.sh
```

If **`MONYATRON_BACKENDS`** is unset, nginx proxies **`/monyatron/`** to **`127.0.0.1:$MONYATRON_PORT`** (default **`MONYATRON_PORT=5050`**).

### Load-balanced Jonotron (optional)

```bash
sudo JONOTRON_BACKENDS="10.0.0.1:8011 10.0.0.2:8011" \
  bash deploy/portal/install-portal.sh
```

If **`JONOTRON_BACKENDS`** is unset, nginx proxies **`/jonotron/`** to **`127.0.0.1:$JONOTRON_PORT`** (default **`JONOTRON_PORT=8011`** so Splippers Archive can keep **8000** on the same host).

### Load-balanced Splippers Archive and SIC (optional — VIP / unified hostname)

Run **`splippers-archive`** (port **8000**) and **`sic-arena`** (**8787**) on **both** Marvin and Eddie, then teach the nginx portal about both listeners so **`http://vip/archive/`** and **`http://vip/sic/`** spread traffic the same way as Brickwise (**strip prefix** **`/archive/`** / **`/sic/`**, **`sub_filter`** for **`/api/`**):

```bash
sudo ARCHIVE_BACKENDS="MARVIN_LAN_IP:8000 EDDIE_LAN_IP:8000" \
     SIC_BACKENDS="MARVIN_LAN_IP:8787 EDDIE_LAN_IP:8787" \
     bash deploy/portal/install-portal.sh
```

Replace LAN IPs or DNS names. Optional **`ARCHIVE_LB_METHOD`** / **`SIC_LB_METHOD`**: **`least_conn`** (default), **`round_robin`**, or **`ip_hash`** (sticky sessions).

When **`ARCHIVE_BACKENDS`** / **`SIC_BACKENDS`** are **unset**, the portal **`302`** redirects to **`http://$host:8000`** and **`$host:8787`**. That favours deployments where browsers hit **Marvin** or **Eddie** by name — each sends you to Archive/SIC on **that same host**. Setting **`ARCHIVE_REDIRECT_HOST`** / **`SIC_REDIRECT_HOST`** is ignored once the corresponding **`*_BACKENDS`** list is set (proxy mode wins).

If a frontend uses **hard-coded absolute URLs** (`/assets/…` etc.) behind **`/archive/`**, you may need extra **`sub_filter`** rules — fall back to **redirect** mode and open Archive/SIC by **host:port** on each node instead.

### Project prioritiser (`/projects/`)

The NerveCentre landing page links to **`/projects/`**, which nginx reverse-proxies to **`projectscan-dashboard.service`** (runs **`moneymakers/projectscan.py serve`**) on **`127.0.0.1:$PROJECTSCAN_PORT`** (default **`8765`**).

**Persistent service (recommended)**

From this repo, with **`../moneymakers/projectscan.py`** present:

```bash
cd Projects/NerveCentre
sudo PROJECTSCAN_PORT=8765 RUN_USER=yourlogin bash deploy/projectscan/install-service.sh
```

That writes **`/etc/default/projectscan`** and **`/etc/systemd/system/projectscan-dashboard.service`**, then enables and starts the unit. Optional install-time env: **`PROJECTSCAN_HOME`**, **`PROJECTSCAN_ROOT`**, **`PROJECTSCAN_INDEX_DIR`**, **`PROJECTSCAN_PUBLIC_ORIGIN`** (e.g. **`http://192.168.1.2`** — makes the dashboard’s “Drive setup guide” link absolute to your LAN nginx host; see script header). After changing the defaults file: **`sudo systemctl restart projectscan-dashboard`**.

All-in-one installers: **`install-all-splippers.sh`** installs the same unit as step **[6b/8]** when moneymakers is present.

Manual run (no systemd): **`cd ../moneymakers && python3 projectscan.py serve`**.

**Portal / nginx**

Keep a checkout at **`../moneymakers`** (sibling of **NerveCentre** under **`Projects/`**), or override paths with **`PROJECTSCAN_ROOT`** / **`PROJECTSCAN_INDEX_DIR`** in **`/etc/default/projectscan`**.

```bash
sudo PROJECTSCAN_PORT=8765 bash deploy/portal/install-portal.sh
```

Load-balanced backends (optional), same pattern as Monyatron/Jonotron:

```bash
sudo PROJECTSCAN_BACKENDS="10.0.0.1:8765 10.0.0.2:8765" \
  bash deploy/portal/install-portal.sh
```

### Deanotron (Expo web — redirect)

The portal links **`/deanotron/`** → **`302`** → **`http://$host:$DEANOTRON_PORT/`** (default **`8791`**, matching `Deanotron/deploy/install-deanotron.sh`). Expo’s dev server expects root URLs; path-prefix reverse proxy is not used here.

Pin another host if needed: **`DEANOTRON_REDIRECT_HOST`**.

### Redirects for Archive / SIC on a specific node

If Splippers Archive or SIC runs only on one host (not on the VIP), pin the HTTP redirects:

```bash
sudo ARCHIVE_REDIRECT_HOST=marvin.lan SIC_REDIRECT_HOST=eddie.lan \
  bash deploy/portal/install-portal.sh
```

Override ports with **`ARCHIVE_PORT`** (default **8000**) and **`SIC_PORT`** (default **8787**). If **`ARCHIVE_REDIRECT_HOST`** / **`SIC_REDIRECT_HOST`** are unset, redirects use **`http://$host:port/`** (same hostname the client used).

Static assets install under **`/var/www/splippers-portal/`**; the nginx site defaults to **`splippers-portal`**.

### Full Splippers stack replicated on Marvin and Eddie

**Goal**: same systemd services and backends on **both** machines so either node (or keepalived / round-robin DNS) survives the loss of one host.

1. On **each** machine, put sibling clones next to **`NerveCentre`** (same **`Projects/`** layout): **`Brickwise`**, **`Splippers-Archive`**, **`massdeb8`**, and any optional repos you use (**`Monyatron`**, **`jonotron`**, **`Deanotron`**, **`moneymakers`** for projectscan).

2. On **each** host:

   ```bash
   cd /path/to/Projects/NerveCentre
   sudo -E ./deploy/install-all-splippers.sh
   ```

   Use **`SKIP_PORTAL=1`** on one or both if only a single nginx entry should own port **80** (for example **`sudo SKIP_PORTAL=1`** on backend-only builds and run **`deploy/portal/install-portal.sh` once** where you terminate HTTP).

3. Install or refresh the nginx portal **where clients land** — typically the VIP, LB, **or both** Marvin and Eddie if they each advertise **`http://<that-host>/`** — with **`*_BACKENDS`** listing **both** LAN addresses for anything you want pooled:

```bash
sudo BRICKWISE_BACKENDS="MARVIN_IP:8756 EDDIE_IP:8756" \
     ARCHIVE_BACKENDS="MARVIN_IP:8000 EDDIE_IP:8000" \
     SIC_BACKENDS="MARVIN_IP:8787 EDDIE_IP:8787" \
     MONYATRON_BACKENDS="MARVIN_IP:5050 EDDIE_IP:5050" \
     JONOTRON_BACKENDS="MARVIN_IP:8011 EDDIE_IP:8011" \
     PROJECTSCAN_BACKENDS="MARVIN_IP:8765 EDDIE_IP:8765" \
     bash deploy/portal/install-portal.sh
```

Add **`CEO_SIMULATOR_BACKENDS`** if you use **CEO-Simulator**. Omit any line for services you do not run.

4. **Deanotron** stays a **redirect** to **`http://$host:8791/`** by default. With **Expo** absolute paths, that still works if **each** node runs **`deanotron-web`** and users reach that node’s hostname; for a **single VIP** name you often pick **one** **`DEANOTRON_REDIRECT_HOST`** or run Deanotron only where the VIP points for that path.

5. **Gluster / Brickwise**: keep both nodes in the storage pool; load-balanced Brickwise is already the expected pattern for Eddie + Marvin.

## Enrolling Deanotron

With a **Deanotron** clone beside this repo (e.g. **`Projects/Deanotron`** next to **`Projects/NerveCentre`**):

```bash
cd Projects/NerveCentre
sudo ./deploy/deanotron/enroll.sh
```

This installs **`/etc/default/deanotron`**, **`deanotron-web.service`**, and starts **Expo web** on **`DEANOTRON_PORT`** (default **8791**). Override **`DEANOTRON_SRC`** if the repo lives elsewhere. Then run **`deploy/portal/install-portal.sh`** (or the full **`install-all-splippers.sh`**) so nginx redirects **`/deanotron/`** to that port.

## Layout

| Path | Role |
|------|------|
| `deploy/portal/index.html` | Landing page UI (links **`/projects/`** to moneymakers project prioritiser) |
| `deploy/portal/moneymakers-drive-guide.html` | Step-by-step Google Drive OAuth for projectscan (linked from portal + dashboard) |
| `deploy/portal/install-portal.sh` | Writes nginx site (upstream + server block) and reloads nginx |
| `deploy/projectscan/install-service.sh` | **`projectscan-dashboard.service`** + **`/etc/default/projectscan`** (moneymakers dashboard) |
| `deploy/install-repo.sh` | Clone / pull this repository |
| `deploy/install-all-splippers.sh` | Brickwise + Splippers Archive + SIC venvs, UI builds, systemd, optional nginx portal |
| `deploy/deanotron/enroll.sh` | Enroll Deanotron (delegates to Deanotron `deploy/install-deanotron.sh`) |

The former **`deploy/marvin-portal/`** path is retired; use **`deploy/portal/`** only.
