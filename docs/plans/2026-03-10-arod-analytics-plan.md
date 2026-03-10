# Arod Analytics Dashboard Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the /action analytics dashboard with time windows, traffic classification (browsers/AI crawlers/bots/feed readers), Bushel content popularity, feed subscriber tracking, referrer analysis, and attack probe categorisation.

**Architecture:** Server-side rendered HTML with `?range=` query param for time windows. All classification logic in OCaml (UA pattern matching, path parsing, referrer domain extraction). SQL queries parameterised with `WHERE 1=1 {time_clause}` pattern already used in `arod_stats.ml`. No new dependencies.

**Tech Stack:** OCaml, Htmlit, Sqlite3_eio, Ezjsonm. Existing libraries only.

---

### Task 1: Add Time Range Support to Dashboard

Port the `time_range` / `time_clause` pattern from `arod_stats.ml` into `arod_handlers_stats.ml`, and thread range through all existing queries.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:1-60` (query helpers)
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:59-221` (all data queries)
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:623-660` (overview_cards, traffic_section)
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:864-934` (render_dashboard signature)
- Modify: `avsm/arod/lib_handlers/arod_handlers.ml:1014-1035` (route handlers)

**Step 1: Add time_range type and helper**

At the top of `arod_handlers_stats.ml` (after the `open Htmlit`), add:

```ocaml
type time_range = Last_days of int | All

let time_clause = function
  | All -> ""
  | Last_days d ->
    Printf.sprintf " AND timestamp >= (strftime('%%s','now') - %d)" (d * 86400)

let range_of_string = function
  | "30d" -> Last_days 30
  | "6m" -> Last_days 180
  | "all" -> All
  | _ -> Last_days 7  (* default *)

let range_to_string = function
  | Last_days 7 -> "7d"
  | Last_days 30 -> "30d"
  | Last_days 180 -> "6m"
  | All -> "all"
  | Last_days d -> string_of_int d ^ "d"

let range_label = function
  | Last_days 7 -> "7 Days"
  | Last_days 30 -> "30 Days"
  | Last_days 180 -> "6 Months"
  | All -> "All Time"
  | Last_days d -> string_of_int d ^ " Days"

let all_ranges = [Last_days 7; Last_days 30; Last_days 180; All]
```

**Step 2: Update all existing query functions to accept `range`**

Every query that currently has a hardcoded time filter or no filter needs a `range` parameter. Pattern: change `"SELECT ... FROM requests"` to `Printf.sprintf "SELECT ... FROM requests WHERE 1=1%s" (time_clause range)`. For queries that already have a WHERE clause, append the time_clause.

Specific changes:
- `total_requests db` → `total_requests db range` — add `WHERE 1=1%s`
- `total_requests_24h` — remove (replaced by time-windowed total)
- `avg_response_time db` → `avg_response_time db range` — add `WHERE 1=1%s`
- `cache_hit_rate db` → `cache_hit_rate db range` — add time clause to both sub-queries
- `error_rate db` → `error_rate db range` — add time clause to both sub-queries
- `total_bandwidth db` → `total_bandwidth db range` — add `WHERE 1=1%s`
- `status_breakdown db` → `status_breakdown db range` — add `WHERE 1=1%s`
- `traffic_per_hour db` → `traffic_per_hour db range` — replace hardcoded 172800 with range-appropriate bucket:
  - `Last_days 7` → hourly, last 168 hours
  - `Last_days 30` → 6-hourly grouping
  - `Last_days 180` / `All` → daily grouping
- `top_pages_cache_rate db` → `top_pages_cache_rate db range`
- `latency_percentiles db` → `latency_percentiles db range`
- `latency_histogram db` → `latency_histogram db range`
- `top_referers db` → `top_referers db range`
- `top_user_agents db` → `top_user_agents db range`
- `cache_breakdown db` → `cache_breakdown db range`
- `cache_rate_per_hour db` → `cache_rate_per_hour db range` — adapt bucket size like traffic_per_hour

For `traffic_per_hour`, the adaptive bucketing:

```ocaml
let traffic_over_time db range =
  let fmt, limit = match range with
    | Last_days d when d <= 7 ->
      "'%Y-%m-%d %H:00'", d * 24
    | Last_days d when d <= 30 ->
      (* 6-hour blocks *)
      "'%Y-%m-%d ' || printf('%02d', (CAST(strftime('%H', timestamp, 'unixepoch') AS INTEGER) / 6) * 6) || ':00'",
      d * 4
    | _ ->
      "'%Y-%m-%d'", 366
  in
  query_string_int db
    (Printf.sprintf
       {|SELECT strftime(%s, timestamp, 'unixepoch') AS bucket,
                COUNT(*) AS cnt
         FROM requests WHERE 1=1%s
         GROUP BY bucket ORDER BY bucket ASC LIMIT %d|}
       fmt (time_clause range) limit)
```

**Step 3: Update `render_dashboard` signature**

