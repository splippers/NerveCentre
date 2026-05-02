# NerveCentre

Splippers **NerveCentre** — central coordination for Marvin-hosted services (repo scaffold).

## Path on Marvin

On **Marvin**, keep this clone at:

```text
/mnt/SANDIEGO/Projects/NerveCentre
```

Use the same `/mnt/SANDIEGO/…` layout as your other Splippers project mounts (Gluster or local disk).

## One-shot setup on Marvin

Requires `git`, `sudo` (only if `/mnt/SANDIEGO/Projects` does not exist yet), and network access to GitHub.

From a checkout anywhere (or copy the script out of this repo):

```bash
bash deploy/install-on-marvin.sh
```

Environment overrides:

- **`NERVECENTRE_ROOT`** — clone directory (default `/mnt/SANDIEGO/Projects/NerveCentre`)
- **`NERVECENTRE_REPO_URL`** — Git remote (default `https://github.com/splippers/NerveCentre.git`)

If the directory already exists with a `.git` folder, the script runs `git pull --ff-only` instead of cloning.

## Elsewhere (e.g. Eddie)

You can develop under `/mnt/EDDIE-SANDIEGO/Projects/NerveCentre` or any path; Marvin remains the canonical deployment root above.
