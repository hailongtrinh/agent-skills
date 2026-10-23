# YouTube recipes

`Y` is `scripts/yt.sh` in this skill's folder. Each recipe notes its quota
cost.

## Channel report (about 3–6 units)

```bash
CH=$($Y channel @GoogleDevelopers)
echo "$CH" | jq '{id, title: .snippet.title, subscribers: (.statistics.subscriberCount | tonumber? // null), videos: (.statistics.videoCount | tonumber), views: (.statistics.viewCount | tonumber)}'

# Latest 50 uploads, then their stats in one call
IDS=$($Y uploads @GoogleDevelopers 50 | jq -r 'map(.videoId) | join(",")')
$Y get videos part=snippet,statistics,contentDetails id="$IDS" | jq '
  [.items[] | {
    id, title: .snippet.title, publishedAt: .snippet.publishedAt,
    duration: .contentDetails.duration,
    views: (.statistics.viewCount // "0" | tonumber),
    likes: (.statistics.likeCount // null | if . then tonumber else null end),
    comments: (.statistics.commentCount // null | if . then tonumber else null end)
  }]
  | {count: length,
     avgViews: (map(.views) | add / length | floor),
     top5: (sort_by(-.views) | .[:5] | map({title, views, url: "https://www.youtube.com/watch?v=\(.id)"}))}'
```

For more than 50 videos, split the ids into batches of 50 (`.[0:50]`,
`.[50:100]` and so on).

## Export a video's comments (1 unit per 100 threads)

```bash
VID=$($Y video-id "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
$Y all commentThreads --max-pages 10 part=snippet,replies videoId="$VID" order=time textFormat=plainText maxResults=100 \
  | jq -r '.items[] | .snippet.topLevelComment.snippet
      | [.publishedAt, .authorDisplayName, .likeCount, (.textDisplay | gsub("[\r\n]+"; " "))] | @csv' > comments.csv
```

Up to 5 replies come inline in `.replies.comments`. For full reply threads,
call `$Y all comments part=snippet parentId=<thread id> textFormat=plainText maxResults=100`.
On `commentsDisabled`, report that comments are off.

## Compare competitors (about 1 unit per channel + 2 per channel for uploads)

```bash
for h in @channelA @channelB @channelC; do
  $Y channel "$h" snippet,statistics | jq -c '{handle: "'"$h"'", id, title: .snippet.title, subs: .statistics.subscriberCount, videos: .statistics.videoCount, views: .statistics.viewCount}'
done | jq -s 'sort_by(-(.subs // "0" | tonumber))'
```

Add posting frequency: for each channel, take `uploads <handle> 20` and compute
the days between the first and the last `publishedAt`.

## Keyword research (100 units per search page)

```bash
$Y get search part=snippet type=video q="ai video editing" order=viewCount publishedAfter=2026-07-01T00:00:00Z regionCode=US maxResults=25 \
  | jq -r '.items[].id.videoId' | paste -sd, - > ids.txt
$Y get videos part=snippet,statistics id="$(cat ids.txt)" \
  | jq '[.items[] | {title: .snippet.title, channel: .snippet.channelTitle, views: (.statistics.viewCount | tonumber), tags: (.snippet.tags // [] | .[:8])}] | sort_by(-.views)'
```

Each extra search page costs 100 units. Keep it to 1–2 pages unless the user
asks for more, and say that search results are a ranked sample.

## Trending by category in Vietnam (2 units)

```bash
$Y get videoCategories part=snippet regionCode=VN | jq -r '.items[] | select(.snippet.assignable) | "\(.id)\t\(.snippet.title)"'
$Y get videos part=snippet,statistics chart=mostPopular regionCode=VN videoCategoryId=10 maxResults=20 \
  | jq '.items[] | {title: .snippet.title, channel: .snippet.channelTitle, views: .statistics.viewCount}'
```

Some categories return 404 `videoChartNotFound` for some regions. Try the chart
without a category.
