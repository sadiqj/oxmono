(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep API protocol types and JSON codecs

    This module provides type definitions and jsont codecs for the Karakeep
    bookmark service API protocol messages. *)

(** {1 ID Types} *)

type asset_id = string
(** Asset identifier type *)

type bookmark_id = string
(** Bookmark identifier type *)

type list_id = string
(** List identifier type *)

type tag_id = string
(** Tag identifier type *)

type highlight_id = string
(** Highlight identifier type *)

(** {1 Enum Types} *)

(** Type of content a bookmark can have *)
type bookmark_content_type =
  | Link  (** A URL to a webpage *)
  | Text  (** Plain text content *)
  | Asset  (** An attached asset (image, PDF, etc.) *)
  | Unknown  (** Unknown content type *)

val bookmark_content_type_jsont : bookmark_content_type Jsont.t

(** Type of asset *)
type asset_type =
  | Screenshot  (** Screenshot of a webpage *)
  | AssetScreenshot  (** Screenshot of an asset *)
  | BannerImage  (** Banner image *)
  | FullPageArchive  (** Archive of a full webpage *)
  | Video  (** Video asset *)
  | BookmarkAsset  (** Generic bookmark asset *)
  | PrecrawledArchive  (** Pre-crawled archive *)
  | Unknown  (** Unknown asset type *)

val asset_type_jsont : asset_type Jsont.t

(** Type of tagging status *)
type tagging_status =
  | Success  (** Tagging was successful *)
  | Failure  (** Tagging failed *)
  | Pending  (** Tagging is pending *)

val tagging_status_jsont : tagging_status Jsont.t
val string_of_tagging_status : tagging_status -> string

(** Type of bookmark list *)
type list_type =
  | Manual  (** List is manually managed *)
  | Smart  (** List is dynamically generated based on a query *)

val list_type_jsont : list_type Jsont.t

(** Highlight color *)
type highlight_color =
  | Yellow  (** Yellow highlight *)
  | Red  (** Red highlight *)
  | Green  (** Green highlight *)
  | Blue  (** Blue highlight *)

val highlight_color_jsont : highlight_color Jsont.t
val string_of_highlight_color : highlight_color -> string

(** Type of how a tag was attached *)
type tag_attachment_type =
  | AI  (** Tag was attached by AI *)
  | Human  (** Tag was attached by a human *)

val tag_attachment_type_jsont : tag_attachment_type Jsont.t
val string_of_tag_attachment_type : tag_attachment_type -> string

(** {1 Content Types} *)

type link_content = {
  url : string;  (** The URL of the bookmarked page *)
  title : string option;  (** Title from the link *)
  description : string option;  (** Description from the link *)
  image_url : string option;  (** URL of an image from the link *)
  image_asset_id : asset_id option;  (** ID of an image asset *)
  screenshot_asset_id : asset_id option;  (** ID of a screenshot asset *)
  full_page_archive_asset_id : asset_id option;
      (** ID of a full page archive asset *)
  precrawled_archive_asset_id : asset_id option;
      (** ID of a pre-crawled archive asset *)
  video_asset_id : asset_id option;  (** ID of a video asset *)
  favicon : string option;  (** URL of the favicon *)
  html_content : string option;  (** HTML content of the page *)
  crawled_at : Ptime.t option;  (** When the page was crawled *)
  author : string option;  (** Author of the content *)
  publisher : string option;  (** Publisher of the content *)
  date_published : Ptime.t option;  (** When the content was published *)
  date_modified : Ptime.t option;  (** When the content was last modified *)
}
(** Link content for a bookmark *)

val link_content_jsont : link_content Jsont.t

type text_content = {
  text : string;  (** The text content *)
  source_url : string option;  (** Optional source URL for the text *)
}
(** Text content for a bookmark *)

val text_content_jsont : text_content Jsont.t

type asset_content = {
  asset_type : [ `Image | `PDF ];  (** Type of the asset *)
  asset_id : asset_id;  (** ID of the asset *)
  file_name : string option;  (** Name of the file *)
  source_url : string option;  (** Source URL for the asset *)
  size : int option;  (** Size of the asset in bytes *)
  content : string option;  (** Extracted content from the asset *)
}
(** Asset content for a bookmark *)

val asset_content_jsont : asset_content Jsont.t

(** Content of a bookmark *)
type content =
  | Link of link_content  (** Link-type content *)
  | Text of text_content  (** Text-type content *)
  | Asset of asset_content  (** Asset-type content *)
  | Unknown  (** Unknown content type *)

