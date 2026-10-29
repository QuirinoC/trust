# Trust Staging: two-iPhone acceptance

**Execution status: not run.** Build 49 is available to the staging internal TestFlight group, so physical acceptance can begin. StoreKit product metadata may exist before the app can fetch products or complete a Sandbox purchase; verify those behaviors and staging APNs delivery on-device below.

Use two adult testers with distinct Apple Accounts and real iPhones. Select two of the three approved testers; these are the only two reserved phone numbers available concurrently for the automatic, no-SMS flow. Do not swap the assigned numbers between accounts during the run. Assign them as follows:

- **A:** `+1 202 555 0101`, handle `trustqatesta`
- **B:** `+1 202 555 0102`, handle `trustqatestb`

If either handle is already taken, choose another unique handle and record it. Use A’s invited Apple Account for both TestFlight and Apple sign-in on A; use B’s different invited Apple Account for both on B. Complete the real age check on each phone. Do not enable global phone-verification skips or use demo or age bypasses; only the two reserved numbers use the approved automatic staging flow.

Record each phone’s model, iOS version, app build, and location and notification permissions. Confirm both apps say **Trust Staging**, show the STAGING badge, and use the same build. [TestFlight purchases automatically use Apple’s sandbox](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/) and are not charged. No extra dedicated Sandbox Apple Account is needed for these baseline purchase checks. If products do not load, record that step as blocked; do not substitute a local purchase fixture.

For every numbered step, record **Pass**, **Fail**, **Blocked**, or **Not run**. Record observed behavior, not an inferred result. Push delivery is not guaranteed.

## Run the checks

1. **Install and distinguish the app.** Install the processed Trust Staging TestFlight build on both phones while keeping the normal Trust app installed. **Expected:** the staging app is labeled Trust Staging, shows the STAGING badge, and coexists with the production app without replacing it.

2. **Complete real sign-in and age checks.** On A and B, sign in with the assigned distinct Apple Accounts and complete the normal age-assurance flow. **Expected:** account setup remains gated if Apple sign-in or age verification is unavailable or declined; no bypass is used.

3. **Finish each profile and phone setup.** Set A to `trustqatesta` and B to `trustqatestb`, leave discovery off, then enter each assigned reserved number and wait for the staging flow. **Expected:** each handle is accepted if available; only these two reserved numbers auto-verify after the normal Apple, age, and handle steps; the phone screen says “No SMS is sent”; no SMS-code entry screen appears. Both accounts enter Trust with sharing Off. Record any blocked age or handle result.

4. **Check phone discovery while B is opted out.** On A, search for B using B's complete phone number. **Expected:** no eligible phone match or unconnected profile-picture preview appears while B's discovery choice is off.

5. **Check discovery consent changes.** On B, explicitly turn on “Help people find me.” Search B's full number again from A, then turn B's discovery off and repeat. **Expected:** with consent on, the eligible handle and opted-in picture may appear; after consent is off, future phone matches and unconnected picture previews are unavailable. An existing connection remains governed by its connection permissions.

6. **Cancel a sent request.** From A, send B a connection request, then cancel it from A's sent requests. **Expected:** the request becomes pending and then disappears after cancellation; no connection is created.

7. **Exercise decline, resend, and acceptance.** A sends a new request; B declines it. A sends again; B accepts. **Expected:** decline creates no connection; acceptance creates one, and both directions remain Off until independently chosen.

8. **Verify sharing directions are independent.** A chooses Sealed for B. B keeps Off for A. **Expected:** A's confirmed direction becomes Sealed while B's remains Off; changing one person's direction does not change the other.

9. **Complete a Sealed Look and receipt.** Keep A's Sealed direction active. If prompted, grant A location access While Using the App. On B, select A and confirm a Look. **Expected:** B sees a one-time snapshot with its timestamp; A sees the corresponding receipt in Trust Activity. The snapshot is the latest available location, not guaranteed-current GPS.

10. **Confirm a snapshot does not become live.** Move A to a different place without changing its sharing mode or performing another Look. Check the existing point from B. **Expected:** the prior snapshot remains until a new authorized Look; movement alone does not turn Sealed into live sharing.

11. **Pause sharing for three days.** On A, open B's sharing actions and choose Pause for three days. Check the row and attempt a Look from B. **Expected:** the pause end date/time is shown, no new Look succeeds during the pause, and the prior confirmed mode is not presented as active.

12. **Resume the prior mode.** On A, resume sharing with B. **Expected:** A's previous Sealed mode returns for B only; B's direction to A is unchanged. Confirm B can make a new Look and A receives its receipt.

13. **Turn A's direction Off with confirmation.** On A, choose Off for B and confirm the named-person prompt. **Expected:** A's sharing direction becomes Off, the connection remains, and B cannot make a new Look using A's direction.

14. **Check offline mode updates.** Put A in Airplane Mode, request a different sharing mode for B, then reconnect. **Expected:** the last server-confirmed mode remains selected while the request is pending or fails. After reconnecting, retry if offered or make a new request; the new mode appears only after confirmation.

