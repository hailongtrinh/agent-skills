#!/usr/bin/env bash
# YouTube Data API v3 helper (read-only, API keys with rotation).
#
#   yt.sh get <resource> [param=value ...]                one request, raw JSON
#   yt.sh all <resource> [--max-pages N] [param=value ...] follow nextPageToken (default 5 pages)
#   yt.sh video-id <url|id>                               extract a video id (no API call)
#   yt.sh channel <@handle|channel URL|UC… id> [parts]    resolve a channel (1 unit)
#   yt.sh uploads <@handle|channel URL|UC… id> [max]      latest uploads of a channel (2+ units)
#   yt.sh keys                                            key pool status today (no API call)
#
# Examples:
#   yt.sh get videos part=snippet,statistics id=dQw4w9WgXcQ
#   yt.sh all commentThreads --max-pages 3 part=snippet videoId=dQw4w9WgXcQ textFormat=plainText maxResults=100
#
# Env:
#   YOUTUBE_API_KEYS  one key or a comma-separated list. Never print it.
#                     (YOUTUBE_API_KEY is still read when YOUTUBE_API_KEYS is unset.)
#   YOUTUBE_API_URL   default https://www.googleapis.com/youtube/v3
#   YT_STATE_DIR      where out-of-quota keys are remembered for the day
#                     (default ${XDG_STATE_HOME:-~/.local/state}/youtube-data-api-skill)
# Inside a Paperclip run without these in env, the keys are read from the
# agent's granted secret YOUTUBE_API_KEYS / YOUTUBE_API_KEY.
#
# Key rotation: keys are tried in random order. A key that returns
# quotaExceeded is remembered as spent until midnight Pacific time and the next
# key is tried; a broken key (invalid, API not enabled, blocked) is skipped for
# this run. When every key is spent the call fails with exit code 3.
# Keys are only ever shown as `key#<n> (…last4)`; they are sent as the
# `x-goog-api-key` header through curl's config on stdin, never in URLs.
#
# Exit codes: 0 ok, 1 API error (`HTTP <status> <reason>: <message>` on stderr),
#             2 usage/config error, 3 every key is out of quota or unusable.
set -euo pipefail

API_URL="${YOUTUBE_API_URL:-https://www.googleapis.com/youtube/v3}"
API_URL="${API_URL%/}"
STATE_DIR="${YT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/youtube-data-api-skill}"
SPENT_FILE="$STATE_DIR/spent-keys"
RATE_LIMIT_RETRIES=3

die() { echo "yt: $1" >&2; exit "${2:-2}"; }
note() { echo "yt: $1" >&2; }
usage() { sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; }

KEYS=()      # the pool, deduplicated, in configured order
ORDER=()     # indexes into KEYS, shuffled once per run
CURRENT=0    # position in ORDER of the key in use
BROKEN=()    # indexes skipped for this run

# Quota resets at midnight Pacific time; the day is the bucket for spent keys.
quota_day() { TZ=America/Los_Angeles date +%F; }

# Stable fingerprint of a key, so the state file never holds the key itself.
fingerprint() {
  if command -v sha256sum >/dev/null; then printf '%s' "$1" | sha256sum | cut -c1-16
  else printf '%s' "$1" | shasum -a 256 | cut -c1-16; fi
}

label() { local i="$1" k="${KEYS[$1]}"; printf 'key#%d (…%s)' "$((i + 1))" "${k: -4}"; }