val content_jsont : content Jsont.t

val title : content -> string
(** [title content] extracts a meaningful title from the bookmark content.
    For Link content, it returns the title if available, otherwise the URL.
    For Text content, it returns a short excerpt from the text.
    For Asset content, it returns the filename if available, otherwise a
    generic title.
    For Unknown content, it returns a generic title. *)

(** {1 Resource Types} *)

type asset = {
  id : asset_id;  (** ID of the asset *)
  asset_type : asset_type;  (** Type of the asset *)
}
(** Asset attached to a bookmark *)

val asset_jsont : asset Jsont.t

type bookmark_tag = {
  id : tag_id;  (** ID of the tag *)
  name : string;  (** Name of the tag *)
  attached_by : tag_attachment_type;  (** How the tag was attached *)
}
(** Tag with attachment information *)

val bookmark_tag_jsont : bookmark_tag Jsont.t

type bookmark = {
  id : bookmark_id;  (** Unique identifier for the bookmark *)
  created_at : Ptime.t;  (** Timestamp when the bookmark was created *)
  modified_at : Ptime.t option;  (** Optional timestamp of the last update *)
  title : string option;  (** Optional title of the bookmarked page *)
  archived : bool;  (** Whether the bookmark is archived *)
  favourited : bool;  (** Whether the bookmark is marked as a favorite *)
  tagging_status : tagging_status option;  (** Status of automatic tagging *)
  note : string option;  (** Optional user note associated with the bookmark *)
  summary : string option;  (** Optional AI-generated summary *)
  tags : bookmark_tag list;  (** Tags associated with the bookmark *)
  content : content;  (** Content of the bookmark *)
  assets : asset list;  (** Assets attached to the bookmark *)
}
(** A bookmark from the Karakeep service *)

val bookmark_jsont : bookmark Jsont.t

