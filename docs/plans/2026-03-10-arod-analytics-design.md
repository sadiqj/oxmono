# Arod Analytics Dashboard Redesign

## Context

The `/action` stats dashboard at `arod_handlers_stats.ml` (974 lines) shows
all-time-only metrics with no time windowing, no content classification, and
no separation of attack traffic from legitimate errors. The database has 288K+
rows spanning ~23 days with rich fields (path, user_agent, referer, status,
content_type, cache_status, duration, body_size).

## Design

### 1. Time Window Tabs

Tabs at page top: **7d** (default) | **30d** | **6m** | **All**.
Implemented as `?range=7d|30d|6m|all` query param, fully server-rendered.
All sections respect the selected range except errors (always 7d) and live
activity (always real-time).

### 2. Overview Cards — Multi-Window Comparison

Instead of single-value cards, show a comparison table across all 4 windows:

| Metric       | 7d   | 30d  | 6m   | All  |
|-------------|------|------|------|------|
| Requests     |      |      |      |      |
| Bandwidth    |      |      |      |      |
| Cache rate   |      |      |      |      |
| Error rate   |      |      |      |      |
| Avg latency  |      |      |      |      |
| Req/hour avg |      |      |      |      |

5 queries × 4 windows = 20 queries, all simple indexed aggregates.

### 3. Traffic Classification by User-Agent

Classify each request into one category using UA substring matching:

| Category           | UA patterns                                                       |
|-------------------|-------------------------------------------------------------------|
| **Feed readers**   | Feedly, Feedbin, NetNewsWire, Newsboat, FreshRSS, Miniflux, TT-RSS, Inoreader, NewsBlur, Blogtrottr, FrostySoftStort |
| **AI crawlers**    | ChatGPT-User, ClaudeBot, Aranet-SearchBot, Amazonbot, meta-externalagent, GPTBot, Bytespider, Applebot-Extended, PerplexityBot |
| **SEO crawlers**   | AhrefsBot, AhrefsSiteAudit, SemrushBot, Barkrowler, BuobeBot     |
| **Search engines** | Googlebot, GoogleOther, bingbot, YandexBot, Baiduspider           |
| **Link previews**  | Slackbot, matrix-hookshot, Twitterbot, WhatsApp, TelegramBot      |
| **Security scanners** | CensysInspect, l9explore, NetScope, fhms-its-research-scanner, Shadowserver |
| **Programmatic**   | curl/, python-requests, python-httpx, Go-http-client, ocaml-cohttp |
| **Browsers**       | Real browser UAs not matching any above pattern                    |
| **Unknown**        | No UA or unrecognized                                              |

Classification runs in SQL with a CASE expression for efficiency.
Show horizontal bar chart + table with request count, bandwidth, and % of total
per category.

### 4. Feed Subscribers Section

Dedicated feed health panel:

- Per-feed path (`/news.xml`, `/perma.xml`, `/perma.json`, `/feed.json`,
  `/notes/atom.xml`): total polls, unique UAs, estimated subscribers
- Subscriber estimation: parse subscriber counts from Feedly
  (`N subscribers`), Feedbin (`feed-id:X - N subscribers`), Inoreader,
  NewsBlur UAs. Sum distinct subscriber counts.
- Top 10 feed readers table (UA name, poll count, subscribers if known)
- Feed poll frequency over time (hourly buckets)

### 5. Popular Content by Bushel Type

Parse paths to classify content:

| Prefix        | Type    |
|--------------|---------|
| `/notes/X`    | Note    |
| `/papers/X`   | Paper   |
| `/projects/X` | Project |
| `/ideas/X`    | Idea    |
| `/videos/X`   | Video   |

Two tables scoped to selected time window:

**Top 15 Notes**: slug, hits, unique referrers (COUNT DISTINCT referer),
bandwidth, avg latency.

**Top 10 Papers**: same columns.

Filter: only paths matching `/type/slug` with status 200, exclude index
pages (`/notes`, `/papers` without slug).

### 6. Referrer Analysis

Classify referrers by domain into categories:

| Category         | Domains                                           |
|-----------------|---------------------------------------------------|
| **Search**       | google.com, bing.com, kagi.com, duckduckgo.com    |
| **Social**       | lobste.rs, linkedin.com, t.co, reddit.com, bsky.app, mastodon.* |
| **Aggregators**  | news.ycombinator.com, pckt.blog, blogtrottr.com   |
| **Self**         | anil.recoil.org                                    |
| **Other**        | everything else                                    |

Table: category, count, % of referred traffic. Expand "Other" as sub-table
with top 10 individual domains.

### 7. Errors Section (Always Last 7 Days)

Two sub-sections regardless of selected time window:

**Attack probes** (single summary line + expandable detail):
Match by path pattern:
- `/wp-*`, `/wp-login.php`, `/wp-admin/*`
- `/.env*`, `/.git/*`
- `/cgi-bin/*`, `/geoserver/*`, `/actuator/*`, `/boaform/*`, `/SDK/*`
- Path traversal: `..%2F`
- CONNECT proxying: paths containing `:` port or starting with `http://`
- Random hash: paths matching `^/[a-z0-9]{10,}$`
- `/login`, `/backup/`, `/bin/`, `/bins/`, `/config.json`

Show total count and top 5 source IPs.

**Legitimate 404s**: everything else with status 404 in last 7 days.
Table: path, count, top referrer (to find broken external links).

### 8. Retained Sections (Scoped to Selected Range)

- **Traffic over time**: adapt bucket size — hourly for 7d, 6-hourly for
  30d, daily for 6m/all
- **Status distribution**: horizontal bar chart
- **Latency percentiles + histogram**: p50/p90/p95/p99 cards + bar chart
- **Cache performance**: hit/miss breakdown + hit rate over time
- **Live activity feed**: always real-time last 50 requests, auto-refreshing

### 9. Removed

- Top user agents table → replaced by traffic classification
- Top referrers table → replaced by referrer analysis

## Implementation Notes

- The `arod_stats.ml` CLI module already has `time_range` and `time_clause`
  support. Port this pattern to `arod_handlers_stats.ml`.
- UA classification: define as a list of `(category, patterns)` pairs,
  build a single SQL CASE expression. Keep the pattern list in one place
  so it's easy to update.
- Attack probe detection: same approach, list of path patterns, single
  SQL CASE or OCaml-side filtering.
- Feed subscriber parsing: OCaml-side regex on UA strings after SQL query,
  since the patterns are too varied for SQL.
- The `?range=` param needs extracting from the query string in the route
  handler. The existing handler uses `lits ["action"]` — extend to parse
  query params.

## File Changes

| File | Change |
|------|--------|
| `avsm/arod/lib_handlers/arod_handlers_stats.ml` | Major rewrite: add time range, classification queries, new sections |
| `avsm/arod/lib_handlers/arod_handlers.ml` | Parse `?range=` query param, pass to `render_dashboard` |
| `avsm/arod/lib_handlers/arod_handlers_stats.mli` | Update signature for `render_dashboard` to accept range |
