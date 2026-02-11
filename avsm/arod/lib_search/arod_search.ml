(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** FTS5 full-text search index for Arod content.

    Uses one FTS5 table per entry kind (paper, note, project, idea, video,
    link) so that kind filtering is a simple matter of which tables to query.
    Results from each table are merged and sorted by date. *)

type t = { db : Sqlite3_eio.t }

type result = {
  slug : string;
  kind : string;
  url : string;
  title : string;
  snippet : string;
  date : string;
  rank : float;
  parent_slugs : string list;
}

(** {1 Kinds} *)

let kinds = ["paper"; "note"; "project"; "idea"; "video"; "link"]

let table_for kind = "search_" ^ kind

(** {1 Schema — one FTS5 table per kind} *)

let create_table_sql kind =
  Printf.sprintf
    {|CREATE VIRTUAL TABLE IF NOT EXISTS %s USING fts5(
        slug UNINDEXED,
        url UNINDEXED,
        date UNINDEXED,
        parent_slugs UNINDEXED,
        title,
        body,
        tags,
        tokenize='porter unicode61'
      )|}
    (table_for kind)

let create_all_tables db =
  List.iter (fun kind ->
    Sqlite3.Rc.check (Sqlite3_eio.exec db (create_table_sql kind))
  ) kinds

let create ~sw path =
  let db = Sqlite3_eio.open_path ~sw ~busy_timeout:5000 path in
  create_all_tables db;
  { db }

let create_memory ~sw () =
  let db = Sqlite3_eio.open_memory ~sw () in
  create_all_tables db;
  { db }

