(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep configuration management with XDG support.

    This module provides profile-based credential storage following XDG
    Base Directory conventions. Configuration is stored in TOML format at:

    {v
    ~/.config/karakeep/
    ├── config.toml           # Global settings (current profile)
    └── profiles/
        ├── default/
        │   └── credentials.toml
        └── work/
            └── credentials.toml
    v}
*)

(** {1 Configuration Types} *)

type credentials = {
  api_key : string;
  base_url : string;
}
(** Stored credentials for a Karakeep instance. *)

(** {1 Constants} *)

val app_name : string
(** The application name ["karakeep"], used for XDG directory paths. *)

val default_base_url : string
(** Default Karakeep instance URL. *)

val default_profile : string
(** Name of the default profile. *)

(** {1 Directory Paths} *)

val base_config_dir : Eio.Fs.dir_ty Eio.Path.t -> Eio.Fs.dir_ty Eio.Path.t
(** [base_config_dir fs] returns the base config directory for karakeep.
    Creates the directory if it doesn't exist. *)

val profiles_dir : Eio.Fs.dir_ty Eio.Path.t -> Eio.Fs.dir_ty Eio.Path.t
(** [profiles_dir fs] returns the profiles subdirectory.
    Creates the directory if it doesn't exist. *)

val profile_dir : Eio.Fs.dir_ty Eio.Path.t -> string -> Eio.Fs.dir_ty Eio.Path.t
(** [profile_dir fs profile] returns the directory for a specific profile.
    Creates the directory if it doesn't exist. *)

(** {1 Profile Management} *)

val get_current_profile : Eio.Fs.dir_ty Eio.Path.t -> string
(** [get_current_profile fs] returns the current profile name.
    Returns ["default"] if no profile is set. *)

val set_current_profile : Eio.Fs.dir_ty Eio.Path.t -> string -> unit
(** [set_current_profile fs name] sets the current profile. *)

val list_profiles : Eio.Fs.dir_ty Eio.Path.t -> string list
(** [list_profiles fs] returns all available profile names. *)

(** {1 Credential Storage} *)

val load_credentials : Eio.Fs.dir_ty Eio.Path.t -> ?profile:string -> unit -> credentials option
(** [load_credentials fs ?profile ()] loads credentials for a profile.
    Uses current profile if not specified. Returns [None] if not found. *)

val save_credentials : Eio.Fs.dir_ty Eio.Path.t -> ?profile:string -> credentials -> unit
(** [save_credentials fs ?profile creds] saves credentials to a profile.
    Uses current profile if not specified. *)

val clear_credentials : Eio.Fs.dir_ty Eio.Path.t -> ?profile:string -> unit -> unit
(** [clear_credentials fs ?profile ()] removes credentials for a profile.
    Uses current profile if not specified. *)

(** {1 Legacy Migration} *)

val load_legacy_api_key : unit -> string option
(** [load_legacy_api_key ()] attempts to read API key from legacy locations:
    1. KARAKEEP_API_KEY environment variable
    2. .karakeep-api file in current directory *)
