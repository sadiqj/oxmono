(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Video component rendering using htmlit. *)

open Htmlit

module Video = Bushel.Video

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_short (y, m, _d) =
  Printf.sprintf "%s %4d" (month_name m) y

(** Render a heading for a video entry. *)
let heading ~ctx:_ v =
  El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
    El.a ~at:[At.href (Bushel.Entry.site_url (`Video v))] [
      El.txt (Video.title v)];
    El.span ~at:[At.class' "text-sm text-secondary"] [
      El.txt " / ";
      El.txt (ptime_date_short (Video.date v))]]

(** Brief video rendering with embed/image and description. *)
let brief ~ctx v =
  let md =
    Printf.sprintf "![%%c](:%s)\n\n%s" v.Video.slug v.Video.description
  in
  let body = [
    heading ~ctx v;
    El.unsafe_raw (fst (Arod.Md.to_html ~ctx md))] in
  (El.div body, None)

(** Full video display. *)
let full ~ctx v = fst (brief ~ctx v)

(** Video for feeds. *)
let for_feed ~ctx v =
  let md = Printf.sprintf "![%%c](:%s)\n\n" v.Video.slug in
  (El.unsafe_raw (fst (Arod.Md.to_html ~ctx md)), None)
