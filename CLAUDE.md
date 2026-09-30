# CLAUDE.md — instructions for Claude

Do Zore is a mobile idle kafana-management game. This is a monorepo shared by two agents:
Claude (backend, contract, data) and Codex (client, tools). See `README.md` for the full layout.

## Ownership

- You own `/server`, `/contracts` and `/data`.
- **Never modify `/client` or `/tools`.** You may read them.

## API contract

- `/contracts/openapi.yaml` is the single source of truth for the API. The server implements it;
  it does not drift from it.
- Log every contract change in `/contracts/CHANGELOG.md` (date, what changed, why, breaking or not).
- **Before changing the contract, check `/client/CONTRACT_ISSUES.md`** for problems the client
  side has reported, and address them where relevant.

## Offline-first

- The game must stay playable offline. The server is never required to play.
- Server features (accounts, cloud save, leaderboards, etc.) are optional enhancements; design
  every endpoint so the client can work without it and sync later.
