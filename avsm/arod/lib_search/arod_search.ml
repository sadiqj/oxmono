(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** FTS5 full-text search index for Arod content. *)

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

let create_table_sql =
  {|CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
      slug UNINDEXED,
      kind UNINDEXED,
      url UNINDEXED,
      date UNINDEXED,
      parent_slugs UNINDEXED,
      title,
      body,
      tags,
      tokenize='porter unicode61'
    )|}

let create ~sw path =
  let db = Sqlite3_eio.open_path ~sw ~busy_timeout:5000 path in
  Sqlite3.Rc.check (Sqlite3_eio.exec db create_table_sql);
  { db }

let create_memory ~sw () =
  let db = Sqlite3_eio.open_memory ~sw () in
  Sqlite3.Rc.check (Sqlite3_eio.exec db create_table_sql);
  { db }

let open_readonly ~sw path =
  let db = Sqlite3_eio.open_path ~sw ~busy_timeout:5000 ~mode:`READONLY path in
  { db }

(** {1 Plain text extraction from markdown} *)

let inline_to_plain_text i =
  let lines = Cmarkit.Inline.to_plain_text ~break_on_soft:true i in
  String.concat "\n" (List.map (String.concat "") lines)

let plain_text_of_markdown md =
  let doc = Cmarkit.Doc.of_string md in
  let block _f acc = function
    | Cmarkit.Block.Paragraph (p, _) ->
      let text = inline_to_plain_text (Cmarkit.Block.Paragraph.inline p) in
      `Fold (text :: acc)
    | Cmarkit.Block.Heading (h, _) ->
      let text = inline_to_plain_text (Cmarkit.Block.Heading.inline h) in
      `Fold (text :: acc)
    | _ -> `Default
  in
  let folder = Cmarkit.Folder.make ~block () in
  let parts = Cmarkit.Folder.fold_doc folder [] doc in
  String.concat "\n" (List.rev parts)

(** {1 Date formatting} *)

let date_string_of_triple (y, m, d) =
  Fmt.str "%04d-%02d-%02d" y m d

(** {1 Indexing} *)

let insert_sql =
  {|INSERT INTO search_index (slug, kind, url, date, parent_slugs, title, body, tags)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)|}

let insert_row t ~slug ~kind ~url ~date ~parent_slugs ~title ~body ~tags =
  let stmt = Sqlite3_eio.prepare t.db insert_sql in
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 1 slug);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 2 kind);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 3 url);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 4 date);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 5 parent_slugs);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 6 title);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 7 body);
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 8 tags);
  let rc = Sqlite3_eio.step t.db stmt in
  ignore (Sqlite3_eio.finalize t.db stmt);
  match rc with
  | Sqlite3.Rc.DONE -> ()
  | rc -> Sqlite3.Rc.check rc

let index_entry t (ent : Bushel.Entry.entry) =
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
  let body = match ent with
    | `Paper p -> Bushel.Paper.abstract p
    | `Note n -> plain_text_of_markdown (Bushel.Note.body n)
    | `Project p -> plain_text_of_markdown (Bushel.Project.body p)
    | `Idea i -> plain_text_of_markdown (Bushel.Idea.body i)
    | `Video v -> Bushel.Video.description v
  in
  insert_row t ~slug ~kind ~url ~date ~parent_slugs:"" ~title ~body ~tags

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
  insert_row t ~slug ~kind ~url ~date ~parent_slugs ~title ~body ~tags

let rebuild t ctx =
  Sqlite3.Rc.check (Sqlite3_eio.exec t.db "BEGIN");
  Sqlite3.Rc.check (Sqlite3_eio.exec t.db
    "DELETE FROM search_index");
  let entries = Arod.Ctx.all_entries ctx in
  List.iter (fun ent -> index_entry t ent) entries;
  let links = Arod.Ctx.all_links ctx in
  List.iter (fun link -> index_link t link) links;
  Sqlite3.Rc.check (Sqlite3_eio.exec t.db "COMMIT")

(** {1 Querying} *)

let query_sql =
  {|SELECT slug, kind, url, date, title,
         snippet(search_index, 6, '<b>', '</b>', '...', 32),
         bm25(search_index, 10.0, 1.0, 5.0),
         parent_slugs
    FROM search_index
    WHERE search_index MATCH ?1
    ORDER BY date DESC
    LIMIT ?2|}

let query_kind_sql =
  {|SELECT slug, kind, url, date, title,
         snippet(search_index, 6, '<b>', '</b>', '...', 32),
         bm25(search_index, 10.0, 1.0, 5.0),
         parent_slugs
    FROM search_index
    WHERE search_index MATCH ?1 AND kind = ?3
    ORDER BY date DESC
    LIMIT ?2|}

let query_kinds_sql =
  {|SELECT slug, kind, url, date, title,
         snippet(search_index, 6, '<b>', '</b>', '...', 32),
         bm25(search_index, 10.0, 1.0, 5.0),
         parent_slugs
    FROM search_index
    WHERE search_index MATCH ?1 AND kind IN (SELECT value FROM json_each(?3))
    ORDER BY date DESC
    LIMIT ?2|}

let parse_parent_slugs s =
  if s = "" then []
  else String.split_on_char ',' s |> List.filter (fun s -> s <> "")

let query t ?kind ?kinds ?(limit = 20) q =
  let sql, bind_filter = match kinds, kind with
    | Some _, _ -> query_kinds_sql, `Kinds
    | _, Some _ -> query_kind_sql, `Kind
    | None, None -> query_sql, `None
  in
  let stmt = Sqlite3_eio.prepare t.db sql in
  Sqlite3.Rc.check (Sqlite3.bind_text stmt 1 q);
  Sqlite3.Rc.check (Sqlite3.bind_int stmt 2 limit);
  (match bind_filter with
   | `Kind ->
     (match kind with
      | Some k -> Sqlite3.Rc.check (Sqlite3.bind_text stmt 3 k)
      | None -> ())
   | `Kinds ->
     (match kinds with
      | Some ks ->
        let json = "[" ^ String.concat "," (List.map (fun k -> "\"" ^ k ^ "\"") ks) ^ "]" in
        Sqlite3.Rc.check (Sqlite3.bind_text stmt 3 json)
      | None -> ())
   | `None -> ());
  let _rc, results = Sqlite3_eio.fold t.db stmt ~init:[] ~f:(fun acc row ->
    let slug = match row.(0) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let kind = match row.(1) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let url = match row.(2) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let date = match row.(3) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let title = match row.(4) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let snippet = match row.(5) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let rank = match row.(6) with Sqlite3.Data.FLOAT f -> f | _ -> 0.0 in
    let parent_slugs_str = match row.(7) with Sqlite3.Data.TEXT s -> s | _ -> "" in
    let parent_slugs = parse_parent_slugs parent_slugs_str in
    { slug; kind; url; title; snippet; date; rank; parent_slugs } :: acc
  ) in
  ignore (Sqlite3_eio.finalize t.db stmt);
  List.rev results

(** {1 Search syntax} *)

let kinds = ["paper"; "note"; "project"; "idea"; "video"; "link"]

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

let search t ?limit input =
  let found_kinds, fts_query = parse_search_input input in
  if fts_query = "" then []
  else match found_kinds with
    | [] -> query t ?limit fts_query
    | [k] -> query t ~kind:k ?limit fts_query
    | ks -> query t ~kinds:ks ?limit fts_query

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
