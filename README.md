# Agent Skills

Skills for AI agents in the open Agent Skills format: each skill is a folder
with a `SKILL.md` (the instructions an agent loads), plus optional `scripts/`
and `references/`. They work in **Paperclip**, **Claude Code**, **Codex** and
other compatible clients.

## Skills

| Skill | What it does | Needs |
|---|---|---|
| [`youtube-data-api-skill`](skills/youtube-data-api-skill/SKILL.md) | Read public YouTube data (search, video and channel stats, uploads, playlists, comments, trending) with a pool of API keys that rotates when one runs out of quota | `YOUTUBE_API_KEYS`, `bash`, `curl`, `jq` |

## Install

### Paperclip

1. **Skills → + New → Import from GitHub** (or **Import from path or URL**) →
   `https://github.com/hailongtrinh/agent-skills`
2. Click **Find skills** and select the skills to import. They are pinned to
   the current commit; use **Refresh** later to pull updates.
3. Open the agent's **Skills** tab and enable the skill.
4. Create a company secret with the keys and bind it to the agent as
   `env.YOUTUBE_API_KEYS`. Never paste keys into issues or comments.

### skills CLI (Claude Code, Codex, …)

```bash
npx skills add https://github.com/hailongtrinh/agent-skills --skill youtube-data-api-skill
```

### Manual

```bash
git clone https://github.com/hailongtrinh/agent-skills
cp -r agent-skills/skills/youtube-data-api-skill ~/.claude/skills/
export YOUTUBE_API_KEYS=key1,key2
```

## youtube-data-api-skill: keys

`YOUTUBE_API_KEYS` holds one key or several separated by commas. Each call
uses a random key; a key that hits `quotaExceeded` is skipped until midnight
Pacific time (when the quota resets), and when every key is spent the helper
fails with exit code 3. `scripts/yt.sh keys` shows the pool status without an
API call. Keys are only ever shown as `key#N (…last4)`.

Quota is per Google Cloud project, so keys only add headroom when they come
from different projects. Use them in line with the YouTube API Services Terms
and Developer Policies that apply to you.

## Layout

```
skills/
└── <skill-name>/
    ├── SKILL.md        # frontmatter (name, description) + instructions
    ├── scripts/        # helpers the instructions call (executable)
    └── references/     # longer docs, loaded only when needed
```
