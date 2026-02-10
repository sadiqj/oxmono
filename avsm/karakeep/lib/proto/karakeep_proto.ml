(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep API protocol types and JSON codecs *)

(** {1 Helper Codecs} *)

let ptime_jsont =
  let dec s =
    match Ptime.of_rfc3339 s with
    | Ok (t, _, _) -> Ok t
    | Error _ -> Error (Printf.sprintf "Invalid timestamp: %s" s)
  in
  let enc t =
    let (y, m, d), ((hh, mm, ss), _) = Ptime.to_date_time t in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" y m d hh mm ss
  in
  Jsont.of_of_string ~kind:"Ptime.t" dec ~enc

let ptime_option_jsont =
  let null = Jsont.null None in
  let some = Jsont.map ~dec:(fun t -> Some t) ~enc:(function Some t -> t | None -> assert false) ptime_jsont in
  Jsont.any ~dec_null:null ~dec_string:some ~enc:(function None -> null | Some _ -> some) ()

(** {1 ID Types} *)

type asset_id = string
type bookmark_id = string
type list_id = string
type tag_id = string
type highlight_id = string

(** {1 Enum Types} *)

type bookmark_content_type = Link | Text | Asset | Unknown

let bookmark_content_type_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "link" -> Ok Link
    | "text" -> Ok Text
    | "asset" -> Ok Asset
    | _ -> Ok Unknown
  in
  let enc = function
    | Link -> "link"
    | Text -> "text"
    | Asset -> "asset"
    | Unknown -> "unknown"
  in
  Jsont.of_of_string ~kind:"bookmark_content_type" dec ~enc

type asset_type =
  | Screenshot
  | AssetScreenshot
  | BannerImage
  | FullPageArchive
  | Video
  | BookmarkAsset
  | PrecrawledArchive
  | Unknown

let asset_type_jsont =
  let dec s =
    match s with
    | "screenshot" -> Ok Screenshot
    | "assetScreenshot" -> Ok AssetScreenshot
    | "bannerImage" -> Ok BannerImage
    | "fullPageArchive" -> Ok FullPageArchive
    | "video" -> Ok Video
    | "bookmarkAsset" -> Ok BookmarkAsset
    | "precrawledArchive" -> Ok PrecrawledArchive
    | _ -> Ok Unknown
  in
  let enc = function
    | Screenshot -> "screenshot"
    | AssetScreenshot -> "assetScreenshot"
    | BannerImage -> "bannerImage"
    | FullPageArchive -> "fullPageArchive"
    | Video -> "video"
    | BookmarkAsset -> "bookmarkAsset"
    | PrecrawledArchive -> "precrawledArchive"
    | Unknown -> "unknown"
  in
  Jsont.of_of_string ~kind:"asset_type" dec ~enc

type tagging_status = Success | Failure | Pending

let tagging_status_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "success" -> Ok Success
    | "failure" -> Ok Failure
    | "pending" -> Ok Pending
    | _ -> Ok Pending
  in
  let enc = function
    | Success -> "success"
    | Failure -> "failure"
    | Pending -> "pending"
  in
  Jsont.of_of_string ~kind:"tagging_status" dec ~enc

let string_of_tagging_status = function
  | Success -> "success"
  | Failure -> "failure"
  | Pending -> "pending"

type list_type = Manual | Smart

let list_type_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "manual" -> Ok Manual
    | "smart" -> Ok Smart
    | _ -> Ok Manual
  in
  let enc = function Manual -> "manual" | Smart -> "smart"
  in
  Jsont.of_of_string ~kind:"list_type" dec ~enc

type highlight_color = Yellow | Red | Green | Blue

let highlight_color_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "yellow" -> Ok Yellow
    | "red" -> Ok Red
    | "green" -> Ok Green
    | "blue" -> Ok Blue
    | _ -> Ok Yellow
  in
  let enc = function
    | Yellow -> "yellow"
    | Red -> "red"
    | Green -> "green"
    | Blue -> "blue"
  in
  Jsont.of_of_string ~kind:"highlight_color" dec ~enc

