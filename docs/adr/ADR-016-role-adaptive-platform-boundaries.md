# ADR-016: Role-adaptive platform boundaries

**Status:** Accepted for contract-ready local implementation
**Date:** 2026-08-12

## Decision

LaPluma uses shared domain and API contracts with three deliberately different surfaces:

- iPhone/iPad applicant mode retains folder, capture, missing-item, interview, review, and package access allowed to the applicant.
- iPad reviewer-lite mode exposes assigned review work only when the session contains the reviewer capability.
- macOS workforce mode is the full client directory, queue, case workbench, administration, review, approval, generation, and export surface.

Users entitled to both applicant and workforce personas explicitly switch modes. UI mode is never an authorization input. The identity service returns personas, roles, capabilities, tenant, person scopes, and session identity; each service independently enforces them.

Organization-managed cases require distinct assigned humans for Preparer, Reviewer, and Approver. Tenant administration does not imply case-content access.

## Consequences

The Form Catalog owns editions and bindings, the Case service owns canonical values, the Document service owns authorized pixels, and preview/generation are server operations. Shared client types may render these records but cannot merge their trust boundaries. Capability-matrix and distinct-actor tests are release gates.