Change from `render_dashboard db` to `render_dashboard db range`. Thread `range` through to all section rendering functions: `overview_cards db range`, `traffic_section db range`, etc.

**Step 4: Update route handler to parse `?range=` query param**

In `arod_handlers.ml:1014-1020`, change:

```ocaml
(* Before *)
let html = Arod_handlers_stats.render_dashboard db in

(* After *)
let range_s = match R.query_param rctx "range" with
  | Some s -> s | None -> "7d" in
let range = Arod_handlers_stats.range_of_string range_s in
let html = Arod_handlers_stats.render_dashboard db range in
```

Also update the three API endpoints similarly.

**Step 5: Add time window tabs to the dashboard HTML**

In `render_dashboard`, before the overview cards, add tab navigation:

```ocaml
let time_tabs range =
  let tab r =
    let active = range_to_string range = range_to_string r in
    El.a ~at:[
      At.href (Printf.sprintf "/action?range=%s" (range_to_string r));
      At.class' (if active then "tab tab-active" else "tab");
    ] [El.txt (range_label r)]
  in
  El.div ~at:[At.class' "tabs"] (List.map tab all_ranges)
```

Add corresponding CSS for `.tabs` and `.tab` / `.tab-active`.

**Step 6: Build and verify**

Run: `dune build @check 2>&1 | head -40`
Expected: clean build (no errors)

**Step 7: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml avsm/arod/lib_handlers/arod_handlers.ml
git commit -m "arod analytics: add time range support with tab navigation"
```

---

### Task 2: Multi-Window Overview Comparison Table

Replace the single-value overview cards with a comparison table showing all 4 time windows simultaneously.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:623-650` (overview_cards function)

**Step 1: Rewrite `overview_cards` to show all windows**

Replace the existing `overview_cards db` function:

```ocaml
let overview_comparison db active_range =
  let metrics = List.map (fun range ->
    let total = total_requests db range in
    let avg_lat = avg_response_time db range in
    let cache_rate = cache_hit_rate db range in
    let err_rate = error_rate db range in
    let bw = total_bandwidth db range in
    (range, total, avg_lat, cache_rate, err_rate, bw)
  ) all_ranges in
  let header = El.v "tr" ~at:[] (
    El.v "th" ~at:[] [El.txt "Metric"] ::
    List.map (fun (range, _, _, _, _, _) ->
      let cls = if range_to_string range = range_to_string active_range
                then "num active-col" else "num" in
      El.v "th" ~at:[At.class' cls] [El.txt (range_label range)]
    ) metrics
  ) in
  let row label f =
    El.v "tr" ~at:[] (
      El.v "td" ~at:[At.class' "metric-label"] [El.txt label] ::
      List.map (fun m ->
        let range, _, _, _, _, _ = m in
        let cls = if range_to_string range = range_to_string active_range
                  then "num active-col" else "num" in
        El.v "td" ~at:[At.class' cls] [El.txt (f m)]
      ) metrics
    )
  in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Overview"];
    El.div ~at:[At.class' "chart-container"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [header];
        El.v "tbody" ~at:[] [
          row "Requests" (fun (_, total, _, _, _, _) -> format_number total);
          row "Avg Latency" (fun (_, _, avg, _, _, _) ->
            human_duration_us (Float.to_int avg));
          row "Cache Rate" (fun (_, _, _, cr, _, _) -> Printf.sprintf "%.1f%%" cr);
          row "Error Rate" (fun (_, _, _, _, er, _) -> Printf.sprintf "%.1f%%" er);
          row "Bandwidth" (fun (_, _, _, _, _, bw) -> human_bytes bw);
        ]
      ]
    ]
  ]
```

Add CSS for `.active-col` (subtle highlight background) and `.metric-label` (bold).

**Step 2: Update `render_dashboard` to call new function**

Replace `overview_cards db` with `overview_comparison db range`.

**Step 3: Update `overview_json` to accept range**

```ocaml
let overview_json db range = ...
```

**Step 4: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 5: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: multi-window overview comparison table"
```

---

### Task 3: Traffic Classification by User-Agent

Add UA-based request classification into categories: browsers, feed readers, AI crawlers, SEO crawlers, search engines, link previews, security scanners, programmatic, unknown.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml` (add classification queries + rendering)

**Step 1: Define UA classification patterns**

Add after the time_range definitions:

