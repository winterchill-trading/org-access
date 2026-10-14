(** Free-text fields checked at the edge: names and notes. *)

open! Core

(** Collapses runs of whitespace to one space and trims the ends. *)
val collapse_whitespace : string -> string

(** [check ~what ~max s] collapses whitespace and fails when the result is empty, longer
    than [max] bytes, or has a control character. [what] names the field in the error. *)
val check : what:string -> max:int -> string -> string Or_error.t

(** Like {!check} but an empty or blank input is [None]. *)
val check_optional : what:string -> max:int -> string -> string option Or_error.t
