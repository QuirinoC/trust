# Sharing and connection requests

## Product model

**Find by handle → send a request → accept the connection → choose what to share.** A request is not consent to receive location. Only recipient acceptance creates an active connection, and acceptance initializes both share directions to Off. Each person then chooses whether and how to share.

Sharing owns the audience and per-person location modes. Home status is a secondary setting inside Sharing. You → Location settings owns device permission, Home setup, and diagnostics; it does not decide who can see the account.

## Current milestone

- Add someone opens one large native sheet with a focused handle field, brief instructions to get a handle from You, exact search, and one result row with generated initials and Send request.
- Incoming requests are visible in Sharing with Accept and Decline. Sent requests show Pending and Cancel. Connected People retain the compact per-person sharing controls.
- Request lists and lookup show only handles and request metadata. Before acceptance, they do not expose display names, photos, phone numbers, presence, location, or sharing state.
- Phone numbers remain private account verification data. Handle discovery and connection request creation require completed onboarding; a client-side or TestFlight verification skip does not establish phone ownership.
- Home / Away / Hidden stays behind the secondary Home status control. Adding or accepting someone never starts location sharing.
- Legacy invite URLs and the existing code API remain compatible. Only when an old invite URL is opened does the app show a separate direct Accept / Later card; that flow does not change the handle-based Add someone sheet.

## Request lifecycle

Requests are addressed to one verified Trust account by its exact normalized handle. A request expires after seven days. Only the recipient can accept or decline, and only the sender can cancel. A duplicate or reciprocal submission returns the same pending request; reciprocal intent never accepts automatically. Acceptance locks both accounts in stable ID order, rechecks capacity, creates or reactivates membership, writes Off in both directions, and marks the request accepted in one transaction. Replaying acceptance never resets a chosen share mode or restores a connection removed later. Declined requests apply a seven-day cooldown to a repeat request in the same direction. Pending request limits and daily send quotas are enforced while participant account rows are locked. Terminal request metadata is retained for 30 days.

The API does not send SMS or push notifications for a connection request. The request record is authoritative; any future push is only a best-effort prompt to refresh it.

## Release and privacy

Phone discovery, contact-book upload, automatic Trust-sent SMS, QR codes, and deferred-install attribution are out of scope. Profile photos remain visible only to active connected people and are not part of a pre-connection preview. Verified phone numbers are collected for account verification, remain private, and are not used to discover people.

## Known adjacent issue

`AppModel.clearHomePlace()` currently clears only device storage. Confirm and fix server-side Home/Away deletion before public release so a cleared Home location cannot remain visible to a connected person.