let open_readonly ~sw path =
  let db = Sqlite3_eio.open_path ~sw ~busy_timeout:5000 ~mode:`READONLY path in
  { db }

(** {1 Date formatting} *)

let date_string_of_triple (y, m, d) =
  Fmt.str "%04d-%02d-%02d" y m d

(** {1 Indexing} *)

let insert_sql kind =
  Printf.sprintf
    {|INSERT INTO %s (slug, url, date, parent_slugs, title, body, tags)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)|}
    (table_for kind)

let insert_row t ~kind ~slug ~url ~date ~parent_slugs ~title ~body ~tags =
  let stmt = Sqlite3_eio.prepare t.db (insert_sql kind) in
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 1 slug);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 2 url);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 3 date);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 4 parent_slugs);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 5 title);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 6 body);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 7 tags);
  let rc = Sqlite3_eio.step t.db stmt in
  ignore (Sqlite3_eio.finalize t.db stmt);
  match rc with
  | Sqlite3.Rc.DONE -> ()
  | rc -> Sqlite3.Rc.check rc

let index_entry t ~contact_name (ent : Bushel.Entry.entry) =
  let slug = Bushel.Entry.slug ent in
  let kind = Bushel.Entry.to_type_string ent in
  let url = Bushel.Entry.site_url ent in
  let date = date_string_of_triple (Bushel.Entry.date ent) in
  let title = Bushel.Entry.title ent in
  let tags_list = match ent with
    | `Paper p -> Bushel.Paper.tags p
    | `Note n -> Bushel.Note.tags n
    | `Project p -> Bushel.Project.tags p
    | `Idea i -> Bushel.Idea.tags i
    | `Video v -> Bushel.Video.tags v
  in
  let tags = String.concat " " tags_list in
  let plain = Bushel.Md.plain_text_of_markdown ~contact_name in
  let body = match ent with
    | `Paper p -> Bushel.Paper.abstract p
    | `Note n -> plain (Bushel.Note.body n)
    | `Project p -> plain (Bushel.Project.body p)
    | `Idea i -> plain (Bushel.Idea.body i)
    | `Video v -> Bushel.Video.description v
  in
  insert_row t ~kind ~slug ~url ~date ~parent_slugs:"" ~title ~body ~tags

let strip_scheme url =
  let prefixes = ["https://"; "http://"] in
  match List.find_opt (fun p -> String.starts_with ~prefix:p url) prefixes with
  | Some p -> String.sub url (String.length p) (String.length url - String.length p)
  | None -> url

let index_link t (link : Bushel.Link.t) =
  let url = Bushel.Link.url link in
  let slug = url in
  let kind = "link" in
  let date = date_string_of_triple (Bushel.Link.date link) in
  let karakeep_meta = match link.karakeep with
    | Some k -> k.metadata
    | None -> []
  in
  let title = match List.assoc_opt "title" karakeep_meta with
    | Some t when t <> "" -> t
    | _ -> url
  in
  let karakeep_summary = match List.assoc_opt "summary" karakeep_meta with
    | Some s when s <> "" -> s
    | _ -> ""
  in
  let body =
    let desc = Bushel.Link.description link in
    let parts =
      (if karakeep_summary <> "" then [karakeep_summary] else [])
      @ (if desc <> "" then [desc] else [])
      @ [strip_scheme url]
    in
    String.concat "\n" parts
  in
  let karakeep_tags = match link.karakeep with
    | Some k -> k.tags
    | None -> []
  in
  let bushel_tags = match link.bushel with
    | Some b -> b.tags
    | None -> []
  in
  let tags = String.concat " " (karakeep_tags @ bushel_tags) in
  let parent_slugs = match link.bushel with
    | Some b -> String.concat "," b.slugs
    | None -> ""
  in
  insert_row t ~kind ~slug ~url ~date ~parent_slugs ~title ~body ~tags

let rebuild t ctx =
  Sqlite3.Rc.check (Sqlite3_eio.exec t.db "BEGIN");
  List.iter (fun kind ->
    Sqlite3.Rc.check (Sqlite3_eio.exec t.db
      (Printf.sprintf "DELETE FROM %s" (table_for kind)))
  ) kinds;
  let contacts = Arod.Ctx.contacts ctx in
  let contact_name handle =
    List.find_map (fun c ->
      if Sortal_schema.Contact.handle c = handle
      then Some (Sortal_schema.Contact.name c)
      else None
    ) contacts
  in
  let entries = Arod.Ctx.all_entries ctx in
  List.iter (fun ent -> index_entry t ~contact_name ent) entries;
  let links = Arod.Ctx.all_links ctx in
  List.iter (fun link -> index_link t link) links;
  Sqlite3.Rc.check (Sqlite3_eio.exec t.db "COMMIT");
  (* Log per-table counts *)
  List.iter (fun kind ->
    let tbl = table_for kind in
    let sql = Printf.sprintf "SELECT count(*) FROM %s" tbl in
    let stmt = Sqlite3_eio.prepare t.db sql in
    let _rc, count = Sqlite3_eio.fold t.db stmt ~init:0 ~f:(fun _acc row ->
      match row.(0) with Sqlite3.Data.INT i -> Int64.to_int i | _ -> 0
    ) in
    ignore (Sqlite3_eio.finalize t.db stmt);
    Logs.info (fun m -> m "Search index: %s has %d rows" tbl count)
  ) kinds

(** {1 Querying} *)

let parse_parent_slugs s =
  if s = "" then []
  else String.split_on_char ',' s |> List.filter (fun s -> s <> "")

(** Query a single per-kind FTS5 table. *)
let query_table t ~kind ~limit q =
  let tbl = table_for kind in
  let sql = Printf.sprintf
    {|SELECT slug, url, date, parent_slugs, title,
           snippet(%s, 5, '<b>', '</b>', '...', 32),
           bm25(%s, 0.0, 0.0, 0.0, 0.0, 10.0, 1.0, 5.0)
      FROM %s
      WHERE %s MATCH ?1
      ORDER BY date DESC
      LIMIT ?2|}
    tbl tbl tbl tbl
  in
  let stmt = Sqlite3_eio.prepare t.db sql in
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 1 q);
  Sqlite3.Rc.check (Sqlite3.bind_int stmt 2 limit);
  let _rc, results = Sqlite3_eio.fold t.db stmt ~init:[] ~f:(fun acc row ->
    let slug = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let url = match row.(1) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let date = match row.(2) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let parent_slugs_str = match row.(3) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let title = match row.(4) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let snippet = match row.(5) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let rank = match row.(6) with Sqlite3.Data.FLOAT f -> f | _ -> 0.0 in
    let parent_slugs = parse_parent_slugs parent_slugs_str in
    { slug; kind; url; title; snippet; date; rank; parent_slugs } :: acc
  ) in
  ignore (Sqlite3_eio.finalize t.db stmt);
  List.rev results

(** Merge results from multiple tables, sorted by date descending, take [limit]. *)
let merge_results ~limit results_per_kind =
  let all = List.concat results_per_kind in
  let sorted = List.sort (fun a b -> String.compare b.date a.date) all in
  let rec take acc n = function
    | _ when n <= 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: xs -> take (x :: acc) (n - 1) xs
  in
  take [] limit sorted

(** {1 Search syntax} *)

let parse_search_input input =
  let words = String.split_on_char ' ' input in
  let found_kinds = ref [] in
  let terms = List.filter_map (fun w ->
    match String.split_on_char ':' w with
    | ["kind"; k] when List.mem k kinds ->
      found_kinds := k :: !found_kinds; None
    | _ ->
      if w = "" then None else Some w
  ) words in
  (* Append * to the last term for prefix matching (works-as-you-type)
     unless it already ends with * or is a quoted phrase *)
  let terms = match List.rev terms with
    | [] -> []
    | last :: rest ->
      let last' =
        if String.ends_with ~suffix:"*" last then last
        else if String.starts_with ~prefix:"\"" last then last
        else last ^ "*"
      in
      List.rev (last' :: rest)
  in
  let fts_query = String.concat " " terms in
  (List.rev !found_kinds, fts_query)

let search t ?(limit = 20) input =
  let found_kinds, fts_query = parse_search_input input in
  Logs.info (fun m -> m "Search: input=%S kinds=[%s] fts_query=%S"
    input (String.concat "," found_kinds) fts_query);
  if fts_query = "" then []
  else
    let target_kinds = match found_kinds with
      | [] -> kinds
      | ks -> ks
    in
    let per_kind = List.map (fun kind ->
      let results = query_table t ~kind ~limit fts_query in
      Logs.info (fun m -> m "Search: table=%s query=%S -> %d results"
        (table_for kind) fts_query (List.length results));
      results
    ) target_kinds in
    merge_results ~limit per_kind

let strip_html s =
  let buf = Buffer.create (String.length s) in
  let in_tag = ref false in
  String.iter (fun c ->
    if c = '<' then in_tag := true
    else if c = '>' then in_tag := false
    else if not !in_tag then Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let pp_result ppf r =
  let snippet = strip_html r.snippet in
  Fmt.pf ppf "@[<v>%s [%s] %s@,  %s@,  %s@]"
    r.title r.kind r.date r.url snippet
