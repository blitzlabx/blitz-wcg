# Blitz WCG

**Word Chain Game bot for Telegram**

Created by **Blitz**  
Social: [blitzlabx](https://t.me/blitzlabx)

A polished, competitive multiplayer Word Chain game that works in Telegram groups and private chats (1v1 challenges).

## Features

- Group multiplayer games
- DM challenge system (`/challenge @username`)
- Dictionary-backed word validation with caching + fallback
- Turn timers, scoring, duplicate prevention
- Floket human verification layer
- Full admin panel (broadcast, ban, maintenance, stats, etc.)
- Leaderboard & profiles
- Health endpoints for UptimeRobot (`/ping`, `/health`)
- Docker-ready for Render Free

## Quick Start (local)

```bash
cp .env.example .env
# edit .env with your TELEGRAM_BOT_TOKEN and ADMIN_ID
bundle install
bundle exec ruby bin/bot
```

## Deploy on Render Free

1. Create a new **Web Service**
2. Connect this repo
3. Runtime: Docker
4. Set environment variables from `.env.example`
5. Add a health check path: `/health` or `/ping`
6. Deploy

UptimeRobot can hit `https://your-service.onrender.com/ping` every 5 minutes.

## Commands

| Command | Description |
|---------|-------------|
| /start | Welcome + main menu |
| /play | Start/join group game |
| /challenge @user | Send DM challenge |
| /accept /decline | Respond to challenge |
| /cancel | Cancel game |
| /profile /stats /leaderboard | Player stats |
| /rules /donate /ping /health | Utility |
| /admin ... | Admin only |

## Architecture

Clean Ruby modules:

- `game/` — engine + state
- `dictionary/` — API client + cache
- `challenge/` — DM challenges
- `floket/` — verification
- `admin/` — control plane
- `handlers/` — Telegram commands/callbacks/messages
- `persistence/` — JSON file store
- `health_server` — WEBrick for Render/UptimeRobot

## License

MIT — Created by Blitz (blitzlabx)
