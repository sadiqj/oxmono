(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep authentication CLI commands.

    Provides commands for managing API key credentials across multiple profiles. *)

(** {1 Command Line Terms} *)

val profile_term : string option Cmdliner.Term.t
(** Cmdliner term for [--profile] / [-P] flag. *)

(** {1 Commands} *)

val login_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth login] - Configure API credentials for a profile. *)

val logout_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth logout] - Remove stored credentials. *)

val status_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth status] - Show authentication status. *)

val profile_list_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth profile list] - List available profiles. *)

val profile_switch_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth profile switch] - Switch to a different profile. *)

val profile_current_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth profile current] - Show current profile name. *)

val profile_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth profile] - Profile management command group. *)

val auth_cmd : unit -> int Cmdliner.Cmd.t
(** [karakeep auth] - Authentication command group. *)
