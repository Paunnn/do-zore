# Do Zore

Do Zore ("till dawn") is a mobile idle game where you run a Balkan kafana: start with a few
tables and a tired accordion player, serve rakija and coffee, hire staff and musicians, and grow
the place into the liveliest spot in town while it keeps earning even when you are away. The game
is fully playable offline; an optional backend adds accounts and cloud save.

## Repository layout

| Folder       | Contents                                  | Owner  |
|--------------|-------------------------------------------|--------|
| `/client`    | Godot 4 game client                       | Codex  |
| `/tools`     | Python economy simulator                  | Codex  |
| `/server`    | ASP.NET Core backend                      | Claude |
| `/contracts` | OpenAPI spec + JSON Schemas               | Claude |
| `/data`      | Game balance JSON                         | Claude |

Each agent only modifies the folders it owns and reads the rest. Agent rules live in
`CLAUDE.md` (Claude) and `AGENTS.md` (Codex).

## Workflow

1. **Contract first** — define or change the API in `/contracts/openapi.yaml`, logged in
   `/contracts/CHANGELOG.md`.
2. **Server and client in parallel** — server work on branch `server`, client work on branch
   `client`, both built against the agreed contract. Client-side contract problems go in
   `/client/CONTRACT_ISSUES.md`.
3. **Merge to `main`** — each branch merges once its side is working.
4. **Integration** — run client against server on `main` and fix any gaps.

## Configuration

Copy `.env.example` to `.env` for local server settings. Never commit `.env`.
