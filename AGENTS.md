# AGENTS.md — instructions for Codex

Do Zore is a mobile idle kafana-management game. This is a monorepo shared by two agents:
Codex (client, tools) and Claude (backend, contract, data). See `README.md` for the full layout.

## Ownership

- You own `/client` (Godot 4 client) and `/tools` (Python economy simulator).
- **Never modify `/server`, `/contracts` or `/data`.** Read them only.

## API contract

- The API contract is `/contracts/openapi.yaml`. Build the client against it.
- If the contract seems wrong, incomplete or awkward to use, **do not change it**. Write the
  issue in `/client/CONTRACT_ISSUES.md` (endpoint, problem, suggested fix) instead.

## Offline-first

- The game must be fully playable offline. Never block gameplay on a network call.
- Treat the server as optional: local save is authoritative for play, and syncing is best-effort.
