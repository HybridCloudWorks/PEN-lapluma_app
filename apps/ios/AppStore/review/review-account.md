# App Review access contract

Alpha 0.2 has no public App Review account because deployment is outside this sprint.
The local stub sign-in is not a valid public review mechanism.

Before public submission, Release Engineering must provide through the protected
submission environment:

- a non-expiring reviewer username and password, or an approved fully featured
  review mode;
- the always-on review backend URL and health-check evidence;
- step-up, OTP, and passkey bypass instructions that do not weaken production users;
- test data that is visibly synthetic and can be reset;
- a support contact able to respond throughout review.

Credentials and personal contact details belong in App Store Connect or a secret
store, never in this file. Account expiration, forced OTP to an employee, unavailable
backend data, or a stub-only journey blocks submission.
