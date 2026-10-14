# Security Policy

extra-container helps create and manage dynamic systemd-nspawn containers
on NixOS. It leverages systemd namespaces to isolate network, file system,
uids, and processes. If you think you've found a bug or vulnerability, we
want to know! Please follow the guidance below for reporting. We will
investigate all credible reported issues.

## Please report privately

**Do not open a public issue, discussion, or pull request for a suspected
vulnerability, and do not create a public repo with a reproducible test case.**
Public disclosure before a fix is available puts every user at risk.

Report privately using **GitHub private vulnerability reporting**

- Go to the repository's **Security** tab → **Report a vulnerability**.
  This opens a private advisory only you and the maintainers can see.

You can help by making the report clear, and, ideally, including a reproducible
test case demonstrating the vulnerability. If you are able, check if the
issue reproduces on a standard NixOS container (requires nixos-rebuild switch),
to determine if the issue is specific to extra-container or may be an upstream
issue. If the report looks like it's AI generated, or is too long, verbose,
or unclear, we may not take it seriously. If we can't reproduce it, it will
take longer to investigate, and that's not in either of our interests.

Please include:

- the extra-container version or commit
- the NixOS version or commit
- OS platform and version
- a description of the issue and its impact
- reproduction steps or a proof of concept
- whether you were able to reproduce on a nixos container
- any suggested remediation
- your contact information

**Redact real secrets, keys, or tokens** from anything you attach.

## What to expect

There is **no bug bounty** and no formal SLA. That said:

- We are grateful for feedback and getting a heads-up for security bugs.
- We aim to acknowledge a credible report within **3 business days**.
- We will keep you updated as we investigate and fix.
- We practice coordinated disclosure: we will agree on a disclosure timeline
  with you and, unless you prefer otherwise, credit you in the release notes and
  advisory.