```ocaml
(* UA classification — order matters: first match wins *)
let ua_categories = [
  "Feed readers", [
    "Feedly"; "Feedbin"; "NetNewsWire"; "Newsboat"; "FreshRSS"; "Miniflux";
    "Tiny Tiny RSS"; "Inoreader"; "NewsBlur"; "Blogtrottr"; "FrostySoftStort";
    "BuobeBot"; "BuobeFeedDiscovery";
  ];
  "AI crawlers", [
    "ChatGPT-User"; "ClaudeBot"; "Aranet-SearchBot"; "Amazonbot";
    "meta-externalagent"; "GPTBot"; "Bytespider"; "Applebot-Extended";
    "PerplexityBot"; "Cohere-AI"; "anthropic-ai"; "Google-Extended";
  ];
  "SEO crawlers", [
    "AhrefsBot"; "AhrefsSiteAudit"; "SemrushBot"; "Barkrowler"; "BuobeBot";
    "MJ12bot"; "DotBot";
  ];
  "Search engines", [
    "Googlebot"; "GoogleOther"; "bingbot"; "YandexBot"; "Baiduspider";
    "DuckDuckBot";
  ];
  "Link previews", [
    "Slackbot"; "matrix-hookshot"; "Twitterbot"; "WhatsApp"; "TelegramBot";
    "LinkedInBot"; "Discordbot";
  ];
  "Security scanners", [
    "CensysInspect"; "l9explore"; "NetScope"; "fhms-its-research-scanner";
    "Shadowserver"; "security research scanner";
  ];
  "Programmatic", [
    "curl/"; "python-requests"; "python-httpx"; "Go-http-client";
    "ocaml-cohttp"; "Java/"; "Ruby"; "PHP/";
  ];
]
```

**Step 2: Build SQL CASE expression from patterns**

```ocaml
let ua_classify_sql =
  let cases = List.map (fun (category, patterns) ->
    let conditions = List.map (fun pat ->
      Printf.sprintf "user_agent LIKE '%%%s%%'" pat
    ) patterns in
    Printf.sprintf "WHEN %s THEN '%s'"
      (String.concat " OR " conditions) category
  ) ua_categories in
  Printf.sprintf
    {|CASE
        %s
        WHEN user_agent IS NULL OR user_agent = '' THEN 'Unknown'
        ELSE 'Browsers'
      END|}
    (String.concat "\n        " cases)

let traffic_classification db range =
  let stmt = Sqlite3_eio.prepare db
    (Printf.sprintf
       {|SELECT %s AS category,
                COUNT(*) AS cnt,
                COALESCE(SUM(response_body_size), 0) AS bw
         FROM requests WHERE 1=1%s
         GROUP BY category ORDER BY cnt DESC|}
       ua_classify_sql (time_clause range)) in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let cat = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let cnt = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let bw = match row.(2) with
      | Sqlite3.Data.FLOAT f -> f | Sqlite3.Data.INT i -> Int64.to_float i | _ -> 0.0 in
    (cat, cnt, bw) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows
```

**Step 3: Add rendering function**

```ocaml
let category_color = function
  | "Browsers" -> "#3b82f6"
  | "Feed readers" -> "#22c55e"
  | "AI crawlers" -> "#f59e0b"
  | "SEO crawlers" -> "#ef4444"
  | "Search engines" -> "#8b5cf6"
  | "Link previews" -> "#06b6d4"
  | "Security scanners" -> "#dc2626"
  | "Programmatic" -> "#6b7280"
  | _ -> "#9ca3af"

let traffic_classification_section db range =
  let data = traffic_classification db range in
  let total = List.fold_left (fun acc (_, cnt, _) -> acc + cnt) 0 data in
  let bars = List.map (fun (cat, cnt, _) ->
    (cat, cnt, category_color cat)
  ) data in
  let rows = List.map (fun (cat, cnt, bw) ->
    let pct = if total > 0 then float_of_int cnt /. float_of_int total *. 100.0
              else 0.0 in
    El.v "tr" ~at:[] [
      El.v "td" ~at:[] [
        El.span ~at:[At.style (Printf.sprintf
          "display:inline-block;width:10px;height:10px;border-radius:50%%;background:%s;margin-right:0.5rem"
          (category_color cat))] [];
        El.txt cat];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt (Printf.sprintf "%.1f%%" pct)];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_bytes bw)];
    ]
  ) data in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Traffic Classification"];
    El.div ~at:[At.class' "chart-container"] [
      svg_horizontal_bars ~width:600
        ~height:(max 80 (List.length bars * 36)) ~bars ();
    ];
    El.div ~at:[At.class' "chart-container"; At.style "margin-top:1rem"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [El.v "tr" ~at:[] [
          El.v "th" ~at:[] [El.txt "Category"];
          El.v "th" ~at:[At.class' "num"] [El.txt "Requests"];
          El.v "th" ~at:[At.class' "num"] [El.txt "%"];
          El.v "th" ~at:[At.class' "num"] [El.txt "Bandwidth"];
        ]];
        El.v "tbody" ~at:[] rows
      ]
    ]
  ]
```

**Step 4: Wire into `render_dashboard`**

Add `traffic_classification_section db range` after the overview comparison.

**Step 5: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 6: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: traffic classification by user-agent category"
```

---

### Task 4: Feed Subscribers Section

Track feed health: subscriber counts, unique readers, poll activity per feed.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml`

**Step 1: Add feed query functions**

