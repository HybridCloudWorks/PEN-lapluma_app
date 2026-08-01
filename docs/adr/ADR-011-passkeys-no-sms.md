# ADR-011 — Passkeys primary; SMS never offered as a factor

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Principal Security Architect, CISO
**Consulted:** CX Lead, Accessibility Specialist, CPO

## Context

The target population is among the most heavily targeted by impersonation fraud in the United
States. Fake "USCIS verification" messages are a standard attack. A credential that can be typed
into a lookalike site is a credential that will be.

SMS one-time codes are the conventional consumer fallback. For this population they are
particularly poor: SIM-swap risk is real, phone numbers change frequently, numbers are often shared
within a household, and collecting a phone number creates a data holding we would rather not have.

The counter-argument, raised by the CPO and CX Lead, is that passkeys are unfamiliar and that
requiring them will cost conversion.

## Decision

**Passkeys (platform authenticators) are the primary authentication method** for applicants, with a
one-sentence plain-language explanation at enrolment.

**Fallbacks:** email OTP, and TOTP for devices without passkey support. Accounts on the fallback
path are flagged `AUTH_DOWNGRADED` so the population can be measured and shrunk.

**SMS is not offered as an authentication factor, and phone numbers are not collected for
authentication.**

**Recovery** requires email OTP **plus** a recovery code issued at registration, and triggers:
revocation of all sessions, invalidation of all passkeys, a 24-hour hold on package export and on
adding household members, and a security notification. Recovery of a folder owner's account never
grants access to another member's Private Annex, because that data is scoped to a different
`UserId` at the RLS layer.

## Consequences

**Positive.** Removes the phishing attack that this population is most targeted by. No password
database exists. Recovery friction is deliberate and proportionate — account takeover here means an
abuser reading a victim's file.

**Negative.** Passkeys are unfamiliar and enrolment will cost some conversion. Recovery is harder
than a password reset, and some users will be genuinely locked out. Older devices need the fallback
path.

**Neutral.** Requires investment in plain-language explanation and in support tooling for recovery.
The `AUTH_DOWNGRADED` flag exists so we can measure how much of the population is on the weaker path
and target improvement there.

## Revisit triggers

None that would introduce SMS. If passkey enrolment proves a material conversion barrier after
measurement, invest in explanation and in the OTP+TOTP path — not in SMS.
