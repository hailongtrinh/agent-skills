# YouTube Data API v3: read endpoints

Base: `https://www.googleapis.com/youtube/v3/<resource>`. Every request needs
`part`. Call them with `scripts/yt.sh get <resource> part=… …`. Costs are
quota units per request (per page). Full reference:
https://developers.google.com/youtube/v3/docs

## search (100 units)

Finds videos, channels or playlists.

- **Filter by type:** `type=video|channel|playlist` (comma list allowed).
  Several filters below need `type=video`.
- **Query:** `q` supports `-word` to exclude and `a|b` for OR.
- **Order:** `order=relevance|date|viewCount|rating|title|videoCount`.
- **Date range:** `publishedAfter` and `publishedBefore` (RFC 3339).
- **Scope:** `channelId`, `regionCode` (ISO 3166-1), `relevanceLanguage`
  (ISO 639-1).
- **Video filters (need `type=video`):**
  - `videoDuration=short|medium|long`. Short is under 4 minutes, medium is
    4–20 minutes, long is over 20 minutes.
  - `videoCategoryId`
  - `eventType=live|upcoming|completed`
  - `videoDefinition=high`
  - `videoCaption=closedCaption`
- **Paging:** `maxResults` 0–50 (default 5), `pageToken`.
- **Part:** `part=snippet`. Results only carry ids and a snippet. Get
  statistics with a follow-up `videos` call: 1 unit for up to 50 ids.
- **Result id:** `id.videoId`, `id.channelId` or `id.playlistId`, depending on
  `id.kind`.

## videos (1 unit)

- Filter: `id=a,b,…` (up to 50), or `chart=mostPopular` with `regionCode` and
  an optional `videoCategoryId`.
- Parts:
  - `snippet`: title, description, tags, channelId, channelTitle,
    publishedAt, thumbnails, categoryId, defaultAudioLanguage, liveBroadcastContent
  - `statistics`: viewCount, likeCount, commentCount (strings; can be missing)
  - `contentDetails`: duration (ISO 8601), definition, caption, licensedContent,
    regionRestriction
  - `status`: privacyStatus, embeddable, madeForKids
  - `topicDetails`: topicCategories (Wikipedia URLs)
  - `liveStreamingDetails`: actualStartTime, concurrentViewers (live only)
  - `player`: embedHtml
  - `localizations`
- `maxResults` and `pageToken` apply to `chart` only.

## channels (1 unit)

- Filter (exactly one):
  - `id=UC…,UC…` (up to 50)
  - `forHandle=@name`
  - `forUsername=legacyName`
- Parts:
  - `snippet`: title, description, customUrl, publishedAt, country, thumbnails
  - `statistics`: viewCount, subscriberCount (3 significant figures), hiddenSubscriberCount, videoCount
  - `contentDetails.relatedPlaylists.uploads`: the uploads playlist, which lists all public videos
  - `brandingSettings`: keywords, banner
  - `topicDetails`
  - `status`: madeForKids, isLinked

## playlists (1 unit)

- Filter: `channelId=UC…` or `id=PL…,…`.
- Parts: `snippet`, `contentDetails` (itemCount), `status`.
- Paging: `maxResults` 0–50, `pageToken`.

## playlistItems (1 unit)

- `playlistId=PL…` or `UU…`. The uploads playlist id is the channel id with
  `UC` replaced by `UU`. The reliable way is `contentDetails.relatedPlaylists.uploads`.
- Parts:
  - `snippet`: title, position, publishedAt (when added)
  - `contentDetails`: videoId, videoPublishedAt
  - `status`: privacyStatus
- Paging: `maxResults` 0–50, `pageToken`. Uploads come newest first.

## commentThreads (1 unit)

- Filter: `videoId=…`, or `allThreadsRelatedToChannelId=UC…` (comments on all
  of the channel's videos).
- Parts:
  - `snippet`: topLevelComment.snippet (authorDisplayName, textDisplay,
    textOriginal, likeCount, publishedAt), totalReplyCount
  - `replies`: up to 5 replies. Get all of them with `comments`.
- Options:
  - `order=time|relevance`
  - `searchTerms=…`
  - `textFormat=plainText|html` (default html)
  - `maxResults` 1–100
  - `pageToken`
- 403 `commentsDisabled` when comments are off.

## comments (1 unit)

- `parentId=<top-level comment id>` lists all replies to a thread.
  `id=a,b,…` reads specific comments.
- `part=snippet`, `textFormat`, `maxResults` 1–100, `pageToken`.

## videoCategories (1 unit)

- `regionCode=VN` or `id=…`, with `part=snippet`. Only categories with
  `snippet.assignable: true` are used for uploads.

Usual ids: 1 Film & Animation, 2 Autos & Vehicles, 10 Music, 15 Pets &
Animals, 17 Sports, 19 Travel & Events, 20 Gaming, 22 People & Blogs, 23
Comedy, 24 Entertainment, 25 News & Politics, 26 Howto & Style, 27 Education,
28 Science & Technology, 29 Nonprofits & Activism.

## i18nRegions / i18nLanguages (1 unit)

`part=snippet`. Lists the valid `regionCode` / `hl` values.

## Not available with an API key

- Uploading, updating, deleting, rating, commenting, subscribing: these need
  OAuth 2.0 user consent.
- Private or unlisted data. `myRating`, `mine=true` and `forMine` need OAuth.
- YouTube Analytics and Reporting APIs (watch time, revenue, demographics):
  these are separate APIs that need OAuth.
- Caption tracks: `captions.download` needs OAuth from the owner.
- Video or audio download: not part of the API, and against YouTube's Terms of
  Service.
