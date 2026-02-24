(* webdavz_xml.ml - XML tree types and xmlm codec
   RFC 4918 Section 14 — XML element definitions *)

type fqname = string * string
type attribute = fqname * string

type tree =
  | Pcdata of string
  | Node of string * string * attribute list * tree list

let dav_ns = "DAV:"
let carddav_ns = "urn:ietf:params:xml:ns:carddav"

let[@inline] dav_node name children = Node (dav_ns, name, [], children)
let[@inline] pcdata s = Pcdata s

let find_children ns name children =
  List.filter (fun t ->
    match t with
    | Node (ns', name', _, _) -> String.equal ns ns' && String.equal name name'
    | Pcdata _ -> false)
    children

let[@inline] node_name = function
  | Node (ns, name, _, _) -> Some (ns, name)
  | Pcdata _ -> None

(* xmlm-based parsing — RFC 4918 requires well-formed XML *)
let parse xml_string =
  let input = Xmlm.make_input (`String (0, xml_string)) in
  let rec parse_node () =
    match Xmlm.input input with
    | `El_start ((ns, name), attrs) ->
        let attrs = List.map (fun ((ans, aname), value) ->
          ((ans, aname), value)) attrs
        in
        let children = parse_children [] in
        Some (Node (ns, name, attrs, children))
    | `Data s -> Some (Pcdata s)
    | `El_end -> None
    | `Dtd _ -> parse_node ()
  and parse_children acc =
    match parse_node () with
    | Some node -> parse_children (node :: acc)
    | None -> List.rev acc
  in
  try
    match parse_node () with
    | Some tree -> Some tree
    | None -> None
  with Xmlm.Error _ -> None

(* xmlm-based serialization — compact output, no XML declaration *)
let serialize tree =
  let buf = Buffer.create 1024 in
  let output = Xmlm.make_output ~decl:false (`Buffer buf) in
  let rec write_tree = function
    | Pcdata s -> Xmlm.output output (`Data s)
    | Node (ns, name, attrs, children) ->
        let attrs = List.map (fun ((ans, aname), value) ->
          ((ans, aname), value)) attrs
        in
        Xmlm.output output (`El_start (((ns, name), attrs)));
        List.iter write_tree children;
        Xmlm.output output `El_end
  in
  Xmlm.output output (`Dtd None);
  write_tree tree;
  Buffer.contents buf