let string_of_highlight_color = function
  | Yellow -> "yellow"
  | Red -> "red"
  | Green -> "green"
  | Blue -> "blue"

type tag_attachment_type = AI | Human

let tag_attachment_type_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "ai" -> Ok AI
    | "human" -> Ok Human
    | _ -> Ok Human
  in
  let enc = function AI -> "ai" | Human -> "human"
  in
  Jsont.of_of_string ~kind:"tag_attachment_type" dec ~enc

let string_of_tag_attachment_type = function AI -> "ai" | Human -> "human"

(** {1 Content Types} *)

type link_content = {
  url : string;
  title : string option;
  description : string option;
  image_url : string option;
  image_asset_id : asset_id option;
  screenshot_asset_id : asset_id option;
  full_page_archive_asset_id : asset_id option;
  precrawled_archive_asset_id : asset_id option;
  video_asset_id : asset_id option;
  favicon : string option;
  html_content : string option;
  crawled_at : Ptime.t option;
  author : string option;
  publisher : string option;
  date_published : Ptime.t option;
  date_modified : Ptime.t option;
}

(** Helper codec for optional string that handles both absent members and null values *)
let string_option = Jsont.option Jsont.string

let link_content_jsont =
  let make url title description image_url image_asset_id screenshot_asset_id
      full_page_archive_asset_id precrawled_archive_asset_id video_asset_id
      favicon html_content crawled_at author publisher date_published date_modified =
    { url; title; description; image_url; image_asset_id; screenshot_asset_id;
      full_page_archive_asset_id; precrawled_archive_asset_id; video_asset_id;
      favicon; html_content; crawled_at; author; publisher; date_published; date_modified }
  in
  Jsont.Object.map ~kind:"link_content" make
  |> Jsont.Object.mem "url" Jsont.string ~enc:(fun l -> l.url)
  |> Jsont.Object.mem "title" string_option ~dec_absent:None ~enc:(fun l -> l.title)
  |> Jsont.Object.mem "description" string_option ~dec_absent:None ~enc:(fun l -> l.description)
  |> Jsont.Object.mem "imageUrl" string_option ~dec_absent:None ~enc:(fun l -> l.image_url)
  |> Jsont.Object.mem "imageAssetId" string_option ~dec_absent:None ~enc:(fun l -> l.image_asset_id)
  |> Jsont.Object.mem "screenshotAssetId" string_option ~dec_absent:None ~enc:(fun l -> l.screenshot_asset_id)
  |> Jsont.Object.mem "fullPageArchiveAssetId" string_option ~dec_absent:None ~enc:(fun l -> l.full_page_archive_asset_id)
  |> Jsont.Object.mem "precrawledArchiveAssetId" string_option ~dec_absent:None ~enc:(fun l -> l.precrawled_archive_asset_id)
  |> Jsont.Object.mem "videoAssetId" string_option ~dec_absent:None ~enc:(fun l -> l.video_asset_id)
  |> Jsont.Object.mem "favicon" string_option ~dec_absent:None ~enc:(fun l -> l.favicon)
  |> Jsont.Object.mem "htmlContent" string_option ~dec_absent:None ~enc:(fun l -> l.html_content)
  |> Jsont.Object.mem "crawledAt" ptime_option_jsont ~dec_absent:None ~enc:(fun l -> l.crawled_at)
  |> Jsont.Object.mem "author" string_option ~dec_absent:None ~enc:(fun l -> l.author)
  |> Jsont.Object.mem "publisher" string_option ~dec_absent:None ~enc:(fun l -> l.publisher)
  |> Jsont.Object.mem "datePublished" ptime_option_jsont ~dec_absent:None ~enc:(fun l -> l.date_published)
  |> Jsont.Object.mem "dateModified" ptime_option_jsont ~dec_absent:None ~enc:(fun l -> l.date_modified)
  |> Jsont.Object.finish

type text_content = {
  text : string;
  source_url : string option;
}

