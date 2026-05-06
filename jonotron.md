# Jonotron - AI Assistant with Long-Term Memory

## Overview
Jonotron is a rebranded OpenCode assistant with persistent memory across sessions, running on the Marvin system. Replaced 2026-05-06 with new memory harness and web interface.

## Files Location
- **jonotron-harness.sh**: `/home/jon/jonotron-harness.sh`
- **jonotron-web.py**: `/home/jon/jonotron-web.py`
- **Memory**: `~/.jonotron_memory/`

## New Features (2026-05-06)
- Long-term memory harness that persists conversation history across sessions
- Local Flask web server on `http://localhost:5000` for browser-based interaction
- Automatic context loading from last 5 sessions
- Unity/BoreDoom project awareness

## Usage

### Running Jonotron with Memory
```bash
cd /home/jon
./jonotron-harness.sh
```

### Starting the Web Interface
```bash
cd /home/jon
python3 jonotron-web.py
```
Then visit `http://localhost:5000` in your browser.

## Memory Structure
```
~/.jonotron_memory/
├── current_context.txt
└── history/
    ├── YYYYMMDD_HHMMSS.jsonl
    └── ...
```

## Integration with NerveCentre
- Listed as a service in the all-in-one installer (`../jonotron`)
- Configured for load balancing with `JONOTRON_BACKENDS`
- Default port: `8011` (distinct from Splippers Archive on `8000`)
- Service file: `jonotron.service` (installed via `scripts/install-service.sh`)

## Linked Repos
- [BoreDoom](https://github.com/splippers/BoreDoom)
- [ChoreWars](https://github.com/splippers/ChoreWars)
- [NerveCentre](https://github.com/splippers/NerveCentre)

## Previous Entry (Replaced)
The previous Jonotron entry described an older setup without the memory harness. This update adds persistent context and web interface capabilities.
