(** Shared values for the tests: a fixed clock start, an organisation and members of the
    default role model. *)

open! Core
open Org_access

val t0 : Time_ns.t

(** [t0] plus a number of minutes. *)
val at : int -> Time_ns.t

val org_id : Org_id.t
val other_org_id : Org_id.t
val organisation : ?verified:bool -> ?status:Organisation.Status.t -> unit -> Organisation.t
val user : string -> User_id.t
val email : string -> Email.t

(** A member of {!org_id} with this user name (also the e-mail local part) and role. *)
val member : ?org:Org_id.t -> string -> Role.t -> Member.t
