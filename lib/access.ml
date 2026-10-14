open! Core

module Config = struct
  type t =
    { model : Role_model.t
    ; team_policy : Team.Policy.t
    ; invitation_policy : Invitation.Policy.t
    ; new_token : unit -> Token.t
    ; audit_denials : bool
    ; max_attempts : int
    }

  let default =
    { model = Role_model.default
    ; team_policy = Team.Policy.default
    ; invitation_policy = Invitation.Policy.default
    ; new_token = Token.random
    ; audit_denials = true
    ; max_attempts = 3
    }
  ;;
end

module Error = struct
  type t =
    | Not_found
    | Exists
    | Denied of Reason.t
    | Team of Team.Error.t
    | Invitation of Invitation.Error.t
    | Approval of Approval.Error.t
    | Conflict
  [@@deriving sexp_of, compare, equal]

  let code = function
    | Not_found -> "not_found"
    | Exists -> "exists"
    | Conflict -> "conflict"
    | Denied reason -> Reason.code reason
    | Team e -> Team.Error.code e
    | Invitation e -> Invitation.Error.code e
    | Approval e -> Approval.Error.code e
  ;;
end

module Make (M : Monad.S) (S : Store.S with type 'a io := 'a M.t) = struct
  open M.Let_syntax

  let note ~at ~actor events = { Store.Note.at; actor; events }

  (* Binds over [(_, Error.t) result M.t]. *)
  let ( let*! ) x f =
    match%bind x with
    | Error e -> return (Error e)
    | Ok v -> f v
  ;;

  let ( let*? ) r f =
    match r with
    | Error e -> return (Error e)
    | Ok v -> f v
  ;;

  let retrying (config : Config.t) attempt =
    let rec go n =
      match%bind attempt () with
      | `Retry when n + 1 < config.max_attempts -> go (n + 1)
      | `Retry -> return (Error Error.Conflict)
      | `Done r -> return r
    in
    go 0
  ;;

  (* The membership [decide] should see: the one in [org] if any, otherwise one elsewhere
     (which [decide] reports as [Other_organisation]), otherwise none. *)
  let membership_for s ~user ~org =
    let%map memberships = S.memberships s user in
    match List.find memberships ~f:(fun m -> Org_id.equal m.org org) with
    | Some m -> Some m
    | None -> List.hd memberships
  ;;

  let audit_denial (config : Config.t) s ~org ~user ~at action reason =
    if config.audit_denials
    then
      S.append_audit
        s
        org
        (note
           ~at
           ~actor:(Some user)
           [ Access_denied { action; code = Reason.code reason } ])
    else return ()
  ;;

  (* Audits a refusal that came from an access check inside a workflow. *)
  let denied config s ~org ~user ~at action (e : Error.t) =
    let reason =
      match e with
      | Denied r | Team (Denied r) | Approval (Denied r) -> Some r
      | _ -> None
    in
    match reason with
    | None -> return (Error e)
    | Some r ->
      let%map () = audit_denial config s ~org ~user ~at action r in
      (match r with
       | Other_organisation | Not_a_member -> Error Error.Not_found
       | _ -> Error e)
  ;;

  let create_organisation
    (config : Config.t)
    s
    ~id
    ~name
    ~creator
    ~email
    ?display_name
    ~at
    ()
    =
    match Organisation.create ~id ~name ~created_by:creator ~at with
    | Error e -> return (Error (Error.Team (Invalid (Core.Error.to_string_hum e))))
    | Ok organisation ->
      let*? team, _changes =
        Team.found config.model organisation ~email ?display_name ~at ()
        |> Result.map_error ~f:(fun e -> Error.Team e)
      in
      let founder = List.hd_exn team.members in
      let%bind elsewhere = S.memberships s creator in
      if config.team_policy.single_membership && not (List.is_empty elsewhere)
      then return (Error (Error.Team (Member_elsewhere (List.hd_exn elsewhere).org)))
      else (
        match%map
          S.create_organisation
            s
            organisation
            ~founder
            (note
               ~at
               ~actor:(Some creator)
               [ Organisation_created { name = organisation.name }
               ; Member_added { user = creator; role = founder.role; invitation = None }
               ])
        with
        | `Exists _ -> Error Error.Exists
        | `Created -> Ok team)
  ;;

  let update_organisation s org ~actor ~at ~f ~event =
    match%bind S.organisation s org with
    | None -> return (Error Error.Not_found)
    | Some o ->
      let o' = f o in
      if Organisation.equal o o'
      then return (Ok o)
      else (
        let%map () = S.save_organisation s o' (note ~at ~actor [ event ]) in
        Ok o')
  ;;

  let set_verified s org verified ~actor ~at =
    update_organisation
      s
      org
      ~actor
      ~at
      ~f:(fun o -> Organisation.set_verified o verified)
      ~event:(Organisation_verified { verified })
  ;;

  let set_status s org status ~actor ~at =
    update_organisation
      s
      org
      ~actor
      ~at
      ~f:(fun o -> Organisation.set_status o status)
      ~event:(Organisation_status_changed { status })
  ;;

  let decide_loaded (config : Config.t) s ~user ~org action =
    let%bind organisation = S.organisation s org in
    let%map membership = membership_for s ~user ~org in
    match organisation with
    | Some organisation ->
      Some organisation, Authorize.decide config.model ~organisation ~membership action
    | None ->
      ( None
      , Denied
          (match membership with
           | Some _ -> Other_organisation
           | None -> Not_a_member) )
  ;;

  let authorize config s ~user ~org action ~at =
    let%bind organisation, decision = decide_loaded config s ~user ~org action in
    match decision, organisation with
    | Denied reason, Some _ ->
      let%map () = audit_denial config s ~org ~user ~at action reason in
      decision
    | _ -> return decision
  ;;

  (* Authorizes [user] for [action] in [org], turning a refusal into [Error] (audited) and
     an unknown organisation into [Not_found]. *)
  let require config s ~user ~org action ~at =
    let%bind organisation, decision = decide_loaded config s ~user ~org action in
    match organisation, decision with
    | None, _ -> return (Error Error.Not_found)
    | Some o, Allowed _ -> return (Ok o)
    | Some _, Denied ((Other_organisation | Not_a_member) as reason) ->
      (* An outsider sees the same answer as for an organisation that does not exist. *)
      let%map () = audit_denial config s ~org ~user ~at action reason in
      Error Error.Not_found
    | Some _, Denied reason ->
      let%map () = audit_denial config s ~org ~user ~at action reason in
      Error (Error.Denied reason)
  ;;

  let load_team (config : Config.t) s org =
    let%map team = S.team s org in
    Option.map team ~f:(fun (t : Team.t) ->
      Team.of_members config.model t.organisation t.members ~version:t.version)
  ;;

  let custodian_action (config : Config.t) =
    Action.requires (Role_model.custodian config.model)
  ;;

  let team config s ~user ~org ~at =
    let*! (_ : Organisation.t) = require config s ~user ~org Action.read ~at in
    match%map load_team config s org with
    | None -> Error Error.Not_found
    | Some t -> Ok t
  ;;

  (* Loads the team, runs [op] and writes its changes with [events], retrying on a
     concurrent change. [op] returns the value to answer with and the audit events. *)
  let team_write config s ~org ~actor ~at ~action op =
    let%bind result =
      retrying config (fun () ->
        match%bind load_team config s org with
        | None -> return (`Done (Error Error.Not_found))
        | Some team ->
          let%bind r = op team in
          (match r with
           | Error e -> return (`Done (Error e))
           | Ok ((_ : Team.t), [], answer, _events) -> return (`Done (Ok answer))
           | Ok ((_ : Team.t), changes, answer, events) ->
             (match%map
                S.update_team
                  s
                  org
                  ~expected_version:team.version
                  changes
                  (note ~at ~actor:(Some actor) events)
              with
              | `Ok -> `Done (Ok answer)
              | `Conflict -> `Retry)))
    in
    match result with
    | Ok _ -> return result
    | Error e -> denied config s ~org ~user:actor ~at action e
  ;;

  let team_error r = Result.map_error r ~f:(fun e -> Error.Team e)
  let other_memberships s user = S.memberships s user

  let add_member (config : Config.t) s ~actor ~org ~user ~email ?display_name ~role ~at ()
    =
    let%bind actor_m = membership_for s ~user:actor ~org in
    team_write config s ~org ~actor ~at ~action:(custodian_action config) (fun team ->
      let%map others = other_memberships s user in
      let%map.Result team', changes =
        Team.add
          ~policy:config.team_policy
          config.model
          team
          ~actor:actor_m
          ~user
          ~email
          ?display_name
          ~role
          ~other_memberships:others
          ~at
          ()
        |> team_error
      in
      let member = Option.value_exn (Team.find team' user) in
      ( team'
      , changes
      , member
      , [ Audit.Event.Member_added { user; role; invitation = None } ] ))
  ;;

  let change_role (config : Config.t) s ~actor ~org ~user ~role ~at =
    let%bind actor_m = membership_for s ~user:actor ~org in
    team_write config s ~org ~actor ~at ~action:(custodian_action config) (fun team ->
      let from = Option.map (Team.find team user) ~f:(fun m -> m.role) in
      return
        (let%map.Result team', changes =
           Team.change_role config.model team ~actor:actor_m ~user ~role |> team_error
         in
         let member = Option.value_exn (Team.find team' user) in
         let events =
           match from with
           | Some from -> [ Audit.Event.Role_changed { user; from; to_ = role } ]
           | None -> []
         in
         team', changes, member, events))
  ;;

  let remove_member (config : Config.t) s ~actor ~org ~user ~at =
    let%bind actor_m = membership_for s ~user:actor ~org in
    team_write config s ~org ~actor ~at ~action:(custodian_action config) (fun team ->
      let role = Option.map (Team.find team user) ~f:(fun m -> m.role) in
      return
        (let%map.Result team', changes =
           Team.remove config.model team ~actor:actor_m ~user |> team_error
         in
         let events =
           match role with
           | Some role -> [ Audit.Event.Member_removed { user; role; left = false } ]
           | None -> []
         in
         team', changes, (), events))
  ;;

  let leave (config : Config.t) s ~user ~org ~at =
    team_write config s ~org ~actor:user ~at ~action:Action.read (fun team ->
      let role = Option.map (Team.find team user) ~f:(fun m -> m.role) in
      return
        (let%map.Result team', changes =
           Team.leave config.model team ~user |> team_error
         in
         let events =
           match role with
           | Some role -> [ Audit.Event.Member_removed { user; role; left = true } ]
           | None -> []
         in
         team', changes, (), events))
  ;;

  let invitation_error r = Result.map_error r ~f:(fun e -> Error.Invitation e)

  let invite (config : Config.t) s ~actor ~org ~id ~email ~role ?display_name ~at () =
    let action = custodian_action config in
    let*! (_ : Organisation.t) = require config s ~user:actor ~org action ~at in
    match%bind load_team config s org with
    | None -> return (Error Error.Not_found)
    | Some team ->
      let%bind invitations = S.invitations s org in
      if List.exists invitations ~f:(fun i -> Invitation_id.equal i.id id)
      then return (Error Error.Exists)
      else (
        let token = config.new_token () in
        let*? invitation =
          Invitation.create
            ~policy:config.invitation_policy
            config.model
            ~id
            ~org
            ~email
            ~role
            ?display_name
            ~invited_by:actor
            ~token
            ~members:team.members
            ~invitations
            ~at
            ()
          |> invitation_error
        in
        match%map
          S.insert_invitation
            s
            invitation
            (note
               ~at
               ~actor:(Some actor)
               [ Invitation_sent { invitation = id; email; role; resend = false } ])
        with
        | `Ok -> Ok (invitation, token)
        | `Duplicate ->
          (* Lost a race with another invitation to the same address. *)
          Error (Error.Invitation Already_invited))
  ;;

  (* Loads an invitation of [org] for a member allowed to manage it, then writes
     [change]'s result with compare-and-set, retrying on a concurrent change. *)
  let invitation_write (config : Config.t) s ~actor ~org ~id ~at change =
    let action = custodian_action config in
    let*! (_ : Organisation.t) = require config s ~user:actor ~org action ~at in
    retrying config (fun () ->
      match%bind S.invitation s id with
      | Some (i : Invitation.t) when Org_id.equal i.org org ->
        (match change i with
         | Error e -> return (`Done (Error (Error.Invitation e)))
         | Ok ((i' : Invitation.t), answer, events) ->
           if Invitation.equal i i'
           then return (`Done (Ok answer))
           else (
             match%map
               S.update_invitation
                 s
                 i'
                 ~expected_version:i.version
                 (note ~at ~actor:(Some actor) events)
             with
             | `Ok -> `Done (Ok answer)
             | `Conflict -> `Retry))
      | _ -> return (`Done (Error Error.Not_found)))
  ;;

  let resend (config : Config.t) s ~actor ~org ~id ~at =
    let token = config.new_token () in
    invitation_write config s ~actor ~org ~id ~at (fun i ->
      let%map.Result i' =
        Invitation.resend ~policy:config.invitation_policy i ~token ~at
      in
      ( i'
      , (i', token)
      , [ Audit.Event.Invitation_sent
            { invitation = id; email = i.email; role = i.role; resend = true }
        ] ))
  ;;

  let revoke config s ~actor ~org ~id ~at =
    invitation_write config s ~actor ~org ~id ~at (fun i ->
      let%map.Result i' = Invitation.revoke i ~at in
      i', i', [ Audit.Event.Invitation_revoked { invitation = id } ])
  ;;

  let preview s ~token ~at =
    match%bind S.invitation_by_token s (Token.hash token) with
    | Some i when Invitation.usable i ~now:at && Token.matches token i.token_hash ->
      let%map organisation = S.organisation s i.org in
      Option.map organisation ~f:(fun o -> o, i)
    | _ -> return None
  ;;

  (* Membership first, then the invitation: see the interface. *)
  let accept (config : Config.t) s (invitation : Invitation.t) ~proof ~user ~email ~at =
    let*? accepted =
      Invitation.accept invitation ~proof ~user ~email ~at |> invitation_error
    in
    let org = invitation.org in
    let*! member =
      retrying config (fun () ->
        match%bind load_team config s org with
        | None -> return (`Done (Error Error.Not_found))
        | Some team ->
          (match Team.find team user with
           | Some m when Email.equal m.email invitation.email ->
             (* A previous attempt added the member and stopped before marking the
                invitation accepted. *)
             return (`Done (Ok m))
           | _ ->
             let%bind others = other_memberships s user in
             (match
                Team.join
                  ~policy:config.team_policy
                  config.model
                  team
                  ~invitation:accepted
                  ~user
                  ~other_memberships:others
                  ~at
              with
              | Error e -> return (`Done (Error (Error.Team e)))
              | Ok (team', changes) ->
                (match%map
                   S.update_team
                     s
                     org
                     ~expected_version:team.version
                     changes
                     (note
                        ~at
                        ~actor:(Some user)
                        [ Member_added
                            { user
                            ; role = invitation.role
                            ; invitation = Some invitation.id
                            }
                        ])
                 with
                 | `Ok -> `Done (Ok (Option.value_exn (Team.find team' user)))
                 | `Conflict -> `Retry))))
    in
    match%map
      S.update_invitation
        s
        accepted
        ~expected_version:invitation.version
        (note
           ~at
           ~actor:(Some user)
           [ Invitation_accepted { invitation = invitation.id; user } ])
    with
    | `Ok -> Ok member
    | `Conflict ->
      (* The invitation was revoked or resent while the member was being added. The
         membership stands: it was valid when it was made, and the audit shows both. *)
      Ok member
  ;;

  let accept_link config s ~token ~user ~email ~at =
    match%bind S.invitation_by_token s (Token.hash token) with
    | None -> return (Error Error.Not_found)
    | Some invitation -> accept config s invitation ~proof:(Token token) ~user ~email ~at
  ;;

  let accept_pending config s ~user ~email ~at =
    let%bind pending = S.pending_for s email in
    match List.find pending ~f:(fun i -> Invitation.usable i ~now:at) with
    | None -> return (Ok None)
    | Some invitation ->
      let%map r = accept config s invitation ~proof:Verified_email ~user ~email ~at in
      Result.map r ~f:Option.some
  ;;

  let approval_error r = Result.map_error r ~f:(fun e -> Error.Approval e)

  let open_approval
    (config : Config.t)
    s
    ~maker
    ~org
    ~id
    ~policy
    ~subject
    ~action
    ~amounts
    ?maker_action
    ~at
    ()
    =
    let*! organisation =
      require
        config
        s
        ~user:maker
        ~org
        (Option.value maker_action ~default:Action.read)
        ~at
    in
    match%bind load_team config s org with
    | None -> return (Error Error.Not_found)
    | Some team ->
      let maker_m = Option.value_exn (Team.find team maker) in
      let*? approval =
        Approval.open_
          config.model
          policy
          ~id
          ~organisation
          ~maker:maker_m
          ~subject
          ~action
          ~amounts
          ~members:team.members
          ~at
          ()
        |> approval_error
      in
      (match%map
         S.insert_approval
           s
           approval
           (note
              ~at
              ~actor:(Some maker)
              [ Approval_opened
                  { approval = id
                  ; subject = approval.subject
                  ; required = approval.required
                  }
              ])
       with
       | `Ok -> Ok approval
       | `Duplicate -> Error Error.Exists)
  ;;

  (* Loads an approval of [org] and the user's standing, applies [step] and writes the
     result with compare-and-set, retrying on a concurrent vote. *)
  let approval_write (config : Config.t) s ~user ~org ~id ~at step =
    let action = ref None in
    let%bind result =
      retrying config (fun () ->
        let%bind approval = S.approval s id in
        let%bind organisation = S.organisation s org in
        let%bind membership = membership_for s ~user ~org in
        match approval, organisation with
        | Some (a : Approval.t), Some organisation when Org_id.equal a.org org ->
          action := Some a.action;
          (match step a ~organisation ~membership with
           | Error e -> return (`Done (Error (Error.Approval e)))
           | Ok ((a' : Approval.t), answer, events) ->
             (match%map
                S.update_approval
                  s
                  a'
                  ~expected_version:a.version
                  (note ~at ~actor:(Some user) events)
              with
              | `Ok -> `Done (Ok answer)
              | `Conflict -> `Retry))
        | _ -> return (`Done (Error Error.Not_found)))
    in
    match result, !action with
    | Error e, Some action -> denied config s ~org ~user ~at action e
    | result, _ -> return result
  ;;

  let approve (config : Config.t) s ~user ~org ~id ?note ~at () =
    approval_write config s ~user ~org ~id ~at (fun a ~organisation ~membership ->
      let%map.Result a', progress =
        Approval.approve a config.model ~organisation ~membership ?note ~at ()
      in
      ( a'
      , (a', progress)
      , [ Audit.Event.Approval_approved
            { approval = id
            ; approvals = List.length a'.approvals
            ; required = a'.required
            }
        ] ))
  ;;

  let reject (config : Config.t) s ~user ~org ~id ?note ~at () =
    approval_write config s ~user ~org ~id ~at (fun a ~organisation ~membership ->
      let%map.Result a' =
        Approval.reject a config.model ~organisation ~membership ?note ~at ()
      in
      a', a', [ Audit.Event.Approval_rejected { approval = id } ])
  ;;

  let cancel (config : Config.t) s ~user ~org ~id ?note ~at () =
    approval_write config s ~user ~org ~id ~at (fun a ~organisation ~membership ->
      let%map.Result a' =
        Approval.cancel
          a
          config.model
          ~organisation
          ~membership
          ~override:(Role_model.custodian config.model)
          ?note
          ~at
          ()
      in
      a', a', [ Audit.Event.Approval_cancelled { approval = id } ])
  ;;

  let audit (config : Config.t) s ~user ~org ?permission ~after ~limit ~at () =
    let permission =
      Option.value permission ~default:(Role_model.custodian config.model)
    in
    let*! (_ : Organisation.t) =
      require config s ~user ~org (Action.requires permission) ~at
    in
    let%map entries = S.audit s org ~after ~limit in
    Ok entries
  ;;
end