```ocaml
let feed_paths = ["/news.xml"; "/perma.xml"; "/perma.json"; "/feed.json";
                  "/notes/atom.xml"]

let feed_overview db range =
  let paths_sql = String.concat "," (List.map (Printf.sprintf "'%s'") feed_paths) in
  let stmt = Sqlite3_eio.prepare db
    (Printf.sprintf
       {|SELECT path, COUNT(*) AS cnt, COUNT(DISTINCT user_agent) AS unique_uas
         FROM requests WHERE path IN (%s)%s
         GROUP BY path ORDER BY cnt DESC|}
       paths_sql (time_clause range)) in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let path = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let cnt = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let uas = match row.(2) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    (path, cnt, uas) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

let feed_top_readers db range =
  let paths_sql = String.concat "," (List.map (Printf.sprintf "'%s'") feed_paths) in
  query_string_int db
    (Printf.sprintf
       {|SELECT COALESCE(user_agent, '(none)') AS ua, COUNT(*) AS cnt
         FROM requests WHERE path IN (%s)%s
         GROUP BY ua ORDER BY cnt DESC LIMIT 15|}
       paths_sql (time_clause range))
```

**Step 2: Add subscriber count parser**

Parse subscriber counts from UA strings (Feedly, Feedbin, Inoreader, NewsBlur embed them):

```ocaml
let parse_subscriber_count ua =
  (* Look for patterns like "N subscribers" or "feed-id:X - N subscribers" *)
  let re_subscribers = Re.(compile (seq [
    group (rep1 digit); char ' '; str "subscriber"
  ])) in
  match Re.exec_opt re_subscribers ua with
  | Some g -> (try Some (int_of_string (Re.Group.get g 1)) with _ -> None)
  | None -> None

let simplify_feed_reader ua =
  (* Extract a readable name from feed reader UA *)
  if String.length ua > 0 then
    let known = [
      "Feedly", "Feedly"; "Feedbin", "Feedbin"; "NetNewsWire", "NetNewsWire";
      "Newsboat", "Newsboat"; "FreshRSS", "FreshRSS"; "Miniflux", "Miniflux";
      "Tiny Tiny RSS", "Tiny Tiny RSS"; "Inoreader", "Inoreader";
      "NewsBlur", "NewsBlur"; "Blogtrottr", "Blogtrottr";
      "FrostySoftStort", "FrostySoftStort"; "matrix-hookshot", "Matrix";
      "Slackbot", "Slack";
    ] in
    match List.find_opt (fun (pat, _) ->
      try let _ = Arod_util.substr_index ua pat in true
      with Not_found -> false
    ) known with
    | Some (_, name) -> name
    | None ->
      (* Truncate long UAs *)
      if String.length ua > 50 then String.sub ua 0 50 ^ "..." else ua
  else "(none)"
```

Note: Check whether `Re` is available as a dependency. If not, use a simple `String`-based scanner instead:

```ocaml
(* Fallback without Re: scan for " N subscribers" *)
let parse_subscriber_count ua =
  match String.split_on_char ' ' ua with
  | parts ->
    let rec find = function
      | n :: s :: _ when String.starts_with ~prefix:"subscriber" s ->
        (try Some (int_of_string n) with _ -> None)
      | _ :: rest -> find rest
      | [] -> None
    in
    find parts
```

Use the `String`-based version to avoid adding a `Re` dependency.

**Step 3: Add feed subscribers rendering**

```ocaml
let feed_section db range =
  let overview = feed_overview db range in
  let readers = feed_top_readers db range in
  (* Estimate total subscribers from UAs with subscriber counts *)
  let total_subs = List.fold_left (fun acc (ua, _cnt) ->
    match parse_subscriber_count ua with
    | Some n -> acc + n
    | None -> acc
  ) 0 readers in
  let overview_rows = List.map (fun (path, cnt, uas) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[] [El.txt path];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt (string_of_int uas)];
    ]
  ) overview in
  let reader_rows = List.map (fun (ua, cnt) ->
    let name = simplify_feed_reader ua in
    let subs = match parse_subscriber_count ua with
      | Some n -> string_of_int n
      | None -> "-" in
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.v "title" ua] [El.txt name];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt subs];
    ]
  ) readers in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [
      El.txt "Feed Subscribers";
      (if total_subs > 0 then
         El.span ~at:[At.class' "text-sm opacity-50"; At.style "margin-left:0.5rem"]
           [El.txt (Printf.sprintf "(~%d known subscribers)" total_subs)]
       else El.void);
    ];
    El.div ~at:[At.class' "stats-two-col"] [
      El.div ~at:[At.class' "chart-container"] [
        El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"]
          [El.txt "Feed Endpoints"];
        El.table ~at:[At.class' "stats-table"] [
          El.v "thead" ~at:[] [El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "Feed"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Polls"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Unique UAs"];
          ]];
          El.v "tbody" ~at:[] overview_rows;
        ]
      ];
      El.div ~at:[At.class' "chart-container"] [
        El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"]
          [El.txt "Top Readers"];
        El.table ~at:[At.class' "stats-table"] [
          El.v "thead" ~at:[] [El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "Reader"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Polls"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Subs"];
          ]];
          El.v "tbody" ~at:[] reader_rows;
        ]
      ];
    ]
  ]
```

