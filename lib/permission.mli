(** The name of something a member may do, such as [payments.approve] or [members.manage].

    Permissions are dotted names: one or more segments of [a-z 0-9 _] joined by dots, each
    segment starting with a letter, 64 characters at most. The library gives no meaning to
    a name beyond equality; the service decides which permission each of its operations
    asks for. *)

include Validated_name.S
