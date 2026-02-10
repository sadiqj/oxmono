(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

open Cmdliner

(* Common terms *)

let profile_term =
  let doc = "Profile name (default: current profile)." in
  Arg.(
    value
    & opt (some string) None
    & info [ "profile"; "P" ] ~docv:"PROFILE" ~doc)

let base_url_term =
  let doc = "Base URL of the Karakeep instance." in
  let env = Cmd.Env.info "KARAKEEP_BASE_URL" ~doc in
  Arg.(
    value
    & opt string Karakeep_config.default_base_url
    & info [ "base-url"; "u" ] ~docv:"URL" ~doc ~env)

let profile_name_arg =
  let doc = "Profile name." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"PROFILE" ~doc)

(* Helper to run with filesystem *)
let with_fs f =
  Eio_main.run @@ fun env -> f env#fs

(* Login command *)

let login_action ~profile ~base_url fs =
  (* Prompt for API key *)
  Fmt.pr "API Key: @?";
  let api_key = read_line () |> String.trim in
  if api_key = "" then begin
    Fmt.epr "Error: API key cannot be empty.@.";
    1
  end else begin
    let creds : Karakeep_config.credentials = { api_key; base_url } in
    (* Determine profile name *)
    let profile_name = match profile with
      | Some p -> p
      | None ->
          let profiles = Karakeep_config.list_profiles fs in
          if profiles = [] then Karakeep_config.default_profile
          else Karakeep_config.get_current_profile fs
    in
    (* Save credentials *)
    Karakeep_config.save_credentials fs ~profile:profile_name creds;
    (* Set as current profile if first login or explicitly requested *)
    let profiles = Karakeep_config.list_profiles fs in
    if List.length profiles <= 1 || Option.is_some profile then
      Karakeep_config.set_current_profile fs profile_name;
    Fmt.pr "Configured profile '%s' for %s@." profile_name base_url;
    0
  end

let login_cmd () =
  let doc = "Configure API credentials for a Karakeep instance." in
  let man = [
    `S Manpage.s_description;
    `P "Prompts for an API key and saves it to the specified profile.";
    `P "API keys can be generated from your Karakeep instance settings.";
    `S "EXAMPLES";
    `P "$(b,karakeep auth login)";
    `Noblank;
    `P "    Login with default profile.";
    `P "$(b,karakeep auth login --profile work --base-url https://work.example.com)";
    `Noblank;
    `P "    Configure a work profile with a different instance.";
  ] in
  let info = Cmd.info "login" ~doc ~man in
  let login' profile base_url = with_fs (login_action ~profile ~base_url) in
  Cmd.v info Term.(const login' $ profile_term $ base_url_term)

(* Logout command *)

let logout_action ~profile fs =
  let profile_name = match profile with
    | Some p -> p
    | None -> Karakeep_config.get_current_profile fs
  in
  match Karakeep_config.load_credentials fs ~profile:profile_name () with
  | None ->
      Fmt.pr "Profile '%s' has no stored credentials.@." profile_name;
      0
  | Some _ ->
      Karakeep_config.clear_credentials fs ~profile:profile_name ();
      Fmt.pr "Removed credentials for profile '%s'.@." profile_name;
      0

let logout_cmd () =
  let doc = "Remove stored credentials." in
  let info = Cmd.info "logout" ~doc in
  let logout' profile = with_fs (logout_action ~profile) in
  Cmd.v info Term.(const logout' $ profile_term)

(* Status command *)

let status_action ~profile fs =
  let home = Sys.getenv "HOME" in
  Fmt.pr "Config directory: %s/.config/%s@." home Karakeep_config.app_name;
  let current = Karakeep_config.get_current_profile fs in
  Fmt.pr "Current profile: %s@." current;
  let profiles = Karakeep_config.list_profiles fs in
  if profiles <> [] then
    Fmt.pr "Available profiles: %s@." (String.concat ", " profiles);
  Fmt.pr "@.";
  let profile_name = match profile with
    | Some p -> p
    | None -> current
  in
  match Karakeep_config.load_credentials fs ~profile:profile_name () with
  | None ->
      Fmt.pr "Profile '%s': Not configured.@." profile_name;
      Fmt.pr "Use 'karakeep auth login' to configure.@.";
      0
  | Some creds ->
      Fmt.pr "Profile '%s':@." profile_name;
      Fmt.pr "  Base URL: %s@." creds.base_url;
      Fmt.pr "  API Key: %s...%s@."
        (String.sub creds.api_key 0 4)
        (String.sub creds.api_key (String.length creds.api_key - 4) 4);
      0

let status_cmd () =
  let doc = "Show authentication status." in
  let info = Cmd.info "status" ~doc in
  let status' profile = with_fs (status_action ~profile) in
  Cmd.v info Term.(const status' $ profile_term)

(* Profile list command *)

let profile_list_action fs =
  let current = Karakeep_config.get_current_profile fs in
  let profiles = Karakeep_config.list_profiles fs in
  if profiles = [] then begin
    Fmt.pr "No profiles found. Use 'karakeep auth login' to create one.@.";
    0
  end else begin
    Fmt.pr "Profiles:@.";
    List.iter (fun p ->
      let marker = if p = current then " (current)" else "" in
      match Karakeep_config.load_credentials fs ~profile:p () with
      | Some creds -> Fmt.pr "  %s%s - %s@." p marker creds.base_url
      | None -> Fmt.pr "  %s%s@." p marker
    ) profiles;
    0
  end

let profile_list_cmd () =
  let doc = "List available profiles." in
  let info = Cmd.info "list" ~doc in
  let list' () = with_fs profile_list_action in
  Cmd.v info Term.(const list' $ const ())

(* Profile switch command *)

let profile_switch_action ~profile fs =
  let profiles = Karakeep_config.list_profiles fs in
  if List.mem profile profiles then begin
    Karakeep_config.set_current_profile fs profile;
    Fmt.pr "Switched to profile: %s@." profile;
    0
  end else begin
    Fmt.epr "Profile '%s' not found.@." profile;
    if profiles <> [] then
      Fmt.epr "Available profiles: %s@." (String.concat ", " profiles);
    1
  end

let profile_switch_cmd () =
  let doc = "Switch to a different profile." in
  let info = Cmd.info "switch" ~doc in
  let switch' profile = with_fs (profile_switch_action ~profile) in
  Cmd.v info Term.(const switch' $ profile_name_arg)

(* Profile current command *)

let profile_current_action fs =
  let current = Karakeep_config.get_current_profile fs in
  Fmt.pr "%s@." current;
  0

let profile_current_cmd () =
  let doc = "Show current profile name." in
  let info = Cmd.info "current" ~doc in
  let current' () = with_fs profile_current_action in
  Cmd.v info Term.(const current' $ const ())

(* Profile command group *)

let profile_cmd () =
  let doc = "Profile management commands." in
  let info = Cmd.info "profile" ~doc in
  Cmd.group info [
    profile_list_cmd ();
    profile_switch_cmd ();
    profile_current_cmd ();
  ]

(* Auth command group *)

let auth_cmd () =
  let doc = "Authentication commands." in
  let man = [
    `S Manpage.s_description;
    `P "Manage authentication credentials for Karakeep instances.";
    `P "Credentials are stored in ~/.config/karakeep/profiles/<name>/credentials.toml";
  ] in
  let info = Cmd.info "auth" ~doc ~man in
  Cmd.group info [
    login_cmd ();
    logout_cmd ();
    status_cmd ();
    profile_cmd ();
  ]