**Step 4: Wire into render_dashboard**

Add `feed_section db range` after traffic classification.

**Step 5: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 6: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: feed subscriber tracking with reader breakdown"
```

---

### Task 5: Popular Content by Bushel Type

Parse paths to show top notes and papers by popularity.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml`

**Step 1: Add content popularity queries**

```ocaml
let top_content_by_type db range content_type n =
  (* content_type is "notes", "papers", "projects", "ideas", "videos" *)
  let prefix = "/" ^ content_type ^ "/%" in
  let exact = "/" ^ content_type in
  let stmt = Sqlite3_eio.prepare db
    (Printf.sprintf
       {|SELECT path,
                COUNT(*) AS cnt,
                COUNT(DISTINCT referer) AS unique_refs,
                COALESCE(SUM(response_body_size), 0) AS bw,
                AVG(duration_us) AS avg_us
         FROM requests
         WHERE path LIKE '%s' AND path != '%s'
           AND status_code = 200%s
         GROUP BY path ORDER BY cnt DESC LIMIT %d|}
       prefix exact (time_clause range) n) in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let path = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let cnt = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let refs = match row.(2) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let bw = match row.(3) with
      | Sqlite3.Data.FLOAT f -> f | Sqlite3.Data.INT i -> Int64.to_float i | _ -> 0.0 in
    let avg = match row.(4) with
      | Sqlite3.Data.FLOAT f -> f | Sqlite3.Data.INT i -> Int64.to_float i | _ -> 0.0 in
    (path, cnt, refs, bw, avg) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows
```

**Step 2: Add rendering**

```ocaml
let slug_of_path path =
  (* "/notes/foo-bar" -> "foo-bar" *)
  match String.split_on_char '/' path with
  | "" :: _ :: slug :: _ -> slug
  | _ -> path

let content_table ~title data =
  let rows = List.map (fun (path, cnt, refs, bw, avg) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" path]
        [El.txt (slug_of_path path)];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt (string_of_int refs)];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_bytes bw)];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_duration_us (Float.to_int avg))];
    ]
  ) data in
  El.div ~at:[At.class' "chart-container"] [
    El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"] [El.txt title];
    El.table ~at:[At.class' "stats-table"] [
      El.v "thead" ~at:[] [El.v "tr" ~at:[] [
        El.v "th" ~at:[] [El.txt "Slug"];
        El.v "th" ~at:[At.class' "num"] [El.txt "Hits"];
        El.v "th" ~at:[At.class' "num"] [El.txt "Referrers"];
        El.v "th" ~at:[At.class' "num"] [El.txt "Bandwidth"];
        El.v "th" ~at:[At.class' "num"] [El.txt "Avg Latency"];
      ]];
      El.v "tbody" ~at:[] rows
    ]
  ]

let popular_content_section db range =
  let notes = top_content_by_type db range "notes" 15 in
  let papers = top_content_by_type db range "papers" 10 in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Popular Content"];
    content_table ~title:"Top Notes" notes;
    El.div ~at:[At.style "margin-top:1rem"] [
      content_table ~title:"Top Papers" papers;
    ];
  ]
```

**Step 3: Wire into render_dashboard**

Add `popular_content_section db range` after feed section.

**Step 4: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 5: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: popular content by Bushel type (notes, papers)"
```

---

### Task 6: Referrer Analysis with Domain Classification

Classify referrers by domain category instead of showing raw URLs.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml`

**Step 1: Add referrer classification**

```ocaml
let referrer_categories = [
  "Search", ["google.com"; "bing.com"; "kagi.com"; "duckduckgo.com";
             "search.yahoo.com"; "ecosia.org"; "baidu.com"; "yandex."];
  "Social", ["lobste.rs"; "linkedin.com"; "t.co"; "reddit.com"; "bsky.app";
             "mastodon."; "twitter.com"; "x.com"; "threads.net"];
  "Aggregators", ["news.ycombinator.com"; "pckt.blog"; "blogtrottr.com";
                   "hacker-news.firebaseio.com"];
  "Self", ["anil.recoil.org"];
]

let classify_referrer ref_url =
  (* Extract domain from URL *)
  let domain = match String.split_on_char '/' ref_url with
    | _ :: "" :: host :: _ ->
      (* Strip port *)
      (match String.split_on_char ':' host with h :: _ -> h | [] -> host)
    | _ -> ref_url
  in
  let domain = String.lowercase_ascii domain in
  match List.find_opt (fun (_, domains) ->
    List.exists (fun d ->
      String.ends_with ~suffix:d domain || String.equal d domain
    ) domains
  ) referrer_categories with
  | Some (cat, _) -> cat
  | None -> "Other"

let referrer_analysis db range =
  let refs = top_referers db range in
  (* refs is (referer_url, count) list — reclassify by domain category *)
  let by_cat = Hashtbl.create 8 in
  List.iter (fun (ref_url, cnt) ->
    let cat = classify_referrer ref_url in
    let prev = try Hashtbl.find by_cat cat with Not_found -> (0, []) in
    let total, items = prev in
    Hashtbl.replace by_cat cat (total + cnt, (ref_url, cnt) :: items)
  ) refs;
  (* Sort categories by total *)
  let cats = Hashtbl.fold (fun cat (total, items) acc ->
    (cat, total, List.sort (fun (_, a) (_, b) -> compare b a) items) :: acc
  ) by_cat [] in
  List.sort (fun (_, a, _) (_, b, _) -> compare b a) cats
```

