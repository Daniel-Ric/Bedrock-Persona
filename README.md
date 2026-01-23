# Persona Assets

This repository automatically mirrors Minecraft Bedrock Persona catalog entries using PlayFab Economy v2 (Catalog/Search).

## Web UI

- https://Daniel-Ric.github.io/Bedrock-Persona/

## What gets updated

- \: normalized persona emote entries
- \: all other PersonaDurable entries excluding persona_emote
- \: unique keyword/rarity/creator/contentType summaries
- \: added/removed/changed UUIDs compared to previous run
- \: static web UI published via GitHub Pages

## Schedule

- Runs on push and every 6 hours via GitHub Actions
- Last update (UTC): 2026-01-23T19:00:08Z

## Current counts

- persona_emote: 1790 (added=0, removed=0, changed=0)
- persona_piece: 10200 (added=3, removed=3, changed=0)

## Setup

1. Add the workflow + script to the repo
2. Add the Actions secret \ (any stable unique string, UUID recommended)
3. Enable GitHub Pages: Settings → Pages → Source: GitHub Actions
4. Run the workflow once (Actions → Update Persona Assets → Run workflow)

## Notes

- No secrets are committed to the repository.
- The workflow only commits when actual catalog changes are detected.
