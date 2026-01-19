# Persona Assets

Automated dataset and web viewer for Minecraft Bedrock Persona catalog assets (PlayFab Economy v2).

## Live Web UI

- https://Daniel-Ric.github.io/Bedrock-Persona/

## Update Schedule

- Runs on push and every 6 hours via GitHub Actions
- Last update (UTC): 2026-01-19T14:57:59Z

## Counts

- persona_emote: 1790 (added=0, removed=0, changed=0)
- persona_piece: 10200 (added=0, removed=0, changed=0)

## Files

- data/index.json
- data/persona_emote/items.json
- data/persona_piece/items.json
- data/*/metadata.json
- site/ (GitHub Pages output)

## Setup

1. Add .github/workflows/main.yml and update.sh
2. Add Actions secret IOS_DEVICE_ID
3. Enable GitHub Pages: Settings → Pages → Source: GitHub Actions
4. Run the workflow once