Note: The existing `top_referers` only returns top 10. We need a bigger limit for proper classification. Change the query to return more (top 50) or write a new one:

```ocaml
let all_referers db range =
  query_string_int db
    (Printf.sprintf
       {|SELECT COALESCE(referer, '(direct)') AS ref, COUNT(*) AS cnt
         FROM requests WHERE referer IS NOT NULL AND referer <> ''%s
         GROUP BY ref ORDER BY cnt DESC LIMIT 50|}
       (time_clause range))
```

**Step 2: Render referrer analysis**

```ocaml
let referrer_section db range =
  let refs = all_referers db range in
  let cats = referrer_analysis_of refs in  (* factor out the classification *)
  let total_referred = List.fold_left (fun acc (_, t, _) -> acc + t) 0 cats in
  let rows = List.concat_map (fun (cat, total, top_items) ->
    let pct = if total_referred > 0
              then float_of_int total /. float_of_int total_referred *. 100.0
              else 0.0 in
    let cat_row = El.v "tr" ~at:[At.style "font-weight:600"] [
      El.v "td" ~at:[] [El.txt cat];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number total)];
      El.v "td" ~at:[At.class' "num"] [El.txt (Printf.sprintf "%.1f%%" pct)];
    ] in
    (* Show top 3 individual referrers for "Other" and "Social" *)
    let detail = if cat = "Self" then [] else
      List.filteri (fun i _ -> i < 3) top_items
      |> List.map (fun (url, cnt) ->
        let short = if String.length url > 60
                    then String.sub url 0 60 ^ "..." else url in
        El.v "tr" ~at:[At.style "opacity:0.7"] [
          El.v "td" ~at:[At.style "padding-left:1.5rem"] [El.txt short];
          El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
          El.v "td" ~at:[] [];
        ])
    in
    cat_row :: detail
  ) cats in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Referrer Analysis"];
    El.div ~at:[At.class' "chart-container"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [El.v "tr" ~at:[] [
          El.v "th" ~at:[] [El.txt "Source"];
          El.v "th" ~at:[At.class' "num"] [El.txt "Visits"];
          El.v "th" ~at:[At.class' "num"] [El.txt "%"];
        ]];
        El.v "tbody" ~at:[] rows
      ]
    ]
  ]
```

**Step 3: Replace old `referers_section` and `user_agents_section` in render_dashboard**

Remove the calls to `referers_section db` and `user_agents_section db`. Replace with `referrer_section db range`.

**Step 4: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 5: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: referrer analysis with domain classification"
```

---

### Task 7: Error Section with Attack Probe Categorisation

Split errors into attack probes vs legitimate 404s. Always show last 7 days regardless of selected time range.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml`

**Step 1: Define attack probe patterns**

```ocaml
(* Path patterns that indicate attack/scanning probes *)
let attack_path_patterns = [
  (* WordPress *)
  "/wp-"; "/wp-login"; "/wp-admin"; "/xmlrpc.php";
  (* Config/secrets *)
  "/.env"; "/.git/"; "/config.json"; "/.aws"; "/.ssh";
  (* Java/enterprise *)
  "/actuator/"; "/geoserver/"; "/solr/"; "/struts";
  (* PHP/admin *)
  "/cgi-bin/"; "/boaform/"; "/SDK/"; "/admin/";
  "/phpmyadmin"; "/myadmin";
  (* Path traversal *)
  "..%2F"; "..%252F"; "../";
  (* Misc probes *)
  "/backup/"; "/bin/"; "/bins/"; "/LIFE";
  "/login"; "/console"; "/debug"; "/_next/server";
]

let is_connect_probe path =
  (* CONNECT-style probes: "host:port" or "http://..." *)
  (try let _ = String.index path ':' in
       not (String.starts_with ~prefix:"/" path)
   with Not_found -> false)
  || String.starts_with ~prefix:"http://" path

let is_random_hash path =
  (* Random hex/alphanum paths like "/3mgam2r44as2v" *)
  String.length path > 10 &&
  String.get path 0 = '/' &&
  let s = String.sub path 1 (String.length path - 1) in
  String.for_all (fun c ->
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')
  ) s

let is_attack_probe path =
  is_connect_probe path ||
  is_random_hash path ||
  List.exists (fun pat ->
    try let _ = Arod_util.substr_index path pat in true
    with Not_found -> false
  ) attack_path_patterns
```