let text_content_jsont =
  let make text source_url = { text; source_url } in
  Jsont.Object.map ~kind:"text_content" make
  |> Jsont.Object.mem "text" Jsont.string ~enc:(fun t -> t.text)
  |> Jsont.Object.mem "sourceUrl" string_option ~dec_absent:None ~enc:(fun t -> t.source_url)
  |> Jsont.Object.finish

type asset_content = {
  asset_type : [ `Image | `PDF ];
  asset_id : asset_id;
  file_name : string option;
  source_url : string option;
  size : int option;
  content : string option;
}

let asset_content_type_jsont =
  let dec s =
    match String.lowercase_ascii s with
    | "image" -> Ok `Image
    | "pdf" -> Ok `PDF
    | _ -> Ok `Image
  in
  let enc = function `Image -> "image" | `PDF -> "pdf"
  in
  Jsont.of_of_string ~kind:"asset_content_type" dec ~enc

let int_option = Jsont.option Jsont.int

let asset_content_jsont =
  let make asset_type asset_id file_name source_url size content =
    { asset_type; asset_id; file_name; source_url; size; content }
  in
  Jsont.Object.map ~kind:"asset_content" make
  |> Jsont.Object.mem "assetType" asset_content_type_jsont ~enc:(fun a -> a.asset_type)
  |> Jsont.Object.mem "assetId" Jsont.string ~enc:(fun a -> a.asset_id)
  |> Jsont.Object.mem "fileName" string_option ~dec_absent:None ~enc:(fun a -> a.file_name)
  |> Jsont.Object.mem "sourceUrl" string_option ~dec_absent:None ~enc:(fun a -> a.source_url)
  |> Jsont.Object.mem "size" int_option ~dec_absent:None ~enc:(fun a -> a.size)
  |> Jsont.Object.mem "content" string_option ~dec_absent:None ~enc:(fun a -> a.content)
  |> Jsont.Object.finish

type content =
  | Link of link_content
  | Text of text_content
  | Asset of asset_content
  | Unknown

(* Content is represented as an object with a "type" field discriminator *)
let content_jsont =
  let link_case = Jsont.Object.Case.map "link" link_content_jsont ~dec:(fun l -> Link l) in
  let text_case = Jsont.Object.Case.map "text" text_content_jsont ~dec:(fun t -> Text t) in
  let asset_case = Jsont.Object.Case.map "asset" asset_content_jsont ~dec:(fun a -> Asset a) in
  let enc_case = function
    | Link l -> Jsont.Object.Case.value link_case l
    | Text t -> Jsont.Object.Case.value text_case t
    | Asset a -> Jsont.Object.Case.value asset_case a
    | Unknown -> Jsont.Object.Case.value link_case { url = ""; title = None; description = None;
        image_url = None; image_asset_id = None; screenshot_asset_id = None;
        full_page_archive_asset_id = None; precrawled_archive_asset_id = None;
        video_asset_id = None; favicon = None; html_content = None; crawled_at = None;
        author = None; publisher = None; date_published = None; date_modified = None }
  in
  let cases = Jsont.Object.Case.[make link_case; make text_case; make asset_case] in
  Jsont.Object.map ~kind:"content" Fun.id
  |> Jsont.Object.case_mem "type" Jsont.string ~enc:Fun.id ~enc_case cases
  |> Jsont.Object.finish

let title content =
  match content with
  | Link l -> Option.value l.title ~default:l.url
  | Text t ->
      let excerpt = if String.length t.text > 50 then String.sub t.text 0 50 ^ "..." else t.text in
      excerpt
  | Asset a -> Option.value a.file_name ~default:"Asset"
  | Unknown -> "Unknown content"

(** {1 Resource Types} *)

type asset = {
  id : asset_id;
  asset_type : asset_type;
}

let asset_jsont =
  let make id asset_type = { id; asset_type } in
  Jsont.Object.map ~kind:"asset" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun a -> a.id)
  |> Jsont.Object.mem "assetType" asset_type_jsont ~enc:(fun a -> a.asset_type)
  |> Jsont.Object.finish

type bookmark_tag = {
  id : tag_id;
  name : string;
  attached_by : tag_attachment_type;
}

let bookmark_tag_jsont =
  let make id name attached_by = { id; name; attached_by } in
  Jsont.Object.map ~kind:"bookmark_tag" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun t -> t.id)
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun t -> t.name)
  |> Jsont.Object.mem "attachedBy" tag_attachment_type_jsont ~enc:(fun t -> t.attached_by)
  |> Jsont.Object.finish

type bookmark = {
  id : bookmark_id;
  created_at : Ptime.t;
  modified_at : Ptime.t option;
  title : string option;
  archived : bool;
  favourited : bool;
  tagging_status : tagging_status option;
  note : string option;
  summary : string option;
  tags : bookmark_tag list;
  content : content;
  assets : asset list;
}

let bookmark_jsont =
  let make id created_at modified_at title archived favourited tagging_status note summary tags content assets =
    { id; created_at; modified_at; title; archived; favourited; tagging_status; note; summary; tags; content; assets }
  in
  Jsont.Object.map ~kind:"bookmark" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun b -> b.id)
  |> Jsont.Object.mem "createdAt" ptime_jsont ~enc:(fun b -> b.created_at)
  |> Jsont.Object.mem "modifiedAt" ptime_option_jsont ~dec_absent:None ~enc:(fun b -> b.modified_at)
  |> Jsont.Object.mem "title" (Jsont.option Jsont.string) ~dec_absent:None ~enc:(fun b -> b.title)
  |> Jsont.Object.mem "archived" Jsont.bool ~dec_absent:false ~enc:(fun b -> b.archived)
  |> Jsont.Object.mem "favourited" Jsont.bool ~dec_absent:false ~enc:(fun b -> b.favourited)
  |> Jsont.Object.mem "taggingStatus" (Jsont.option tagging_status_jsont) ~dec_absent:None ~enc:(fun b -> b.tagging_status)
  |> Jsont.Object.mem "note" (Jsont.option Jsont.string) ~dec_absent:None ~enc:(fun b -> b.note)
  |> Jsont.Object.mem "summary" (Jsont.option Jsont.string) ~dec_absent:None ~enc:(fun b -> b.summary)
  |> Jsont.Object.mem "tags" (Jsont.list bookmark_tag_jsont) ~dec_absent:[] ~enc:(fun b -> b.tags)
  |> Jsont.Object.mem "content" content_jsont ~enc:(fun b -> b.content)
  |> Jsont.Object.mem "assets" (Jsont.list asset_jsont) ~dec_absent:[] ~enc:(fun b -> b.assets)
  |> Jsont.Object.finish

let bookmark_title bookmark =
  match bookmark.title with
  | Some t -> t
  | None -> title bookmark.content

(** {1 Paginated Responses} *)

type paginated_bookmarks = {
  bookmarks : bookmark list;
  next_cursor : string option;
}

let paginated_bookmarks_jsont =
  let make bookmarks next_cursor = { bookmarks; next_cursor } in
  Jsont.Object.map ~kind:"paginated_bookmarks" make
  |> Jsont.Object.mem "bookmarks" (Jsont.list bookmark_jsont) ~dec_absent:[] ~enc:(fun p -> p.bookmarks)
  |> Jsont.Object.mem "nextCursor" string_option ~dec_absent:None ~enc:(fun p -> p.next_cursor)
  |> Jsont.Object.finish

(** {1 List Type} *)

type _list = {
  id : list_id;
  name : string;
  description : string option;
  icon : string;
  parent_id : list_id option;
  list_type : list_type;
  query : string option;
}

let list_jsont =
  let make id name description icon parent_id list_type query =
    { id; name; description; icon; parent_id; list_type; query }
  in
  Jsont.Object.map ~kind:"list" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun l -> l.id)
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun l -> l.name)
  |> Jsont.Object.mem "description" string_option ~dec_absent:None ~enc:(fun l -> l.description)
  |> Jsont.Object.mem "icon" Jsont.string ~dec_absent:"" ~enc:(fun l -> l.icon)
  |> Jsont.Object.mem "parentId" string_option ~dec_absent:None ~enc:(fun l -> l.parent_id)
  |> Jsont.Object.mem "type" list_type_jsont ~dec_absent:Manual ~enc:(fun l -> l.list_type)
  |> Jsont.Object.mem "query" string_option ~dec_absent:None ~enc:(fun l -> l.query)
  |> Jsont.Object.finish

type lists_response = { lists : _list list }

let lists_response_jsont =
  let make lists = { lists } in
  Jsont.Object.map ~kind:"lists_response" make
  |> Jsont.Object.mem "lists" (Jsont.list list_jsont) ~dec_absent:[] ~enc:(fun r -> r.lists)
  |> Jsont.Object.finish

(** {1 Tag Types} *)

type tag = {
  id : tag_id;
  name : string;
  num_bookmarks : int;
  num_bookmarks_by_attached_type : (tag_attachment_type * int) list;
}

(* The API returns numBookmarksByAttachedType as an object like {"ai": 5, "human": 10} *)
let num_bookmarks_by_type_jsont =
  let make ai human =
    let result = [] in
    let result = if ai > 0 then (AI, ai) :: result else result in
    let result = if human > 0 then (Human, human) :: result else result in
    result
  in
  let enc_ai lst = List.assoc_opt AI lst |> Option.value ~default:0 in
  let enc_human lst = List.assoc_opt Human lst |> Option.value ~default:0 in
  Jsont.Object.map ~kind:"num_bookmarks_by_type" make
  |> Jsont.Object.mem "ai" Jsont.int ~dec_absent:0 ~enc:enc_ai
  |> Jsont.Object.mem "human" Jsont.int ~dec_absent:0 ~enc:enc_human
  |> Jsont.Object.finish

let tag_jsont =
  let make id name num_bookmarks num_bookmarks_by_attached_type =
    { id; name; num_bookmarks; num_bookmarks_by_attached_type }
  in
  Jsont.Object.map ~kind:"tag" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun t -> t.id)
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun t -> t.name)
  |> Jsont.Object.mem "numBookmarks" Jsont.int ~dec_absent:0 ~enc:(fun t -> t.num_bookmarks)
  |> Jsont.Object.mem "numBookmarksByAttachedType" num_bookmarks_by_type_jsont
      ~dec_absent:[] ~enc:(fun t -> t.num_bookmarks_by_attached_type)
  |> Jsont.Object.finish

type tags_response = { tags : tag list }

let tags_response_jsont =
  let make tags = { tags } in
  Jsont.Object.map ~kind:"tags_response" make
  |> Jsont.Object.mem "tags" (Jsont.list tag_jsont) ~dec_absent:[] ~enc:(fun r -> r.tags)
  |> Jsont.Object.finish

(** {1 Highlight Types} *)

type highlight = {
  bookmark_id : bookmark_id;
  start_offset : int;
  end_offset : int;
  color : highlight_color;
  text : string option;
  note : string option;
  id : highlight_id;
  user_id : string;
  created_at : Ptime.t;
}

let highlight_jsont =
  let make bookmark_id start_offset end_offset color text note id user_id created_at =
    { bookmark_id; start_offset; end_offset; color; text; note; id; user_id; created_at }
  in
  Jsont.Object.map ~kind:"highlight" make
  |> Jsont.Object.mem "bookmarkId" Jsont.string ~enc:(fun h -> h.bookmark_id)
  |> Jsont.Object.mem "startOffset" Jsont.int ~enc:(fun h -> h.start_offset)
  |> Jsont.Object.mem "endOffset" Jsont.int ~enc:(fun h -> h.end_offset)
  |> Jsont.Object.mem "color" highlight_color_jsont ~dec_absent:Yellow ~enc:(fun h -> h.color)
  |> Jsont.Object.mem "text" string_option ~dec_absent:None ~enc:(fun h -> h.text)
  |> Jsont.Object.mem "note" string_option ~dec_absent:None ~enc:(fun h -> h.note)
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun h -> h.id)
  |> Jsont.Object.mem "userId" Jsont.string ~enc:(fun h -> h.user_id)
  |> Jsont.Object.mem "createdAt" ptime_jsont ~enc:(fun h -> h.created_at)
  |> Jsont.Object.finish

type paginated_highlights = {
  highlights : highlight list;
  next_cursor : string option;
}

let paginated_highlights_jsont =
  let make highlights next_cursor = { highlights; next_cursor } in
  Jsont.Object.map ~kind:"paginated_highlights" make
  |> Jsont.Object.mem "highlights" (Jsont.list highlight_jsont) ~dec_absent:[] ~enc:(fun p -> p.highlights)
  |> Jsont.Object.mem "nextCursor" string_option ~dec_absent:None ~enc:(fun p -> p.next_cursor)
  |> Jsont.Object.finish

type highlights_response = { highlights : highlight list }

let highlights_response_jsont =
  let make highlights = { highlights } in
  Jsont.Object.map ~kind:"highlights_response" make
  |> Jsont.Object.mem "highlights" (Jsont.list highlight_jsont) ~dec_absent:[] ~enc:(fun r -> r.highlights)
  |> Jsont.Object.finish

(** {1 User Types} *)

type user_info = {
  id : string;
  name : string option;
  email : string option;
}

let user_info_jsont =
  let make id name email = { id; name; email } in
  Jsont.Object.map ~kind:"user_info" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun u -> u.id)
  |> Jsont.Object.mem "name" string_option ~dec_absent:None ~enc:(fun u -> u.name)
  |> Jsont.Object.mem "email" string_option ~dec_absent:None ~enc:(fun u -> u.email)
  |> Jsont.Object.finish

type user_stats = {
  num_bookmarks : int;
  num_favorites : int;
  num_archived : int;
  num_tags : int;
  num_lists : int;
  num_highlights : int;
}

let user_stats_jsont =
  let make num_bookmarks num_favorites num_archived num_tags num_lists num_highlights =
    { num_bookmarks; num_favorites; num_archived; num_tags; num_lists; num_highlights }
  in
  Jsont.Object.map ~kind:"user_stats" make
  |> Jsont.Object.mem "numBookmarks" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_bookmarks)
  |> Jsont.Object.mem "numFavourites" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_favorites)
  |> Jsont.Object.mem "numArchived" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_archived)
  |> Jsont.Object.mem "numTags" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_tags)
  |> Jsont.Object.mem "numLists" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_lists)
  |> Jsont.Object.mem "numHighlights" Jsont.int ~dec_absent:0 ~enc:(fun s -> s.num_highlights)
  |> Jsont.Object.finish

(** {1 Error Response} *)

type error_response = {
  code : string;
  message : string;
}

let error_response_jsont =
  let make code message = { code; message } in
  Jsont.Object.map ~kind:"error_response" make
  |> Jsont.Object.mem "code" Jsont.string ~dec_absent:"unknown" ~enc:(fun e -> e.code)
  |> Jsont.Object.mem "message" Jsont.string ~dec_absent:"Unknown error" ~enc:(fun e -> e.message)
  |> Jsont.Object.finish

(** {1 Request Types} *)

type create_bookmark_request = {
  type_ : string;
  url : string option;
  text : string option;
  title : string option;
  note : string option;
  summary : string option;
  archived : bool option;
  favourited : bool option;
  created_at : Ptime.t option;
}

let create_bookmark_request_jsont =
  let make type_ url text title note summary archived favourited created_at =
    { type_; url; text; title; note; summary; archived; favourited; created_at }
  in
  Jsont.Object.map ~kind:"create_bookmark_request" make
  |> Jsont.Object.mem "type" Jsont.string ~enc:(fun r -> r.type_)
  |> Jsont.Object.opt_mem "url" Jsont.string ~enc:(fun r -> r.url)
  |> Jsont.Object.opt_mem "text" Jsont.string ~enc:(fun r -> r.text)
  |> Jsont.Object.opt_mem "title" Jsont.string ~enc:(fun r -> r.title)
  |> Jsont.Object.opt_mem "note" Jsont.string ~enc:(fun r -> r.note)
  |> Jsont.Object.opt_mem "summary" Jsont.string ~enc:(fun r -> r.summary)
  |> Jsont.Object.opt_mem "archived" Jsont.bool ~enc:(fun r -> r.archived)
  |> Jsont.Object.opt_mem "favourited" Jsont.bool ~enc:(fun r -> r.favourited)
  |> Jsont.Object.opt_mem "createdAt" ptime_jsont ~enc:(fun r -> r.created_at)
  |> Jsont.Object.finish

type update_bookmark_request = {
  title : string option;
  note : string option;
  summary : string option;
  archived : bool option;
  favourited : bool option;
}

let update_bookmark_request_jsont =
  let make title note summary archived favourited =
    { title; note; summary; archived; favourited }
  in
  Jsont.Object.map ~kind:"update_bookmark_request" make
  |> Jsont.Object.opt_mem "title" Jsont.string ~enc:(fun r -> r.title)
  |> Jsont.Object.opt_mem "note" Jsont.string ~enc:(fun r -> r.note)
  |> Jsont.Object.opt_mem "summary" Jsont.string ~enc:(fun r -> r.summary)
  |> Jsont.Object.opt_mem "archived" Jsont.bool ~enc:(fun r -> r.archived)
  |> Jsont.Object.opt_mem "favourited" Jsont.bool ~enc:(fun r -> r.favourited)
  |> Jsont.Object.finish

type tag_ref = TagId of tag_id | TagName of string

let tag_ref_jsont =
  (* Each tag ref is an object with either tagId or tagName *)
  let make tagid tagname =
    match tagid, tagname with
    | Some id, _ -> TagId id
    | _, Some name -> TagName name
    | None, None -> TagName ""
  in
  Jsont.Object.map ~kind:"tag_ref" make
  |> Jsont.Object.opt_mem "tagId" Jsont.string ~enc:(function TagId id -> Some id | _ -> None)
  |> Jsont.Object.opt_mem "tagName" Jsont.string ~enc:(function TagName n -> Some n | _ -> None)
  |> Jsont.Object.finish

type attach_tags_request = { tags : tag_ref list }

let attach_tags_request_jsont =
  let make tags = { tags } in
  Jsont.Object.map ~kind:"attach_tags_request" make
  |> Jsont.Object.mem "tags" (Jsont.list tag_ref_jsont) ~enc:(fun r -> r.tags)
  |> Jsont.Object.finish

type attach_tags_response = { attached : tag_id list }

let attach_tags_response_jsont =
  let make attached = { attached } in
  Jsont.Object.map ~kind:"attach_tags_response" make
  |> Jsont.Object.mem "attached" (Jsont.list Jsont.string) ~dec_absent:[] ~enc:(fun r -> r.attached)
  |> Jsont.Object.finish

type detach_tags_response = { detached : tag_id list }

let detach_tags_response_jsont =
  let make detached = { detached } in
  Jsont.Object.map ~kind:"detach_tags_response" make
  |> Jsont.Object.mem "detached" (Jsont.list Jsont.string) ~dec_absent:[] ~enc:(fun r -> r.detached)
  |> Jsont.Object.finish

type create_list_request = {
  name : string;
  icon : string;
  description : string option;
  parent_id : list_id option;
  type_ : string option;
  query : string option;
}

let create_list_request_jsont =
  let make name icon description parent_id type_ query =
    { name; icon; description; parent_id; type_; query }
  in
  Jsont.Object.map ~kind:"create_list_request" make
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun r -> r.name)
  |> Jsont.Object.mem "icon" Jsont.string ~enc:(fun r -> r.icon)
  |> Jsont.Object.opt_mem "description" Jsont.string ~enc:(fun r -> r.description)
  |> Jsont.Object.opt_mem "parentId" Jsont.string ~enc:(fun r -> r.parent_id)
  |> Jsont.Object.opt_mem "type" Jsont.string ~enc:(fun r -> r.type_)
  |> Jsont.Object.opt_mem "query" Jsont.string ~enc:(fun r -> r.query)
  |> Jsont.Object.finish

type update_list_request = {
  name : string option;
  icon : string option;
  description : string option;
  parent_id : list_id option option;
  query : string option;
}

let update_list_request_jsont =
  let make name icon description parent_id query =
    (* parent_id here comes from opt_mem so it's already option *)
    { name; icon; description; parent_id = Some parent_id; query }
  in
  Jsont.Object.map ~kind:"update_list_request" make
  |> Jsont.Object.opt_mem "name" Jsont.string ~enc:(fun r -> r.name)
  |> Jsont.Object.opt_mem "icon" Jsont.string ~enc:(fun r -> r.icon)
  |> Jsont.Object.opt_mem "description" Jsont.string ~enc:(fun r -> r.description)
  |> Jsont.Object.opt_mem "parentId" Jsont.string ~enc:(fun r -> Option.join r.parent_id)
  |> Jsont.Object.opt_mem "query" Jsont.string ~enc:(fun r -> r.query)
  |> Jsont.Object.finish

type create_highlight_request = {
  bookmark_id : bookmark_id;
  start_offset : int;
  end_offset : int;
  text : string;
  note : string option;
  color : highlight_color option;
}

let create_highlight_request_jsont =
  let make bookmark_id start_offset end_offset text note color =
    { bookmark_id; start_offset; end_offset; text; note; color }
  in
  Jsont.Object.map ~kind:"create_highlight_request" make
  |> Jsont.Object.mem "bookmarkId" Jsont.string ~enc:(fun r -> r.bookmark_id)
  |> Jsont.Object.mem "startOffset" Jsont.int ~enc:(fun r -> r.start_offset)
  |> Jsont.Object.mem "endOffset" Jsont.int ~enc:(fun r -> r.end_offset)
  |> Jsont.Object.mem "text" Jsont.string ~enc:(fun r -> r.text)
  |> Jsont.Object.opt_mem "note" Jsont.string ~enc:(fun r -> r.note)
  |> Jsont.Object.opt_mem "color" highlight_color_jsont ~enc:(fun r -> r.color)
  |> Jsont.Object.finish

type update_highlight_request = { color : highlight_color option }

let update_highlight_request_jsont =
  let make color = { color } in
  Jsont.Object.map ~kind:"update_highlight_request" make
  |> Jsont.Object.opt_mem "color" highlight_color_jsont ~enc:(fun r -> r.color)
  |> Jsont.Object.finish

type update_tag_request = { name : string }

let update_tag_request_jsont =
  let make name = { name } in
  Jsont.Object.map ~kind:"update_tag_request" make
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun r -> r.name)
  |> Jsont.Object.finish

type attach_asset_request = {
  id : asset_id;
  asset_type : asset_type;
}

let attach_asset_request_jsont =
  let make id asset_type = { id; asset_type } in
  Jsont.Object.map ~kind:"attach_asset_request" make
  |> Jsont.Object.mem "id" Jsont.string ~enc:(fun r -> r.id)
  |> Jsont.Object.mem "assetType" asset_type_jsont ~enc:(fun r -> r.asset_type)
  |> Jsont.Object.finish

type replace_asset_request = { asset_id : asset_id }

let replace_asset_request_jsont =
  let make asset_id = { asset_id } in
  Jsont.Object.map ~kind:"replace_asset_request" make
  |> Jsont.Object.mem "assetId" Jsont.string ~enc:(fun r -> r.asset_id)
  |> Jsont.Object.finish

type summarize_response = { summary : string }

let summarize_response_jsont =
  let make summary = { summary } in
  Jsont.Object.map ~kind:"summarize_response" make
  |> Jsont.Object.mem "summary" Jsont.string ~enc:(fun r -> r.summary)
  |> Jsont.Object.finish
