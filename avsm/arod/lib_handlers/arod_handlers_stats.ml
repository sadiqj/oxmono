(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Hidden stats dashboard at /action — not linked from any public page. *)

open Htmlit

(** {1 SQL Query Helpers} *)

let query_int db sql =
  let stmt = Sqlite3_eio.prepare db sql in
  let _rc, v = Sqlite3_eio.fold db stmt ~init:0 ~f:(fun _acc row ->
    match row.(0) with
    | Sqlite3.Data.INT i -> Int64.to_int i
    | Sqlite3.Data.FLOAT f -> Float.to_int f
    | _ -> 0
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  v

let query_float db sql =
  let stmt = Sqlite3_eio.prepare db sql in
  let _rc, v = Sqlite3_eio.fold db stmt ~init:0.0 ~f:(fun _acc row ->
    match row.(0) with
    | Sqlite3.Data.FLOAT f -> f
    | Sqlite3.Data.INT i -> Int64.to_float i
    | _ -> 0.0
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  v

let query_string_int db sql =
  let stmt = Sqlite3_eio.prepare db sql in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let s = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let n = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    (s, n) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

let query_string_int_float db sql =
  let stmt = Sqlite3_eio.prepare db sql in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let s = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let n = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let f = match row.(2) with
      | Sqlite3.Data.FLOAT f -> f
      | Sqlite3.Data.INT i -> Int64.to_float i
      | _ -> 0.0
    in
    (s, n, f) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

(** {1 Data Queries} *)

let total_requests db =
  query_int db "SELECT COUNT(*) FROM requests"

let total_requests_24h db =
  query_int db
    "SELECT COUNT(*) FROM requests WHERE timestamp >= (strftime('%s','now') - 86400)"

let avg_response_time db =
  query_float db "SELECT COALESCE(AVG(duration_us), 0) FROM requests"

let cache_hit_rate db =
  let hits = query_int db
    "SELECT COUNT(*) FROM requests WHERE cache_status = 'hit'" in
  let cacheable = query_int db
    "SELECT COUNT(*) FROM requests WHERE cache_status IN ('hit', 'miss')" in
  if cacheable > 0 then float_of_int hits /. float_of_int cacheable *. 100.0
  else 0.0

let error_rate db =
  let errors = query_int db
    "SELECT COUNT(*) FROM requests WHERE status_code >= 400" in
  let total = query_int db "SELECT COUNT(*) FROM requests" in
  if total > 0 then float_of_int errors /. float_of_int total *. 100.0
  else 0.0

let total_bandwidth db =
  query_float db "SELECT COALESCE(SUM(response_body_size), 0) FROM requests"

let status_breakdown db =
  query_string_int db
    {|SELECT
        CASE
          WHEN status_code >= 200 AND status_code < 300 THEN '2xx'
          WHEN status_code >= 300 AND status_code < 400 THEN '3xx'
          WHEN status_code >= 400 AND status_code < 500 THEN '4xx'
          WHEN status_code >= 500 THEN '5xx'
          ELSE 'other'
        END AS bucket,
        COUNT(*) AS cnt
      FROM requests
      GROUP BY bucket ORDER BY bucket|}

let traffic_per_hour db =
  query_string_int db
    {|SELECT strftime('%Y-%m-%d %H:00', timestamp, 'unixepoch') AS hour,
             COUNT(*) AS cnt
      FROM requests
      WHERE timestamp >= (strftime('%s','now') - 172800)
      GROUP BY hour ORDER BY hour ASC|}

let top_pages_cache_rate db =
  let stmt = Sqlite3_eio.prepare db
    {|SELECT path,
             COUNT(*) AS cnt,
             AVG(duration_us) AS avg_us,
             SUM(CASE WHEN cache_status = 'hit' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS hit_rate
      FROM requests
      GROUP BY path ORDER BY cnt DESC LIMIT 20|} in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let path = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let cnt = match row.(1) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let avg = match row.(2) with
      | Sqlite3.Data.FLOAT f -> f | Sqlite3.Data.INT i -> Int64.to_float i | _ -> 0.0 in
    let rate = match row.(3) with
      | Sqlite3.Data.FLOAT f -> f | Sqlite3.Data.INT i -> Int64.to_float i | _ -> 0.0 in
    (path, cnt, avg, rate) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

let latency_percentiles db =
  let stmt = Sqlite3_eio.prepare db
    {|SELECT duration_us FROM requests ORDER BY duration_us ASC|} in
  let _rc, durations = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let d = match row.(0) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    d :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  let arr = Array.of_list (List.rev durations) in
  let len = Array.length arr in
  if len = 0 then (0, 0, 0, 0)
  else
    let pct p = arr.(min (len - 1) (int_of_float (float_of_int len *. p))) in
    (pct 0.50, pct 0.90, pct 0.95, pct 0.99)

let latency_histogram db =
  query_string_int db
    {|SELECT
        CASE
          WHEN duration_us < 100 THEN '<0.1ms'
          WHEN duration_us < 500 THEN '0.1-0.5ms'
          WHEN duration_us < 1000 THEN '0.5-1ms'
          WHEN duration_us < 5000 THEN '1-5ms'
          WHEN duration_us < 10000 THEN '5-10ms'
          WHEN duration_us < 50000 THEN '10-50ms'
          WHEN duration_us < 100000 THEN '50-100ms'
          WHEN duration_us < 500000 THEN '100-500ms'
          WHEN duration_us < 1000000 THEN '0.5-1s'
          ELSE '>1s'
        END AS bucket,
        COUNT(*) AS cnt
      FROM requests
      GROUP BY bucket
      ORDER BY MIN(duration_us) ASC|}

let top_referers db =
  query_string_int db
    {|SELECT COALESCE(referer, '(direct)') AS ref, COUNT(*) AS cnt
      FROM requests WHERE referer IS NOT NULL AND referer != ''
      GROUP BY ref ORDER BY cnt DESC LIMIT 10|}

let top_user_agents db =
  query_string_int db
    {|SELECT COALESCE(user_agent, '(none)') AS ua, COUNT(*) AS cnt
      FROM requests
      GROUP BY ua ORDER BY cnt DESC LIMIT 10|}

let recent_requests db =
  let stmt = Sqlite3_eio.prepare db
    {|SELECT
        strftime('%Y-%m-%d %H:%M:%S', timestamp, 'unixepoch') AS ts,
        method, path, status_code, duration_us, cache_status,
        response_body_size
      FROM requests
      ORDER BY timestamp DESC LIMIT 50|} in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let ts = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let meth = match row.(1) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let path = match row.(2) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let status = match row.(3) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let dur = match row.(4) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    let cache = match row.(5) with Sqlite3.Data.TEXT s -> s | Sqlite3.Data.NULL -> "" | _ -> "" in
    let size = match row.(6) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0 in
    (ts, meth, path, status, dur, cache, size) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

let cache_breakdown db =
  query_string_int db
    {|SELECT COALESCE(cache_status, 'none') AS cs, COUNT(*) AS cnt
      FROM requests GROUP BY cs ORDER BY cnt DESC|}

let cache_rate_per_hour db =
  let stmt = Sqlite3_eio.prepare db
    {|SELECT strftime('%Y-%m-%d %H:00', timestamp, 'unixepoch') AS hour,
             SUM(CASE WHEN cache_status = 'hit' THEN 1 ELSE 0 END) * 100.0 /
               NULLIF(SUM(CASE WHEN cache_status IN ('hit','miss') THEN 1 ELSE 0 END), 0) AS rate
      FROM requests
      WHERE timestamp >= (strftime('%s','now') - 172800)
      GROUP BY hour ORDER BY hour ASC|} in
  let _rc, rows = Sqlite3_eio.fold db stmt ~init:[] ~f:(fun acc row ->
    let hour = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let rate = match row.(1) with
      | Sqlite3.Data.FLOAT f -> f
      | Sqlite3.Data.NULL -> 0.0
      | _ -> 0.0 in
    (hour, rate) :: acc
  ) in
  ignore (Sqlite3_eio.finalize db stmt : Sqlite3.Rc.t);
  List.rev rows

(** {1 Formatting Helpers} *)

let human_bytes b =
  if b >= 1_073_741_824.0 then Printf.sprintf "%.1f GB" (b /. 1_073_741_824.0)
  else if b >= 1_048_576.0 then Printf.sprintf "%.1f MB" (b /. 1_048_576.0)
  else if b >= 1024.0 then Printf.sprintf "%.1f KB" (b /. 1024.0)
  else Printf.sprintf "%.0f B" b

let human_duration_us us =
  if us >= 1_000_000 then Printf.sprintf "%.2fs" (float_of_int us /. 1_000_000.0)
  else if us >= 1000 then Printf.sprintf "%.1fms" (float_of_int us /. 1000.0)
  else Printf.sprintf "%dus" us

let format_number n =
  let s = string_of_int n in
  let len = String.length s in
  if len <= 3 then s
  else
    let buf = Buffer.create (len + len / 3) in
    let rem = len mod 3 in
    for i = 0 to len - 1 do
      if i > 0 && (i - rem) mod 3 = 0 then Buffer.add_char buf ',';
      Buffer.add_char buf s.[i]
    done;
    Buffer.contents buf

(** {1 SVG Chart Rendering} *)

(** Render a bar chart as SVG. *)
let svg_bar_chart ~width ~height ~bars ~color () =
  let n = List.length bars in
  if n = 0 then El.void
  else
    let max_val = List.fold_left (fun m (_, v) -> max m v) 0 bars in
    let max_val = max max_val 1 in
    let bar_w = float_of_int width /. float_of_int n in
    let gap = max 1.0 (bar_w *. 0.1) in
    let actual_w = bar_w -. gap in
    let bars_els = List.mapi (fun i (label, value) ->
      let h = float_of_int value /. float_of_int max_val *. (float_of_int height -. 20.0) in
      let h = max h 1.0 in
      let x = float_of_int i *. bar_w +. (gap /. 2.0) in
      let y = float_of_int height -. h -. 16.0 in
      El.splice [
        El.v "rect" ~at:[
          At.v "x" (Printf.sprintf "%.1f" x);
          At.v "y" (Printf.sprintf "%.1f" y);
          At.v "width" (Printf.sprintf "%.1f" actual_w);
          At.v "height" (Printf.sprintf "%.1f" h);
          At.v "fill" color;
          At.v "rx" "2";
        ] [
          El.v "title" ~at:[] [El.txt (Printf.sprintf "%s: %s" label (format_number value))]
        ];
        (* Label every Nth bar to avoid overlap *)
        (if n <= 24 || i mod (max 1 (n / 12)) = 0 then
           let short_label =
             if String.length label > 5 then
               (* Extract just the hour part: "YYYY-MM-DD HH:00" -> "HH" *)
               let parts = String.split_on_char ' ' label in
               match parts with
               | [_; time] -> (try String.sub time 0 2 with _ -> label)
               | _ -> label
             else label
           in
           El.v "text" ~at:[
             At.v "x" (Printf.sprintf "%.1f" (x +. actual_w /. 2.0));
             At.v "y" (Printf.sprintf "%d" height);
             At.v "text-anchor" "middle";
             At.v "font-size" "9";
             At.v "fill" "currentColor";
             At.v "opacity" "0.6";
           ] [El.txt short_label]
         else El.void)
      ]
    ) bars in
    El.v "svg" ~at:[
      At.v "viewBox" (Printf.sprintf "0 0 %d %d" width height);
      At.v "width" "100%";
      At.v "height" (string_of_int height);
      At.class' "stats-chart";
      At.v "preserveAspectRatio" "none";
    ] bars_els

(** Render a horizontal bar chart for status codes. *)
let svg_horizontal_bars ~width ~height ~bars () =
  let n = List.length bars in
  if n = 0 then El.void
  else
    let max_val = List.fold_left (fun m (_, v, _) -> max m v) 0 bars in
    let max_val = max max_val 1 in
    let bar_h = float_of_int height /. float_of_int n in
    let gap = 4.0 in
    let actual_h = bar_h -. gap in
    let label_w = 80.0 in
    let chart_w = float_of_int width -. label_w -. 10.0 in
    let bars_els = List.mapi (fun i (label, value, color) ->
      let w = float_of_int value /. float_of_int max_val *. chart_w in
      let w = max w 2.0 in
      let y = float_of_int i *. bar_h +. (gap /. 2.0) in
      El.splice [
        El.v "text" ~at:[
          At.v "x" "0";
          At.v "y" (Printf.sprintf "%.1f" (y +. actual_h /. 2.0 +. 4.0));
          At.v "font-size" "12";
          At.v "fill" "currentColor";
          At.v "font-weight" "600";
        ] [El.txt label];
        El.v "rect" ~at:[
          At.v "x" (Printf.sprintf "%.0f" label_w);
          At.v "y" (Printf.sprintf "%.1f" y);
          At.v "width" (Printf.sprintf "%.1f" w);
          At.v "height" (Printf.sprintf "%.1f" actual_h);
          At.v "fill" color;
          At.v "rx" "3";
        ] [];
        El.v "text" ~at:[
          At.v "x" (Printf.sprintf "%.0f" (label_w +. w +. 6.0));
          At.v "y" (Printf.sprintf "%.1f" (y +. actual_h /. 2.0 +. 4.0));
          At.v "font-size" "11";
          At.v "fill" "currentColor";
          At.v "opacity" "0.7";
        ] [El.txt (format_number value)];
      ]
    ) bars in
    El.v "svg" ~at:[
      At.v "viewBox" (Printf.sprintf "0 0 %d %d" width height);
      At.v "width" "100%";
      At.v "height" (string_of_int height);
      At.class' "stats-chart";
    ] bars_els

(** Render a latency histogram as SVG. *)
let svg_latency_histogram ~width ~height ~bars () =
  svg_bar_chart ~width ~height ~bars ~color:"#6366f1" ()

(** Render cache rate over time as SVG line/area chart. *)
let svg_cache_rate_chart ~width ~height ~data () =
  let n = List.length data in
  if n = 0 then El.void
  else
    let padding_top = 10.0 in
    let padding_bottom = 20.0 in
    let chart_h = float_of_int height -. padding_top -. padding_bottom in
    let dx = float_of_int width /. float_of_int (max 1 (n - 1)) in
    let points = List.mapi (fun i (_label, rate) ->
      let x = float_of_int i *. dx in
      let y = padding_top +. chart_h -. (rate /. 100.0 *. chart_h) in
      (x, y)
    ) data in
    let line_str = String.concat " " (List.mapi (fun i (x, y) ->
      Printf.sprintf "%s%.1f,%.1f" (if i = 0 then "M" else "L") x y
    ) points) in
    (* Area fill *)
    let area_str =
      line_str
      ^ Printf.sprintf " L%.1f,%.1f L0,%.1f Z"
          (float_of_int width) (padding_top +. chart_h) (padding_top +. chart_h)
    in
    El.v "svg" ~at:[
      At.v "viewBox" (Printf.sprintf "0 0 %d %d" width height);
      At.v "width" "100%";
      At.v "height" (string_of_int height);
      At.class' "stats-chart";
    ] [
      (* Grid lines at 25%, 50%, 75%, 100% *)
      El.splice (List.map (fun pct ->
        let y = padding_top +. chart_h -. (pct /. 100.0 *. chart_h) in
        El.splice [
          El.v "line" ~at:[
            At.v "x1" "0"; At.v "y1" (Printf.sprintf "%.1f" y);
            At.v "x2" (string_of_int width); At.v "y2" (Printf.sprintf "%.1f" y);
            At.v "stroke" "currentColor"; At.v "stroke-opacity" "0.1";
            At.v "stroke-dasharray" "4,4";
          ] [];
          El.v "text" ~at:[
            At.v "x" (string_of_int (width - 2));
            At.v "y" (Printf.sprintf "%.1f" (y -. 2.0));
            At.v "text-anchor" "end";
            At.v "font-size" "9"; At.v "fill" "currentColor"; At.v "opacity" "0.4";
          ] [El.txt (Printf.sprintf "%.0f%%" pct)];
        ]
      ) [25.0; 50.0; 75.0; 100.0]);
      (* Area *)
      El.v "path" ~at:[
        At.v "d" area_str;
        At.v "fill" "#22c55e"; At.v "fill-opacity" "0.15";
      ] [];
      (* Line *)
      El.v "path" ~at:[
        At.v "d" line_str;
        At.v "fill" "none"; At.v "stroke" "#22c55e"; At.v "stroke-width" "2";
      ] [];
    ]

(** {1 Dashboard CSS} *)

let dashboard_css = {|
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem;
    margin-bottom: 2rem;
  }
  .stats-card {
    background: var(--color-surface, #f8f8f6);
    border: 1px solid var(--color-border, #e5e5e0);
    border-radius: 0.75rem;
    padding: 1.25rem;
    transition: box-shadow 0.2s;
  }
  .stats-card:hover {
    box-shadow: 0 2px 8px rgba(0,0,0,0.06);
  }
  .stats-card-label {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.6;
    margin-bottom: 0.25rem;
  }
  .stats-card-value {
    font-size: 1.75rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    line-height: 1.2;
  }
  .stats-card-sub {
    font-size: 0.75rem;
    opacity: 0.5;
    margin-top: 0.125rem;
  }
  .stats-section {
    margin-bottom: 2.5rem;
  }
  .stats-section h2 {
    font-size: 1rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.7;
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
    border-bottom: 2px solid var(--color-border, #e5e5e0);
  }
  .stats-chart {
    display: block;
    color: var(--color-text, #1a1a1a);
  }
  .stats-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
  }
  .stats-table th {
    text-align: left;
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.5;
    padding: 0.5rem 0.75rem;
    border-bottom: 2px solid var(--color-border, #e5e5e0);
  }
  .stats-table td {
    padding: 0.4rem 0.75rem;
    border-bottom: 1px solid var(--color-border, #e5e5e0);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 400px;
  }
  .stats-table tr:hover td {
    background: var(--color-surface, #f8f8f6);
  }
  .stats-table .num {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .stats-table .path-cell {
    max-width: 300px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .status-2xx { color: #22c55e; }
  .status-3xx { color: #3b82f6; }
  .status-4xx { color: #f59e0b; }
  .status-5xx { color: #ef4444; }
  .status-badge {
    display: inline-block;
    padding: 0.125rem 0.5rem;
    border-radius: 9999px;
    font-size: 0.75rem;
    font-weight: 600;
  }
  .badge-2xx { background: #dcfce7; color: #166534; }
  .badge-3xx { background: #dbeafe; color: #1e40af; }
  .badge-4xx { background: #fef3c7; color: #92400e; }
  .badge-5xx { background: #fee2e2; color: #991b1b; }
  .chart-container {
    background: var(--color-surface, #f8f8f6);
    border: 1px solid var(--color-border, #e5e5e0);
    border-radius: 0.75rem;
    padding: 1rem;
    overflow-x: auto;
  }
  .live-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    background: #22c55e;
    border-radius: 50%;
    animation: pulse 2s infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }
  .stats-two-col {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2rem;
  }
  @media (max-width: 768px) {
    .stats-two-col {
      grid-template-columns: 1fr;
    }
  }
  @media (prefers-color-scheme: dark) {
    .badge-2xx { background: #166534; color: #dcfce7; }
    .badge-3xx { background: #1e40af; color: #dbeafe; }
    .badge-4xx { background: #92400e; color: #fef3c7; }
    .badge-5xx { background: #991b1b; color: #fee2e2; }
  }
|}

(** {1 Dashboard JS} *)

let dashboard_js = {|
(function() {
  function refreshLive() {
    fetch('/action/api/recent')
      .then(r => r.json())
      .then(data => {
        const tbody = document.getElementById('live-tbody');
        if (!tbody || !data.requests) return;
        tbody.innerHTML = '';
        data.requests.forEach(r => {
          const tr = document.createElement('tr');
          const statusCls = r.status < 300 ? 'badge-2xx' :
                           r.status < 400 ? 'badge-3xx' :
                           r.status < 500 ? 'badge-4xx' : 'badge-5xx';
          tr.innerHTML =
            '<td>' + r.timestamp + '</td>' +
            '<td><strong>' + r.method + '</strong></td>' +
            '<td class="path-cell" title="' + r.path + '">' + r.path + '</td>' +
            '<td><span class="status-badge ' + statusCls + '">' + r.status + '</span></td>' +
            '<td class="num">' + r.duration + '</td>' +
            '<td>' + (r.cache || '-') + '</td>' +
            '<td class="num">' + r.size + '</td>';
          tbody.appendChild(tr);
        });
      })
      .catch(() => {});
  }
  setInterval(refreshLive, 5000);

  function refreshOverview() {
    fetch('/action/api/overview')
      .then(r => r.json())
      .then(data => {
        const fields = ['total', 'total_24h', 'avg_latency', 'cache_rate', 'error_rate', 'bandwidth'];
        fields.forEach(f => {
          const el = document.getElementById('ov-' + f);
          if (el && data[f] !== undefined) el.textContent = data[f];
        });
      })
      .catch(() => {});
  }
  setInterval(refreshOverview, 10000);
})();
|}

(** {1 HTML Rendering} *)

let status_color = function
  | "2xx" -> "#22c55e"
  | "3xx" -> "#3b82f6"
  | "4xx" -> "#f59e0b"
  | "5xx" -> "#ef4444"
  | _ -> "#9ca3af"

let status_badge_class status =
  if status < 300 then "badge-2xx"
  else if status < 400 then "badge-3xx"
  else if status < 500 then "badge-4xx"
  else "badge-5xx"

let overview_cards db =
  let total = total_requests db in
  let total_24 = total_requests_24h db in
  let avg_lat = avg_response_time db in
  let cache_rate = cache_hit_rate db in
  let err_rate = error_rate db in
  let bw = total_bandwidth db in
  let card ~label ~value ?(sub="") ~id () =
    El.div ~at:[At.class' "stats-card"] [
      El.div ~at:[At.class' "stats-card-label"] [El.txt label];
      El.div ~at:[At.class' "stats-card-value"; At.id id] [El.txt value];
      (if sub <> "" then
         El.div ~at:[At.class' "stats-card-sub"] [El.txt sub]
       else El.void);
    ]
  in
  El.div ~at:[At.class' "stats-grid"] [
    card ~label:"Total Requests" ~value:(format_number total)
      ~sub:(format_number total_24 ^ " last 24h") ~id:"ov-total" ();
    card ~label:"Avg Response Time" ~value:(human_duration_us (Float.to_int avg_lat))
      ~id:"ov-avg_latency" ();
    card ~label:"Cache Hit Rate" ~value:(Printf.sprintf "%.1f%%" cache_rate)
      ~id:"ov-cache_rate" ();
    card ~label:"Error Rate" ~value:(Printf.sprintf "%.1f%%" err_rate)
      ~id:"ov-error_rate" ();
    card ~label:"Bandwidth" ~value:(human_bytes bw)
      ~id:"ov-bandwidth" ();
  ]

let traffic_section db =
  let hourly = traffic_per_hour db in
  let bars = List.map (fun (h, c) -> (h, c)) hourly in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Traffic Over Time (48h)"];
    El.div ~at:[At.class' "chart-container"] [
      svg_bar_chart ~width:800 ~height:200 ~bars ~color:"#6366f1" ()
    ]
  ]

let status_section db =
  let statuses = status_breakdown db in
  let total = List.fold_left (fun acc (_, n) -> acc + n) 0 statuses in
  let bars = List.map (fun (bucket, cnt) ->
    (bucket, cnt, status_color bucket)
  ) statuses in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Response Status Distribution"];
    El.div ~at:[At.class' "chart-container"] [
      svg_horizontal_bars ~width:500 ~height:(max 80 (List.length bars * 40)) ~bars ()
    ];
    El.div ~at:[At.class' "mt-3 text-sm opacity-60"] [
      El.txt (Printf.sprintf "Total: %s requests" (format_number total))
    ]
  ]

let top_pages_section db =
  let pages = top_pages_cache_rate db in
  let rows = List.map (fun (path, cnt, avg, rate) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" path] [El.txt path];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_duration_us (Float.to_int avg))];
      El.v "td" ~at:[At.class' "num"] [El.txt (Printf.sprintf "%.0f%%" rate)];
    ]
  ) pages in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Top Pages"];
    El.div ~at:[At.class' "chart-container"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [
          El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "Path"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Hits"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Avg Latency"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Cache %"];
          ]
        ];
        El.v "tbody" ~at:[] rows
      ]
    ]
  ]

let latency_section db =
  let p50, p90, p95, p99 = latency_percentiles db in
  let hist = latency_histogram db in
  let bars = List.map (fun (bucket, cnt) -> (bucket, cnt)) hist in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Latency Distribution"];
    El.div ~at:[At.class' "stats-grid"; At.style "margin-bottom: 1rem"] [
      El.div ~at:[At.class' "stats-card"] [
        El.div ~at:[At.class' "stats-card-label"] [El.txt "p50"];
        El.div ~at:[At.class' "stats-card-value"] [El.txt (human_duration_us p50)]];
      El.div ~at:[At.class' "stats-card"] [
        El.div ~at:[At.class' "stats-card-label"] [El.txt "p90"];
        El.div ~at:[At.class' "stats-card-value"] [El.txt (human_duration_us p90)]];
      El.div ~at:[At.class' "stats-card"] [
        El.div ~at:[At.class' "stats-card-label"] [El.txt "p95"];
        El.div ~at:[At.class' "stats-card-value"] [El.txt (human_duration_us p95)]];
      El.div ~at:[At.class' "stats-card"] [
        El.div ~at:[At.class' "stats-card-label"] [El.txt "p99"];
        El.div ~at:[At.class' "stats-card-value"] [El.txt (human_duration_us p99)]];
    ];
    El.div ~at:[At.class' "chart-container"] [
      svg_latency_histogram ~width:600 ~height:180 ~bars ()
    ]
  ]

let referers_section db =
  let refs = top_referers db in
  let rows = List.map (fun (ref, cnt) ->
    let short = if String.length ref > 80 then String.sub ref 0 80 ^ "..." else ref in
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" ref] [El.txt short];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
    ]
  ) refs in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Top Referrers"];
    El.div ~at:[At.class' "chart-container"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [
          El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "Referrer"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Count"];
          ]
        ];
        El.v "tbody" ~at:[] rows
      ]
    ]
  ]

let user_agents_section db =
  let uas = top_user_agents db in
  let simplify_ua ua =
    (* Extract a readable browser/bot name from the UA string *)
    if String.length ua > 60 then
      (* Try to get the last meaningful token *)
      let parts = String.split_on_char ' ' ua in
      let interesting = List.filter (fun p ->
        not (String.starts_with ~prefix:"Mozilla" p)
        && not (String.starts_with ~prefix:"(compatible" p)
        && not (String.starts_with ~prefix:"(KHTML" p)
        && not (String.starts_with ~prefix:"like" p)
        && not (String.starts_with ~prefix:"AppleWebKit" p)
        && not (String.starts_with ~prefix:"Gecko" p)
        && p <> ")" && p <> ""
      ) parts in
      match List.rev interesting with
      | last :: _ -> last
      | [] -> String.sub ua 0 60 ^ "..."
    else ua
  in
  let rows = List.map (fun (ua, cnt) ->
    El.v "tr" ~at:[] [
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" ua]
        [El.txt (simplify_ua ua)];
      El.v "td" ~at:[At.class' "num"] [El.txt (format_number cnt)];
    ]
  ) uas in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Top User Agents"];
    El.div ~at:[At.class' "chart-container"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [
          El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "User Agent"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Count"];
          ]
        ];
        El.v "tbody" ~at:[] rows
      ]
    ]
  ]

let live_activity_section db =
  let recent = recent_requests db in
  let rows = List.map (fun (ts, meth, path, status, dur, cache, size) ->
    let badge_cls = status_badge_class status in
    El.v "tr" ~at:[] [
      El.v "td" ~at:[] [El.txt ts];
      El.v "td" ~at:[] [El.strong [El.txt meth]];
      El.v "td" ~at:[At.class' "path-cell"; At.v "title" path] [El.txt path];
      El.v "td" ~at:[] [
        El.span ~at:[At.class' ("status-badge " ^ badge_cls)]
          [El.txt (string_of_int status)]];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_duration_us dur)];
      El.v "td" ~at:[] [El.txt (if cache = "" then "-" else cache)];
      El.v "td" ~at:[At.class' "num"] [El.txt (human_bytes (float_of_int size))];
    ]
  ) recent in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [
      El.span ~at:[At.class' "live-dot"; At.style "margin-right: 0.5rem"] [];
      El.txt "Live Activity"
    ];
    El.div ~at:[At.class' "chart-container"; At.style "overflow-x: auto"] [
      El.table ~at:[At.class' "stats-table"] [
        El.v "thead" ~at:[] [
          El.v "tr" ~at:[] [
            El.v "th" ~at:[] [El.txt "Time"];
            El.v "th" ~at:[] [El.txt "Method"];
            El.v "th" ~at:[] [El.txt "Path"];
            El.v "th" ~at:[] [El.txt "Status"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Latency"];
            El.v "th" ~at:[] [El.txt "Cache"];
            El.v "th" ~at:[At.class' "num"] [El.txt "Size"];
          ]
        ];
        El.v "tbody" ~at:[At.id "live-tbody"] rows
      ]
    ]
  ]

let cache_section db =
  let breakdown = cache_breakdown db in
  let rate_data = cache_rate_per_hour db in
  let total = List.fold_left (fun acc (_, n) -> acc + n) 0 breakdown in
  let breakdown_items = List.map (fun (status, cnt) ->
    let pct = if total > 0 then float_of_int cnt /. float_of_int total *. 100.0 else 0.0 in
    El.div ~at:[At.class' "flex justify-between items-center py-1"] [
      El.span ~at:[At.class' "font-medium"] [El.txt status];
      El.span ~at:[At.class' "text-sm opacity-70 tabular-nums"]
        [El.txt (Printf.sprintf "%s (%.1f%%)" (format_number cnt) pct)];
    ]
  ) breakdown in
  El.div ~at:[At.class' "stats-section"] [
    El.h2 ~at:[] [El.txt "Cache Performance"];
    El.div ~at:[At.class' "stats-two-col"] [
      El.div ~at:[At.class' "chart-container"] [
        El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"] [El.txt "Hit/Miss Breakdown"];
        El.div ~at:[] breakdown_items;
      ];
      El.div ~at:[At.class' "chart-container"] [
        El.h3 ~at:[At.class' "text-sm font-semibold mb-2 opacity-70"] [El.txt "Hit Rate Over Time (48h)"];
        svg_cache_rate_chart ~width:400 ~height:150 ~data:rate_data ();
      ];
    ]
  ]

(** {1 Full Dashboard Page} *)

let render_dashboard db =
  let content = El.div ~at:[At.style "max-width: 1000px; margin: 0 auto; padding: 1rem 1rem 3rem"] [
    El.style [El.unsafe_raw dashboard_css];
    El.h1 ~at:[At.class' "text-2xl font-bold mb-1"] [El.txt "Arod Analytics"];
    El.p ~at:[At.class' "text-sm opacity-50 mb-6"] [El.txt "Server statistics dashboard"];
    overview_cards db;
    traffic_section db;
    El.div ~at:[At.class' "stats-two-col"] [
      status_section db;
      latency_section db;
    ];
    top_pages_section db;
    El.div ~at:[At.class' "stats-two-col"] [
      referers_section db;
      user_agents_section db;
    ];
    live_activity_section db;
    cache_section db;
    El.script [El.unsafe_raw dashboard_js];
  ] in
  (* Minimal standalone page -- no nav, no footer, no sitemap link *)
  let head_el = El.head [
    El.meta ~at:[At.charset "utf-8"] ();
    El.meta ~at:[At.name "viewport"; At.content "width=device-width, initial-scale=1.0"] ();
    El.meta ~at:[At.name "robots"; At.content "noindex, nofollow"] ();
    El.title [El.txt "Arod Analytics"];
    (* Tailwind for utility classes *)
    El.script ~at:[At.src "https://cdn.tailwindcss.com"] [];
    El.script [El.unsafe_raw {|
      tailwind.config = {
        darkMode: 'media',
        theme: {
          extend: {
            colors: {
              bg: 'var(--color-bg, #fffffc)',
              text: 'var(--color-text, #1a1a1a)',
              surface: 'var(--color-surface, #f8f8f6)',
              border: 'var(--color-border, #e5e5e0)',
            }
          }
        }
      }
    |}];
    El.style [El.unsafe_raw {|
      :root {
        --color-bg: #fffffc;
        --color-text: #1a1a1a;
        --color-surface: #f8f8f6;
        --color-surface-alt: #eeeeea;
        --color-border: #e5e5e0;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --color-bg: #1a1a1f;
          --color-text: #e5e5e0;
          --color-surface: #252529;
          --color-surface-alt: #2d2d33;
          --color-border: #3a3a42;
        }
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                     "Helvetica Neue", Arial, sans-serif;
        background: var(--color-bg);
        color: var(--color-text);
      }
    |}];
  ] in
  let body_el = El.body ~at:[At.class' "bg-bg text-text"] [content] in
  El.to_string ~doctype:true (El.html ~at:[At.lang "en"] [head_el; body_el])

(** {1 JSON API Responses} *)

let overview_json db =
  let total = total_requests db in
  let total_24 = total_requests_24h db in
  let avg_lat = avg_response_time db in
  let cache_rate = cache_hit_rate db in
  let err_rate = error_rate db in
  let bw = total_bandwidth db in
  Ezjsonm.to_string (`O [
    ("total", `String (format_number total));
    ("total_24h", `String (format_number total_24));
    ("avg_latency", `String (human_duration_us (Float.to_int avg_lat)));
    ("cache_rate", `String (Printf.sprintf "%.1f%%" cache_rate));
    ("error_rate", `String (Printf.sprintf "%.1f%%" err_rate));
    ("bandwidth", `String (human_bytes bw));
  ])

let traffic_json db =
  let hourly = traffic_per_hour db in
  let items = List.map (fun (hour, cnt) ->
    `O [("hour", `String hour); ("count", `Float (float_of_int cnt))]
  ) hourly in
  Ezjsonm.to_string (`O [("traffic", `A items)])

let recent_json db =
  let recent = recent_requests db in
  let items = List.map (fun (ts, meth, path, status, dur, cache, size) ->
    `O [
      ("timestamp", `String ts);
      ("method", `String meth);
      ("path", `String path);
      ("status", `Float (float_of_int status));
      ("duration", `String (human_duration_us dur));
      ("cache", `String (if cache = "" then "" else cache));
      ("size", `String (human_bytes (float_of_int size)));
    ]
  ) recent in
  Ezjsonm.to_string (`O [("requests", `A items)])