15. **Check the free-account Always gate.** On free account A, choose Always for B. **Expected:** the Plus purchase screen appears and Always does not become active before an entitlement is verified.

16. **Make A's real Sandbox purchase.** In TestFlight, use A's Apple Sandbox purchase account to fetch and purchase the offered staging subscription. Record the product and period shown by StoreKit and the transaction outcome. After the server verifies A's entitlement, set A's direction to B to Always, then check from B while B is still free. **Expected:** A's entitlement and Always mode take effect only after verification; B sees the existing free-viewer Plus treatment. Do not count sandbox metadata or a local StoreKit test as a purchase.

17. **Purchase for B and check live freshness.** On B, fetch and purchase a staging subscription through its distinct Apple Sandbox account. Recheck A's Always share from B. **Expected:** after B's entitlement is verified, B can view the latest available point with its age, or a clear unavailable state if A has no point. Record product fetch, purchase, and entitlement separately.

18. **Exercise real background location.** With A's Always share and the required Always location permission enabled, lock or background A, move it a meaningful distance, and check from B after the device has had time to report. **Expected:** any updated point and age reflect actual observed background delivery. Record the timestamp and permission state; a foreground update alone does not pass this check.

19. **Request A's alerts explicitly and check a displayed push.** In A's You tab, tap Enable alerts. Set A's direction to B to Sealed; from B, perform a Look at A. **Expected:** A's notification permission status refreshes, and, if a real push is displayed, tapping it opens the matching receipt. Record the app state and actual display separately; APNs acceptance or an Activity entry alone is not proof of display.

20. **Exercise B's denied and allowed notification states.** On B, deny the system notification prompt when asked. In You, verify the denied status and use Open iOS Settings to allow alerts. Return to Trust, set B's direction to A to Sealed, and have A perform a Look at B. **Expected:** B's status refreshes after returning from Settings; if a real push is displayed, it opens the matching receipt. Record actual display and tap behavior. No delivery is guaranteed.

21. **Set Home and check the location controls.** On each phone, open You → My location, review permission status, and use “Use current location as Home” where appropriate. **Expected:** the UI shows Home status and the available permission action. The radius is fixed at 120 m in the app; there is no radius-edit control to look for. Coordinates remain on-device. Enable the per-person Home/Away choice only for the direction being tested; it is separate from location sharing.

22. **Test Home/Away and suppression with real movement.** With Always location permission, move a phone across the Home boundary while the per-person Home/Away option is enabled. Repeat with sharing Off, Pause, and Hidden. **Expected:** record actual Home/Away state changes and alerts; Off, Pause, and Hidden suppress what the other person can see as implemented. Hidden is not shown to the other person. Do not infer background geofence behavior from a foreground-only test, and do not treat push delivery as guaranteed.

23. **Verify avatar edits and privacy.** On both accounts, open the avatar editor, stage a change, and Cancel; then stage a preset or photo and Save. Relaunch the app. **Expected:** Cancel discards the staged change; Save persists it; missing or removed pictures fall back to initials. Neither editing nor saving a picture enables discovery or changes sharing.

24. **Check compact and accessibility layouts.** On the smaller phone, verify the normal-size connected-person row keeps Name, Off, Sealed, Always, and the secondary menu legible and reachable. Then test the largest accessibility text size, dark appearance, German, and Portuguese. **Expected:** controls remain reachable, text is not clipped, and the large-text layout reflows without hiding actions. Capture privacy-safe screenshots of any failure.

25. **Reinstall B and restore the same account.** Delete and reinstall only B's Trust Staging app, then sign in with B's same Apple Account. **Expected:** the server account and verified phone remain; no additional phone-verification SMS is requested. Record whether iOS asks for location or notification permissions again; permission prompts may depend on OS state.

26. **Remove access and clean up staging accounts.** Remove the connection and confirm; reconnect once to verify both directions begin Off, then remove it again. After recording the run, use the app's Delete account action for both staging test accounts and verify staging-only cleanup through the approved staging process. **Expected:** the connection and its grants are revoked, deleted staging accounts are removed, and no production account or resource is changed.

## Privacy-safe run record

Keep evidence minimal. Do not record Apple IDs, passwords, access tokens, verification codes, precise personal locations, customer data, or unredacted device logs.

- Run date and source revision:
- Staging build number and TestFlight processing status:
- Tester A device model / iOS version / permission states:
- Tester B device model / iOS version / permission states:
- Step number and outcome (Pass / Fail / Blocked / Not run):
- Observed result and privacy-safe evidence reference:
- Retest result or remaining blocker:

This procedure does not test carrier SMS; the two reserved staging numbers deliberately bypass SMS. It does not establish guaranteed notification delivery or production release readiness. TestFlight availability does not establish physical acceptance; record the actual outcomes of the checks below. Existing simulator evidence is documented in [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md).
