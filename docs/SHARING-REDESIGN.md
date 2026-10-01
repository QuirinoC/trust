# Sharing and connection requests

## Product model

**Find by handle or complete phone number → send a request → accept the connection → choose what to share.** A request is not consent to receive location. Only recipient acceptance creates an active connection, and acceptance initializes both share directions to Off. Each person then chooses whether and how to share.

Sharing owns the audience and per-person location modes. Home status is a secondary setting inside Sharing. You → Location settings owns device permission, Home setup, and diagnostics; it does not decide who can see the account.

## Implemented experience

The experience below is implemented and is the current product record, not an open redesign task. Cross-account simulator validation passed; remaining real-device and multi-device checks are listed in [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md) and [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md).

- Add someone opens one native sheet with a clear “Find your person” heading, one privacy reassurance (“Connect first. Sharing stays off until you choose.”), and a focused “Handle or phone number” field. A 350 ms debounce runs one exact handle or complete-phone search; national numbers use device region metadata, and international numbers can include `+` and their country code. There is no Search button. Keep the sheet visually light: one compact bordered field, no decorative card shadows, and a simple result row with the opted-in profile picture and `@handle`; Send request is the full-width action below it. Done dismisses the keyboard and gives submit-only feedback for malformed handles or incomplete phone numbers, while the initial screen stays uncluttered.
- If a complete phone lookup returns no eligible match, show a plain “No match found” state and a “Share invite link” action. Phone discovery is opt-in, so the copy must not claim the searched number is not registered. Only tapping Share invite link creates the legacy invite URL and opens native sharing. Dismissing the share sheet does not mean it was sent. Never send an automatic SMS or include the typed phone number in an invite.
- Incoming requests are visible in Sharing with Accept and Decline. Sent requests show Pending and Cancel. Connected People retain the compact per-person sharing controls.
- Discovery starts off for existing accounts. An explicit “Help people find me” choice allows people with the complete verified number to find the handle; the phone itself is never returned. Handle search remains available to verified, onboarded people even when discovery is off.
- Before acceptance, results never expose display names, phone numbers, presence, location, or sharing state. A small picture preview appears only when the searched person has opted in or is already connected to the caller. Turning discovery off prevents future phone matches and unconnected picture previews; an existing connection continues to authorize the usual picture view.
- Handle discovery, phone discovery, and connection request creation require completed onboarding; a client-side or TestFlight verification skip does not establish phone ownership.
- Home / Away / Hidden stays behind the secondary Home status control. Adding or accepting someone never starts location sharing.
- Legacy invite URLs and the existing code API remain compatible. Opening a link shows an explicit Accept / Later card; accepting still starts both sharing directions Off. If the app is not installed, do not invent a public store URL; after a TestFlight install and reopen, acceptance still requires the person's choice. This flow does not replace the Add someone sheet.

## Request lifecycle

Requests are addressed to one verified Trust account by its exact normalized handle. A request expires after seven days. Only the recipient can accept or decline, and only the sender can cancel. A duplicate or reciprocal submission returns the same pending request; reciprocal intent never accepts automatically. Acceptance locks both accounts in stable ID order, rechecks capacity, creates or reactivates membership, writes Off in both directions, and marks the request accepted in one transaction. Replaying acceptance never resets a chosen share mode or restores a connection removed later. Declined requests apply a seven-day cooldown to a repeat request in the same direction. Pending request limits and daily send quotas are enforced while participant account rows are locked. Terminal request metadata is retained for 30 days.

The API does not send SMS or push notifications for a connection request. The request record is authoritative; any future push is only a best-effort prompt to refresh it.

## Release and privacy

Contact-book upload, automatic Trust-sent SMS, QR codes, and deferred-install attribution are out of scope. Phone discovery is an explicit opt-in using one complete verified phone number at a time; Trust does not upload contacts or send invitations by text. Profile photos can appear as small inline previews for opted-in discovery and remain fully available to active connections. No public photo URL is returned.

## Home behavior and open multi-device product decision

Home removal is implemented locally and on the server. Clearing Home removes the server place and derived place association while preserving independent manual presence. Home coordinates remain device-only and account-scoped; they are not uploaded. The API stores only a place ID/label and coarse presence.

The remaining multi-device product decision is separate from the completed sharing redesign: when one account has two devices with different local Home regions, presence is account-wide and the most recent device event can change the status seen by every connection. Decide whether one device is the location source, presence is per device, or Home monitoring is limited to one signed-in device before treating multi-device Home/Away behavior as production-ready. See [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md).