load_keys() {
  local raw="${YOUTUBE_API_KEYS:-${YOUTUBE_API_KEY:-}}"
  if [[ -z "$raw" && -n "${PAPERCLIP_API_URL:-}" && -n "${PAPERCLIP_API_KEY:-}" ]]; then
    local base="${PAPERCLIP_API_URL%/}"; base="${base%/api}"
    local name
    for name in YOUTUBE_API_KEYS youtube_api_keys YOUTUBE_API_KEY youtube_api_key; do
      raw="$(curl -sf -X POST -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
        "$base/api/agents/me/secrets/$name/value" 2>/dev/null | jq -r '.value // empty' 2>/dev/null || true)"
      [[ -n "$raw" ]] && break
    done
  fi
  [[ -n "$raw" ]] || die "YOUTUBE_API_KEYS is not set (one API key, or several separated by commas)"
  local key seen=" "
  IFS=',' read -r -a parts <<<"$raw"
  for key in "${parts[@]}"; do
    key="${key//[[:space:]]/}"
    [[ -z "$key" || "$seen" == *" $key "* ]] && continue
    [[ "$key" =~ ^[A-Za-z0-9_-]+$ ]] || die "YOUTUBE_API_KEYS has an entry that is not an API key (allowed: letters, digits, _ and -)"
    KEYS+=("$key"); seen+="$key "
  done
  ((${#KEYS[@]})) || die "YOUTUBE_API_KEYS has no keys"
  # Fisher-Yates shuffle with $RANDOM (no shuf on macOS).
  local n=${#KEYS[@]} j tmp
  for ((j = 0; j < n; j++)); do ORDER+=("$j"); done
  for ((j = n - 1; j > 0; j--)); do
    local r=$((RANDOM % (j + 1)))
    tmp="${ORDER[$j]}"; ORDER[$j]="${ORDER[$r]}"; ORDER[$r]="$tmp"
  done
}

is_spent() {
  [[ -f "$SPENT_FILE" ]] || return 1
  grep -qx "$(quota_day) $(fingerprint "${KEYS[$1]}")" "$SPENT_FILE"
}

mark_spent() {
  mkdir -p "$STATE_DIR"
  local today; today="$(quota_day)"
  # Drop other days, then record this key for today.
  if [[ -f "$SPENT_FILE" ]]; then
    grep "^$today " "$SPENT_FILE" > "$SPENT_FILE.tmp" 2>/dev/null || true
    mv "$SPENT_FILE.tmp" "$SPENT_FILE"
  fi
  echo "$today $(fingerprint "${KEYS[$1]}")" >> "$SPENT_FILE"
}

is_broken() { local b; for b in "${BROKEN[@]}"; do [[ "$b" == "$1" ]] && return 0; done; return 1; }

# Moves CURRENT to the next usable key; fails when none is left.
next_key() {
  while (( CURRENT < ${#ORDER[@]} )); do
    local i="${ORDER[$CURRENT]}"
    if ! is_spent "$i" && ! is_broken "$i"; then return 0; fi
    CURRENT=$((CURRENT + 1))
  done
  local spent=0 i
  for i in "${!KEYS[@]}"; do is_spent "$i" && spent=$((spent + 1)); done
  local reset; reset="$(TZ=America/Los_Angeles date -d 'tomorrow 00:00' '+%Y-%m-%d %H:%M %Z')"
  die "all ${#KEYS[@]} keys are unusable: $spent out of quota today (resets $reset), $(( ${#KEYS[@]} - spent )) broken or blocked" 3
}

# Reason of an error body: legacy errors[].reason, else ErrorInfo details[].reason, else status.
error_reason() {
  jq -r '.error | (.errors[0].reason // (.details // [] | map(select(.reason)) | .[0].reason) // .status // empty)' 2>/dev/null <<<"$1" || true
}

# GET <resource> with param=value args; prints the JSON body, rotating keys as needed.
request() {
  local resource="$1"; shift
  local args=() param response status reason message tries=0
  for param in "$@"; do
    [[ "$param" == *=* ]] || die "parameter must be name=value: $param"
    [[ "${param%%=*}" == "key" ]] && die "do not pass key=…; keys come from YOUTUBE_API_KEYS and are sent as a header"
    args+=(--data-urlencode "$param")
  done
  while :; do
    next_key
    local i="${ORDER[$CURRENT]}"
    response="$(printf 'header = "x-goog-api-key: %s"\n' "${KEYS[$i]}" |
      curl -sS -G -K - -w '\n%{http_code}' "${args[@]}" "$API_URL/$resource")" || die "cannot reach $API_URL" 1
    status="${response##*$'\n'}"; response="${response%$'\n'*}"
    if [[ "$status" == 2* ]]; then printf '%s\n' "$response"; return 0; fi
    reason="$(error_reason "$response")"
    message="$(jq -r '.error.message // empty' 2>/dev/null <<<"$response" || true)"
    case "$reason" in
      quotaExceeded|dailyLimitExceeded|RATE_LIMIT_EXCEEDED_DAILY)
        mark_spent "$i"; note "$(label "$i") is out of quota today, trying the next key"
        CURRENT=$((CURRENT + 1)); tries=0 ;;
      keyInvalid|keyExpired|API_KEY_INVALID|API_KEY_EXPIRED|accessNotConfigured|SERVICE_DISABLED|ipRefererBlocked|API_KEY_SERVICE_BLOCKED|API_KEY_IP_ADDRESS_BLOCKED|API_KEY_HTTP_REFERRER_BLOCKED|API_KEY_ANDROID_APP_BLOCKED|API_KEY_IOS_APP_BLOCKED)
        BROKEN+=("$i"); note "$(label "$i") is unusable ($reason), trying the next key"
        CURRENT=$((CURRENT + 1)); tries=0 ;;
      rateLimitExceeded|userRateLimitExceeded|RATE_LIMIT_EXCEEDED)
        if (( tries < RATE_LIMIT_RETRIES )); then
          tries=$((tries + 1)); sleep $((2 ** tries))
        else
          die "HTTP $status $reason: ${message:-rate limited}" 1
        fi ;;
      *)
        die "HTTP $status ${reason:-error}: ${message:-$response}" 1 ;;
    esac
  done
}

paginate() {
  local resource="$1"; shift
  local max_pages=5
  if [[ "${1:-}" == "--max-pages" ]]; then
    [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "--max-pages needs a positive number"
    max_pages="$2"; shift 2
  fi
  PAGE_DIR="$(mktemp -d)"
  trap 'rm -rf "${PAGE_DIR:-}"' EXIT
  local tmp="$PAGE_DIR" token="" page=0
  while (( page < max_pages )); do
    local params=("$@")
    [[ -n "$token" ]] && params+=("pageToken=$token")
    page=$((page + 1))
    request "$resource" "${params[@]}" > "$tmp/$page.json"
    token="$(jq -r '.nextPageToken // empty' "$tmp/$page.json")"
    [[ -z "$token" ]] && break
  done
  local files=() n
  for ((n = 1; n <= page; n++)); do files+=("$tmp/$n.json"); done
  jq -s --arg next "$token" '{items: (map(.items // []) | add), pages: length, nextPageToken: (if $next == "" then null else $next end)}' "${files[@]}"
}

video_id() {
  local input="$1" id=""
  if [[ "$input" =~ ^[A-Za-z0-9_-]{11}$ ]]; then id="$input"
  elif [[ "$input" =~ [?\&]v=([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtube(-nocookie)?\.com/(shorts|embed|live|v)/([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[3]}"
  fi
  [[ -n "$id" ]] || die "no video id in: $input"
  printf '%s\n' "$id"
}

# channels.list filter for a handle, channel URL or id.
channel_filter() {
  local input="$1"
  if [[ "$input" =~ ^UC[A-Za-z0-9_-]{22}$ ]]; then echo "id=$input"
  elif [[ "$input" =~ youtube\.com/channel/(UC[A-Za-z0-9_-]{22}) ]]; then echo "id=${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtube\.com/(@[^/?#]+) ]]; then echo "forHandle=${BASH_REMATCH[1]}"
  elif [[ "$input" =~ ^@[^/?#[:space:]]+$ ]]; then echo "forHandle=$input"
  elif [[ "$input" =~ youtube\.com/user/([^/?#]+) ]]; then echo "forUsername=${BASH_REMATCH[1]}"
  else
    die "cannot resolve '$input' without a search: use a @handle, a youtube.com/channel/UC… URL or a UC… id (or search type=channel, 100 units)"
  fi
}

get_channel() {
  local filter parts="${2:-snippet,statistics,contentDetails}" body
  filter="$(channel_filter "$1")"
  body="$(request channels "part=$parts" "$filter")"
  jq -e '.items | length > 0' >/dev/null <<<"$body" || die "channel not found: $1" 1
  jq '.items[0]' <<<"$body"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  get)
    [[ $# -ge 1 ]] || die "usage: yt.sh get <resource> [param=value ...]"
    load_keys; body="$(request "$@")"; jq . <<<"$body"
    ;;
  all)
    [[ $# -ge 1 ]] || die "usage: yt.sh all <resource> [--max-pages N] [param=value ...]"
    load_keys; paginate "$@"
    ;;
  video-id)
    [[ $# -eq 1 ]] || die "usage: yt.sh video-id <url|id>"
    video_id "$1"
    ;;
  channel)
    [[ $# -ge 1 ]] || die "usage: yt.sh channel <@handle|channel URL|UC… id> [parts]"
    load_keys; get_channel "$@"
    ;;
  uploads)
    [[ $# -ge 1 ]] || die "usage: yt.sh uploads <@handle|channel URL|UC… id> [max]"
    max="${2:-10}"
    [[ "$max" =~ ^[1-9][0-9]*$ ]] || die "max must be a positive number"
    load_keys
    channel="$(get_channel "$1" contentDetails)"
    playlist="$(jq -r '.contentDetails.relatedPlaylists.uploads // empty' <<<"$channel")"
    [[ -n "$playlist" ]] || die "channel has no uploads playlist: $1" 1
    pages=$(( (max + 49) / 50 ))
    items="$(paginate playlistItems --max-pages "$pages" part=snippet,contentDetails "playlistId=$playlist" "maxResults=$(( max < 50 ? max : 50 ))")"
    jq --argjson max "$max" '.items[:$max] | map({videoId: .contentDetails.videoId, title: .snippet.title, publishedAt: (.contentDetails.videoPublishedAt // .snippet.publishedAt)})' <<<"$items"
    ;;
  keys)
    load_keys
    for i in "${!KEYS[@]}"; do
      if is_spent "$i"; then state="out of quota today"; else state="not out of quota"; fi
      printf '%s\t%s\n' "$(label "$i")" "$state"
    done
    echo "quota day: $(quota_day) (Pacific); state: $SPENT_FILE"
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    usage >&2; exit 2
    ;;
esac
