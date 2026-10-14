(** The name of a role, such as [admin] or [approver].

    A role means nothing on its own: a {!Role_model} lists the roles an organisation can
    hand out, in order of privilege, and the permissions each one carries. A name is 1 to
    32 characters from [a-z 0-9 _], starting with a letter. *)

include Validated_name.S