val bookmark_title : bookmark -> string
(** [bookmark_title bookmark] returns the best available title for a bookmark.
    It prioritizes the bookmark's title field if available, and falls back to
    extracting a title from the bookmark's content. *)

(** {1 Paginated Responses} *)

type paginated_bookmarks = {
  bookmarks : bookmark list;  (** List of bookmarks in the current page *)
  next_cursor : string option;  (** Optional cursor for fetching the next page *)
}
(** Paginated response of bookmarks *)

val paginated_bookmarks_jsont : paginated_bookmarks Jsont.t

(** {1 List Type} *)

type _list = {
  id : list_id;  (** ID of the list *)
  name : string;  (** Name of the list *)
  description : string option;  (** Optional description of the list *)
  icon : string;  (** Icon for the list *)
  parent_id : list_id option;  (** Optional parent list ID *)
  list_type : list_type;  (** Type of the list *)
  query : string option;  (** Optional query for smart lists *)
}
(** List in Karakeep *)

val list_jsont : _list Jsont.t

type lists_response = { lists : _list list }
(** Response containing a list of lists *)

val lists_response_jsont : lists_response Jsont.t

(** {1 Tag Types} *)

type tag = {
  id : tag_id;  (** ID of the tag *)
  name : string;  (** Name of the tag *)
  num_bookmarks : int;  (** Number of bookmarks with this tag *)
  num_bookmarks_by_attached_type : (tag_attachment_type * int) list;
      (** Number of bookmarks by attachment type *)
}
(** Tag in Karakeep *)

val tag_jsont : tag Jsont.t

type tags_response = { tags : tag list }
(** Response containing a list of tags *)

val tags_response_jsont : tags_response Jsont.t

(** {1 Highlight Types} *)

type highlight = {
  bookmark_id : bookmark_id;  (** ID of the bookmark *)
  start_offset : int;  (** Start position of the highlight *)
  end_offset : int;  (** End position of the highlight *)
  color : highlight_color;  (** Color of the highlight *)
  text : string option;  (** Text of the highlight *)
  note : string option;  (** Note for the highlight *)
  id : highlight_id;  (** ID of the highlight *)
  user_id : string;  (** ID of the user who created the highlight *)
  created_at : Ptime.t;  (** When the highlight was created *)
}
(** Highlight in Karakeep *)

val highlight_jsont : highlight Jsont.t

type paginated_highlights = {
  highlights : highlight list;  (** List of highlights in the current page *)
  next_cursor : string option;  (** Optional cursor for fetching the next page *)
}
(** Paginated response of highlights *)

val paginated_highlights_jsont : paginated_highlights Jsont.t

type highlights_response = { highlights : highlight list }
(** Response containing a list of highlights *)

val highlights_response_jsont : highlights_response Jsont.t

(** {1 User Types} *)

type user_info = {
  id : string;  (** ID of the user *)
  name : string option;  (** Name of the user *)
  email : string option;  (** Email of the user *)
}
(** User information *)

val user_info_jsont : user_info Jsont.t

type user_stats = {
  num_bookmarks : int;  (** Number of bookmarks *)
  num_favorites : int;  (** Number of favorite bookmarks *)
  num_archived : int;  (** Number of archived bookmarks *)
  num_tags : int;  (** Number of tags *)
  num_lists : int;  (** Number of lists *)
  num_highlights : int;  (** Number of highlights *)
}
(** User statistics *)

val user_stats_jsont : user_stats Jsont.t

(** {1 Error Response} *)

type error_response = {
  code : string;  (** Error code *)
  message : string;  (** Error message *)
}
(** Error response from the API *)

val error_response_jsont : error_response Jsont.t

(** {1 Request Types} *)

type create_bookmark_request = {
  type_ : string;  (** Bookmark type: "link", "text", or "asset" *)
  url : string option;  (** URL for link bookmarks *)
  text : string option;  (** Text for text bookmarks *)
  title : string option;  (** Optional title *)
  note : string option;  (** Optional note *)
  summary : string option;  (** Optional summary *)
  archived : bool option;  (** Whether to archive *)
  favourited : bool option;  (** Whether to favourite *)
  created_at : Ptime.t option;  (** Optional creation timestamp *)
}
(** Request to create a bookmark *)

val create_bookmark_request_jsont : create_bookmark_request Jsont.t

type update_bookmark_request = {
  title : string option;
  note : string option;
  summary : string option;
  archived : bool option;
  favourited : bool option;
}
(** Request to update a bookmark *)

val update_bookmark_request_jsont : update_bookmark_request Jsont.t

type tag_ref =
  | TagId of tag_id
  | TagName of string

type attach_tags_request = { tags : tag_ref list }
(** Request to attach tags to a bookmark *)

val attach_tags_request_jsont : attach_tags_request Jsont.t

type attach_tags_response = { attached : tag_id list }
(** Response from attaching tags *)

val attach_tags_response_jsont : attach_tags_response Jsont.t

type detach_tags_response = { detached : tag_id list }
(** Response from detaching tags *)

val detach_tags_response_jsont : detach_tags_response Jsont.t

type create_list_request = {
  name : string;
  icon : string;
  description : string option;
  parent_id : list_id option;
  type_ : string option;  (** "manual" or "smart" *)
  query : string option;
}
(** Request to create a list *)

val create_list_request_jsont : create_list_request Jsont.t

type update_list_request = {
  name : string option;
  icon : string option;
  description : string option;
  parent_id : list_id option option;  (** None to not update, Some None to clear *)
  query : string option;
}
(** Request to update a list *)

val update_list_request_jsont : update_list_request Jsont.t

type create_highlight_request = {
  bookmark_id : bookmark_id;
  start_offset : int;
  end_offset : int;
  text : string;
  note : string option;
  color : highlight_color option;
}
(** Request to create a highlight *)

val create_highlight_request_jsont : create_highlight_request Jsont.t

type update_highlight_request = { color : highlight_color option }
(** Request to update a highlight *)

val update_highlight_request_jsont : update_highlight_request Jsont.t

type update_tag_request = { name : string }
(** Request to update a tag *)

val update_tag_request_jsont : update_tag_request Jsont.t

type attach_asset_request = {
  id : asset_id;
  asset_type : asset_type;
}
(** Request to attach an asset *)

val attach_asset_request_jsont : attach_asset_request Jsont.t

type replace_asset_request = { asset_id : asset_id }
(** Request to replace an asset *)

val replace_asset_request_jsont : replace_asset_request Jsont.t

type summarize_response = { summary : string }
(** Response from summarize bookmark endpoint *)

val summarize_response_jsont : summarize_response Jsont.t

(** {1 Helper Codecs} *)

val ptime_jsont : Ptime.t Jsont.t
(** Codec for Ptime.t values (ISO 8601 format) *)

val ptime_option_jsont : Ptime.t option Jsont.t
(** Codec for optional Ptime.t values *)
