open! Core

module Event = struct
  type t =
    | Organisation_created of { name : string }
    | Organisation_status_changed of { status : Organisation.Status.t }
    | Organisation_verified of { verified : bool }
    | Member_added of
        { user : User_id.Stable.V1.t
        ; role : Role.Stable.V1.t
        ; invitation : Invitation_id.Stable.V1.t option
        }
    | Role_changed of
        { user : User_id.Stable.V1.t
        ; from : Role.Stable.V1.t
        ; to_ : Role.Stable.V1.t
        }
    | Member_removed of
        { user : User_id.Stable.V1.t
        ; role : Role.Stable.V1.t
        ; left : bool
        }
    | Invitation_sent of
        { invitation : Invitation_id.Stable.V1.t
        ; email : Email.Stable.V1.t
        ; role : Role.Stable.V1.t
        ; resend : bool
        }
    | Invitation_revoked of { invitation : Invitation_id.Stable.V1.t }
    | Invitation_accepted of
        { invitation : Invitation_id.Stable.V1.t
        ; user : User_id.Stable.V1.t
        }
    | Approval_policy_changed of { policy : Approval_policy.Stable.V1.t }
    | Approval_opened of
        { approval : Approval_id.Stable.V1.t
        ; subject : string
        ; required : int
        }
    | Approval_approved of
        { approval : Approval_id.Stable.V1.t
        ; approvals : int
        ; required : int
        }
    | Approval_rejected of { approval : Approval_id.Stable.V1.t }
    | Approval_cancelled of { approval : Approval_id.Stable.V1.t }
    | Access_denied of
        { action : Action.Stable.V1.t
        ; code : string
        }
  [@@deriving bin_io, sexp, compare, equal]

  let kind = function
    | Organisation_created _ -> "organisation_created"
    | Organisation_status_changed _ -> "organisation_status_changed"
    | Organisation_verified _ -> "organisation_verified"
    | Member_added _ -> "member_added"
    | Role_changed _ -> "role_changed"
    | Member_removed _ -> "member_removed"
    | Invitation_sent _ -> "invitation_sent"
    | Invitation_revoked _ -> "invitation_revoked"
    | Invitation_accepted _ -> "invitation_accepted"
    | Approval_policy_changed _ -> "approval_policy_changed"
    | Approval_opened _ -> "approval_opened"
    | Approval_approved _ -> "approval_approved"
    | Approval_rejected _ -> "approval_rejected"
    | Approval_cancelled _ -> "approval_cancelled"
    | Access_denied _ -> "access_denied"
  ;;
end

let sha256_hex s =
  Cryptokit.transform_string
    (Cryptokit.Hexa.encode ())
    (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s)
;;

module Digest = struct
  type t = string [@@deriving bin_io, sexp, compare, equal, hash]

  let to_hex t = t
  let genesis org = sha256_hex ("org-access audit genesis\000" ^ Org_id.to_string org)
end

module Entry = struct
  type t =
    { org : Org_id.Stable.V1.t
    ; seq : int
    ; at : Time_utc.t
    ; actor : User_id.Stable.V1.t option
    ; event : Event.t
    ; prev : Digest.t
    ; digest : Digest.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

(* What the digest covers: every field but the digest itself, in its stable binary form,
   so the digest does not depend on sexp layout or the machine's time zone. *)
module Signed = struct
  type t =
    { org : Org_id.Stable.V1.t
    ; seq : int
    ; at : Time_utc.t
    ; actor : User_id.Stable.V1.t option
    ; event : Event.t
    ; prev : Digest.t
    }
  [@@deriving bin_io]
end

let digest_of ~org ~seq ~at ~actor ~event ~prev =
  sha256_hex (Binable.to_string (module Signed) { org; seq; at; actor; event; prev })
;;

let next ~(last : Entry.t option) ~org ~at ~actor event =
  match last with
  | Some l when not (Org_id.equal l.org org) ->
    Or_error.error_s
      [%message "audit entry of another organisation" ~expected:(org : Org_id.t) ~got:(l.org : Org_id.t)]
  | _ ->
    let seq, prev =
      match last with
      | None -> 1, Digest.genesis org
      | Some l -> l.seq + 1, l.digest
    in
    Ok { Entry.org; seq; at; actor; event; prev; digest = digest_of ~org ~seq ~at ~actor ~event ~prev }
;;

module Broken = struct
  type t =
    | Wrong_organisation of { seq : int }
    | Gap of
        { expected : int
        ; found : int
        }
    | Prev_mismatch of { seq : int }
    | Digest_mismatch of { seq : int }
  [@@deriving sexp, compare, equal]
end

let verify ?after org entries =
  let start_seq, start_prev =
    match after with
    | None -> 1, Digest.genesis org
    | Some (e : Entry.t) -> e.seq + 1, e.digest
  in
  let rec go ~seq ~prev = function
    | [] -> Ok ()
    | (e : Entry.t) :: rest ->
      if not (Org_id.equal e.org org)
      then Error (Broken.Wrong_organisation { seq = e.seq })
      else if e.seq <> seq
      then Error (Broken.Gap { expected = seq; found = e.seq })
      else if not (Digest.equal e.prev prev)
      then Error (Broken.Prev_mismatch { seq })
      else if
        not
          (Digest.equal
             e.digest
             (digest_of ~org ~seq ~at:e.at ~actor:e.actor ~event:e.event ~prev:e.prev))
      then Error (Broken.Digest_mismatch { seq })
      else go ~seq:(seq + 1) ~prev:e.digest rest
  in
  go ~seq:start_seq ~prev:start_prev entries
;;

module Stable = struct
  module Event = struct
    module V1 = Event
  end

  module Entry = struct
    module V1 = Entry
  end
end