Note: For `substr_index`, check if an existing utility is available. If not, use a simple `String.starts_with` + manual scan, or just use `String` functions:

```ocaml
let contains_substr s sub =
  let slen = String.length s and sublen = String.length sub in
  if sublen > slen then false
  else
    let rec check i =
      if i > slen - sublen then false
      else if String.sub s i sublen = sub then true
      else check (i + 1)
    in
    check 0

let is_attack_probe path =
  is_connect_probe path ||
  is_random_hash path ||
  List.exists (fun pat -> contains_substr path pat) attack_path_patterns
```

**Step 2: Query recent errors and classify**

```ocaml
let recent_errors db =
  (* Always last 7 days, regardless of selected range *)
  let range = Last_days 7 in
  query_string_int db
    (Printf.sprintf
       {|SELECT path, COUNT(*) AS cnt
         FROM requests WHERE status_code >= 400%s
         GROUP BY path ORDER BY cnt DESC LIMIT 200|}
       (time_clause range))

let recent_errors_with_referrer db =
  let range = Last_days 7 in
  let stmt = Sqlite3_eio.prepare db
    (Printf.sprintf
       {|SELECT path, COUNT(*) AS cnt,
                (SELECT referer FROM requests r2
                 WHERE r2.path = requests.path AND r2.referer IS NOT NULL
                   AND r2.referer <> '' AND r2.status_code >= 400
                 ORDER BY r2.timestamp DESC LIMIT 1) AS top_ref
         FROM requests WHERE status_code >= 400%s
         GROUP BY path ORDER BY cnt DESC LIMIT 200|}
       (time_clause range)) in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let path = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let cnt = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let ref_url = match row.(2) with Sqlite3.Data.TEXT s -> Some s | _ -> None in
    (path, cnt, ref_url) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows
```

**Step 3: Render errors section**

```ocaml
let errors_section db =
  let errors = recent_errors_with_referrer db in
  let attacks, legit = List.partition (fun (path, _, _) ->
    is_attack_probe path
  ) errors in
  let attack_total = List.fold_left (fun acc (_, cnt, _) -> acc + cnt) 0 attacks in
  let legit_rows = List.map (fun (path, cnt, ref_opt) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" path] [El.txt path];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "path-cell"] [
        El.txt (match ref_opt with Some r ->
          if String.length r > 50 then String.sub r 0 50 ^ "..." else r
        | None -> "-")
      ];
    ]
  ) (List.filteri (fun i _ -> i < 20) legit) in
  let top_attacks = List.filteri (fun i _ -> i < 10) attacks in
  let attack_rows = List.map (fun (path, cnt, _) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" path] [El.txt path];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
    ]
  ) top_attacks in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Errors (Last 7 Days)"];
    (* Legitimate 404s *)
    El.div ~at:[At.class' "chart-container"] [
      El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"]
        [El.txt "Legitimate 404s"];
      (if legit_rows = [] then
         El.p ~at:[At.class' "text-sm opacity-50"] [El.txt "None"]
       else
         El.table ~at:[At.class' "stats-table"] [
           El.v "thead" ~at:[] [El.v "tr" ~at:[] [
             El.v "th" ~at:[] [El.txt "Path"];
             El.v "th" ~at:[At.class' "num"] [El.txt "Count"];
             El.v "th" ~at:[] [El.txt "Referrer"];
           ]];
           El.v "tbody" ~at:[] legit_rows
         ]);
    ];
    (* Attack probes summary *)
    El.div ~at:[At.class' "chart-container"; At.style "margin-top:1rem"] [
      El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"]
        [El.txt (Printf.sprintf "Attack Probes (%s total)" (format_number attack_total))];
      (if attack_rows = [] then
         El.p ~at:[At.class' "text-sm opacity-50"] [El.txt "None"]
       else
         El.table ~at:[At.class' "stats-table"] [
           El.v "thead" ~at:[] [El.v "tr" ~at:[] [
             El.v "th" ~at:[] [El.txt "Path"];
             El.v "th" ~at:[At.class' "num"] [El.txt "Count"];
           ]];
           El.v "tbody" ~at:[] attack_rows
         ]);
    ];
  ]
```

**Step 4: Wire into render_dashboard, remove old top_pages_section if redundant**

Replace the old top pages section (which showed all-time data) with:
1. `popular_content_section db range` (from Task 5)
2. `errors_section db` (no range — always 7 days)

**Step 5: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 6: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: error section with attack probe categorisation"
```

---

### Task 8: Content Type Breakdown Section

Show response content type distribution.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml`

**Step 1: Add content type query**

```ocaml
let content_type_breakdown db range =
  query_string_int db
    (Printf.sprintf
       {|SELECT COALESCE(response_content_type, '(none)') AS ct, COUNT(*) AS cnt
         FROM requests WHERE 1=1%s
         GROUP BY ct ORDER BY cnt DESC|}
       (time_clause range))
```

**Step 2: Add rendering**

