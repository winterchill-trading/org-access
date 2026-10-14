The built-in role model:

  $ org-access roles
                      admin     approver  operator  viewer
  accounting.manage   yes       -         yes       -
  addresses.manage    yes       -         yes       -
  cards.manage        yes       -         yes       -
  cost_centres.manage yes       -         yes       -
  export              yes       yes       yes       yes
  members.manage      yes       -         -         -
  payees.manage       yes       -         yes       -
  payments.approve    yes       yes       -         -
  payments.create     yes       -         yes       -
  policy.manage       yes       -         -         -
  rules.manage        yes       -         yes       -
  schedules.manage    yes       -         yes       -
  verification.manage yes       -         -         -
  custodian: members.manage

Decisions:

  $ org-access explain -role approver -permission payments.approve -needs-verification
  (Denied Verification_required)
  code: verification_required
  $ org-access explain -role approver -permission payments.approve -needs-verification -verified
  (Allowed (role approver))
  $ org-access explain -role viewer -permission members.manage
  (Denied
   (Permission_missing (role viewer) (permission members.manage)
    (required (admin))))
  code: role_required

An approval policy with two tiers in euros:

  $ cat > policy.sexp <<'SEXP'
  > ((base 1)
  >  (tiers (((above "10000.00 EUR") (required 2)) ((above "50000.00 EUR") (required 3))))
  >  (unlisted Base))
  > SEXP
  $ org-access required -policy policy.sexp "9000.00 EUR" "6000.00 EUR" "100.00 GBP"
  9000.00 EUR: 1
  6000.00 EUR: 1
  100.00 GBP: 1
  together: 2
