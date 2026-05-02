# NerveCentre

Splippers **NerveCentre** — unified LAN web entry for Marvin-hosted Splippers apps (landing page + nginx reverse proxy / redirects).

Repository: [github.com/splippers/NerveCentre](https://github.com/splippers/NerveCentre)

## Path on Marvin

Keep this clone at:

```text
/mnt/SANDIEGO/Projects/NerveCentre
```

Use the same `/mnt/SANDIEGO/…` layout as your other Splippers project mounts (Gluster or local disk).

## Clone or update on Marvin

Requires `git`, `sudo` (only if `/mnt/SANDIEGO/Projects` does not exist yet), and network access to GitHub.

```bash
bash deploy/install-on-marvin.sh
```

Environment overrides:

- **`NERVECENTRE_ROOT`** — clone directory (default `/mnt/SANDIEGO/Projects/NerveCentre`)
- **`NERVECENTRE_REPO_URL`** — Git remote (default `https://github.com/splippers/NerveCentre.git`)

If the directory already exists with a `.git` folder, the script runs `git pull --ff-only` instead of cloning.

## Unified Splippers portal (port 80)

After the repo is on disk, install nginx and publish the portal:

1. Install nginx if needed (`sudo apt install nginx` on Debian/Ubuntu).
2. Ensure backend services are running (e.g. Brickwise on **8756**, Splippers Archive on **8000**, SIC/massdeb8 on **8787**).
3. From this repo root on Marvin:

   ```bash
   sudo bash deploy/marvin-portal/install-portal.sh
   ```

   Override ports with **`BW_PORT`**, **`ARCHIVE_PORT`**, **`SIC_PORT`** if needed.

Then open `http://<marvin-lan-ip>/`. Brickwise is served under **`/brickwise/`** (proxied); Splippers Archive and SIC redirect to their configured ports so SPA asset URLs keep working.

Static assets are installed under **`/var/www/splippers-portal/`**; the nginx site name defaults to **`splippers-portal`**. If you previously used `marvin-portal` and `/var/www/marvin-portal` from an older Brickwise-bundled install, disable that site or align paths before switching.

## Layout

| Path | Role |
|------|------|
| `deploy/marvin-portal/index.html` | Landing page UI |
| `deploy/marvin-portal/nginx-splippers-portal.conf.in` | nginx template (sed-filled by install script) |
| `deploy/marvin-portal/install-portal.sh` | Installs static files + nginx site + reload |

## Elsewhere (e.g. Eddie)

You can develop under `/mnt/EDDIE-SANDIEGO/Projects/NerveCentre` or any path; Marvin remains the canonical deployment root above.