```ocaml
let content_type_section db range =
  let types = content_type_breakdown db range in
  let total = List.fold_left (fun acc (_, n) -> acc + n) 0 types in
  let simplify_ct ct =
    (* "text/html; charset=utf-8" -> "text/html" *)
    match String.split_on_char ';' ct with
    | short :: _ -> String.trim short
    | [] -> ct
  in
  let rows = List.map (fun (ct, cnt) ->
    let pct = if total > 0 then float_of_int cnt /. float_of_int total *. 100.0
              else 0.0 in
    El.v "tr" ~at:[] [
      El.v "td" ~at:[] [El.txt (simplify_ct ct)];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt (Printf.sprintf "%.1f%%" pct)];
    ]
  ) types in
  El.div ~at:[At.class' "chart-container"] [
    El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"]
      [El.txt "Response Content Types"];
    El.table ~at:[At.class' "stats-table"] [
      El.v "thead" ~at:[] [El.v "tr" ~at:[] [
        El.v "th" ~at:[] [El.txt "Type"];
        El.v "th" ~at:[At.class' "num"] [El.txt "Count"];
        El.v "th" ~at:[At.class' "num"] [El.txt "%"];
      ]];
      El.v "tbody" ~at:[] rows
    ]
  ]
```

**Step 3: Wire in — place next to status distribution in the two-col layout**

Replace the old `stats-two-col` section containing status + latency with:

```ocaml
El.div ~at:[At.class' "stats-two-col"] [
  status_section db range;
  content_type_section db range;
];
```

Keep latency section separately.

**Step 4: Build and verify**

Run: `dune build @check 2>&1 | head -40`

**Step 5: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml
git commit -m "arod analytics: content type breakdown section"
```

---

### Task 9: Assemble Final Dashboard Layout + Update JSON APIs

Reorder all sections and update the JSON API endpoints.

**Files:**
- Modify: `avsm/arod/lib_handlers/arod_handlers_stats.ml:864-974` (render_dashboard + JSON APIs)

**Step 1: Rewrite `render_dashboard`**

```ocaml
let render_dashboard db range =
  let content = El.div ~at:[At.style "max-width: 1000px; margin: 0 auto; padding: 1rem 1rem 3rem"] [
    El.style [El.unsafe_raw dashboard_css];
    El.h1 ~at:[At.class' "text-2xl font-bold mb-1"] [El.txt "Arod Analytics"];
    El.p ~at:[At.class' "text-sm opacity-50 mb-4"] [
      El.txt (Printf.sprintf "Showing: %s" (range_label range))];
    time_tabs range;
    overview_comparison db range;
    traffic_classification_section db range;
    traffic_section db range;
    feed_section db range;
    popular_content_section db range;
    El.div ~at:[At.class' "stats-two-col"] [
      status_section db range;
      content_type_section db range;
    ];
    latency_section db range;
    referrer_section db range;
    cache_section db range;
    errors_section db;
    live_activity_section db;
    El.script [El.unsafe_raw dashboard_js];
  ] in
  (* ... same head/body wrapper as before ... *)
```

**Step 2: Update JSON APIs to accept range**

```ocaml
let overview_json db range = ...  (* use range for all queries *)
let traffic_json db range = ...   (* use range *)
let recent_json db _range = ...   (* recent always real-time *)
```

**Step 3: Update route handlers**

In `arod_handlers.ml`, update all three API endpoints to parse and pass range:

```ocaml
get_h1 (lits ["action"; "api"; "overview"]) Authorization (fun () auth rctx (local_ respond) ->
  if not (check_stats_auth cfg auth) then send_auth_challenge respond
  else
    let db = Arod_log.db log in
    let range_s = match R.query_param rctx "range" with
      | Some s -> s | None -> "7d" in
    let range = Arod_handlers_stats.range_of_string range_s in
    R.json_gen rctx respond (fun () -> Arod_handlers_stats.overview_json db range));
```

(Same pattern for traffic and recent endpoints.)

**Step 4: Build full project**

Run: `dune build 2>&1 | head -40`
Expected: clean build

**Step 5: Commit**

```
git add avsm/arod/lib_handlers/arod_handlers_stats.ml avsm/arod/lib_handlers/arod_handlers.ml
git commit -m "arod analytics: assemble final dashboard layout and update APIs"
```

---

### Task 10: Final Review and Cleanup

**Step 1: Remove dead code**

Delete the old `total_requests_24h`, `top_user_agents`, and any now-unused query functions.

**Step 2: Verify no warnings**

Run: `dune build @check 2>&1 | grep -i warning`
Expected: no warnings

**Step 3: Test the dashboard**

If the server can be run locally:
Run: `dune exec avsm/arod/bin/main.exe -- serve` (or equivalent)
Visit: `http://localhost:PORT/action?range=7d`
Verify: tabs work, all sections render, switching ranges reloads correctly.

**Step 4: Final commit**

```
git add -u
git commit -m "arod analytics: cleanup unused code"
```
