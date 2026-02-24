(** WebDAV protocol library for httpz.

    Provides XML types, PROPFIND/PROPPATCH request parsing,
    207 Multi-Status response generation, and a generic STORE-based
    handler for serving WebDAV resources.

    {{:https://datatracker.ietf.org/doc/html/rfc4918}RFC 4918} *)

module Xml = Webdavz_xml
module Prop = Webdavz_prop
module Request = Webdavz_request
module Response = Webdavz_response
module Handler = Webdavz_handler

module type STORE = Webdavz_handler.STORE
