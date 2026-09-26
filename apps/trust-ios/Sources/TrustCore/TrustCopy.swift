import Foundation

/// Product copy. Voice (design SoT `design-mocks/duo-gpt6`): short nouns and verbs,
/// consequence before action, no apology copy, no lifestyle poetry.
/// English is the development language. Keep non-English values in Scripts/overlays
/// and regenerate the bundled .lproj resources with Scripts/emit_localizations.py.
public enum TrustCopy {
    /// Product name. Do not translate. Use “Trust”; avoid the former name because it collides with Life360.
    public static let appName = "Trust"
    /// Wordmark. Rendered as "Trust" + accent dot. Do not translate.
    public static let mastheadName = "Trust"

    static func value(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: TrustAppLanguage.resourceBundle,
            value: defaultValue,
            comment: "")
    }

    private static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(format: value(key, defaultValue: defaultValue), locale: TrustAppLanguage.currentLocale, arguments: arguments)
    }

    // MARK: Shell

    /// Home tab — people list + map. Not “Circle” (Life360 owns that word).
    public static var people: String { value("people", defaultValue: "People") }
    /// Legacy key alias used by older call sites / localization tables.
    public static var circle: String { people }
    public static var sharing: String { value("sharing", defaultValue: "Sharing") }
    public static var log: String { value("log", defaultValue: "Activity") }
    public static var you: String { value("you", defaultValue: "You") }
    public static var map: String { value("map", defaultValue: "Map") }
    public static var viewLog: String { value("view_log", defaultValue: "View log") }

    /// Top-center map pill. Empty → account name; otherwise “You + N”.
    public static func peoplePill(you: String, count: Int) -> String {
        if count <= 0 {
            return you.isEmpty ? people : you
        }
        return format("you_plus", defaultValue: "You + %d", count)
    }

    public static var cancel: String { value("cancel", defaultValue: "Cancel") }
    public static var close: String { value("close", defaultValue: "Close") }
    public static var done: String { value("done", defaultValue: "Done") }
    public static var back: String { value("back", defaultValue: "Back") }
    public static var later: String { value("later", defaultValue: "Later") }
    public static var continueAction: String { value("continue", defaultValue: "Continue") }
    public static var look: String { value("look", defaultValue: "Look") }
    public static var view: String { value("view", defaultValue: "View") }
    public static var stop: String { value("stop", defaultValue: "Stop") }
    public static var join: String { value("join", defaultValue: "Join") }
    public static var them: String { value("them", defaultValue: "them") }
    public static var someone: String { value("someone", defaultValue: "Someone") }
    public static var now: String { value("now", defaultValue: "now") }
    public static var retry: String { value("retry", defaultValue: "Retry") }
    public static var preferences: String { value("preferences", defaultValue: "Preferences") }
    public static var account: String { value("account", defaultValue: "Account") }
    public static var sendAnInvite: String { value("send_an_invite", defaultValue: "Send an invite") }
    public static var haveInviteCode: String { value("have_invite_code", defaultValue: "Have an invite code?") }
    public static var yourStatus: String { value("your_status", defaultValue: "Your status") }
    public static var homeStatus: String { value("home_status", defaultValue: "Home status") }
    public static var addProfilePicture: String { value("add_profile_picture", defaultValue: "Add a profile picture") }
    public static var changeProfilePicture: String { value("change_profile_picture", defaultValue: "Change profile picture") }
    public static var yourProfile: String { value("your_profile", defaultValue: "Your profile") }
    public static var addPicture: String { value("add_picture", defaultValue: "Add a picture") }
    public static var profilePicture: String { value("profile_picture", defaultValue: "Profile picture") }
    public static var cameraUnavailable: String { value("camera_unavailable", defaultValue: "Camera unavailable") }
    public static var cameraSettingsGuide: String { value("camera_settings_guide", defaultValue: "Allow camera access in Settings to take a picture.") }
    public static var homeSetOnThisPhone: String { value("home_set_on_this_phone", defaultValue: "Home set on this phone") }
    public static func locationAccessStatus(_ status: String) -> String { format("location_access_status", defaultValue: "Location access: %@", status) }
    public static var locationPermissionHeading: String { value("location_permission_heading", defaultValue: "Location permission") }
    public static var manage: String { value("manage", defaultValue: "Manage") }
    public static var systemAppearance: String { value("system_appearance", defaultValue: "System") }
    public static var lightAppearance: String { value("light_appearance", defaultValue: "Light") }
    public static var darkAppearance: String { value("dark_appearance", defaultValue: "Dark") }
    public static func peopleCountAccessibility(_ count: Int) -> String { format("people_count_accessibility", defaultValue: "%d people", count) }
    public static var peopleListSizeAccessibility: String { value("people_list_size_accessibility", defaultValue: "People list size") }
    public static var peopleEmptyTitle: String { value("people_empty_title", defaultValue: "No one is sharing with you yet") }
    public static var peopleEmptyBody: String { value("people_empty_body", defaultValue: "You can invite someone or choose what to share with them.") }
    public static var goToSharing: String { value("go_to_sharing", defaultValue: "Go to Sharing") }
    public static var loadingRecentPlaces: String { value("loading_recent_places", defaultValue: "Loading recent places") }
    public static var optionalAvatarIntro: String { value("optional_avatar_intro", defaultValue: "Optional · choose an animal or a photo") }
    public static var inviteCreateBody: String { value("invite_create_body", defaultValue: "Create a link for them to accept. They join before either of you shares.") }
    public static var createInviteLink: String { value("create_invite_link", defaultValue: "Create invite link") }
    public static var lookNotificationNote: String { value("look_notification_note", defaultValue: "Trust records this Look. A notification may be delivered.") }
    public static func plusFeatureSummary(_ log: String) -> String { format("plus_feature_summary", defaultValue: "Live pins · %@", log) }
    public static func subscriptionError(_ message: String) -> String { format("subscription_error", defaultValue: "Subscription error. %@", message) }
    public static var avatarVisibleToConnections: String { value("avatar_visible_to_connections", defaultValue: "Visible to people connected with you.") }
    public static var demoAvatarNotice: String { value("demo_avatar_notice", defaultValue: "Photos and camera need an account. Animal icons work in this demo and stay on this device.") }
    public static var save: String { value("save", defaultValue: "Save") }
    public static var chooseFromPhotos: String { value("choose_from_photos", defaultValue: "Choose from Photos") }
    public static var takePhoto: String { value("take_photo", defaultValue: "Take Photo") }
    public static var removePicture: String { value("remove_picture", defaultValue: "Remove picture") }
    public static var photoOptions: String { value("photo_options", defaultValue: "Photo options") }
    public static func avatarIconAccessibility(_ name: String) -> String { format("avatar_icon_accessibility", defaultValue: "%@ icon", name) }
    public static var sharingPresenceExplanation: String { value("sharing_presence_explanation", defaultValue: "Home or Away appears only for people you chose Sealed or Always for. Off, Pause, and Hidden keep your status out of their view.") }
    public static func moreSharingActions(_ name: String) -> String { format("more_sharing_actions", defaultValue: "More sharing actions for %@", name) }
    public static func sharingDirections(inbound: String, outbound: String) -> String {
        format("sharing_directions", defaultValue: "They share with you: %@ · You share with them: %@", inbound, outbound)
    }
    public static var appearance: String { value("appearance", defaultValue: "Appearance") }
    public static var language: String { value("language", defaultValue: "Language") }
    public static var followIPhoneLanguage: String { value("follow_iphone_language", defaultValue: "Follow iPhone") }
    public static var englishLanguage: String { value("language_english", defaultValue: "English") }
    public static var simplifiedChineseLanguage: String { value("language_zh_hans", defaultValue: "简体中文") }
    public static var japaneseLanguage: String { value("language_ja", defaultValue: "日本語") }
    public static var germanLanguage: String { value("language_de", defaultValue: "Deutsch") }
    public static var frenchLanguage: String { value("language_fr", defaultValue: "Français") }
    public static var brazilianPortugueseLanguage: String { value("language_pt_br", defaultValue: "Português (Brasil)") }
    public static var editProfilePicture: String { value("edit_profile_picture", defaultValue: "Edit profile picture") }
    public static var changePictureTip: String { value("change_picture_tip", defaultValue: "Tap to change your picture") }
    public static var myLocation: String { value("my_location", defaultValue: "My location") }
    public static var homePlacePrivacy: String { value("home_place_privacy", defaultValue: "Your Home place stays on this phone. In Sharing, choose each person's location mode and your Home, Away, or Hidden status.") }
    public static var sleepyAnimals: String { value("sleepy_animals", defaultValue: "Sleepy animals") }
    public static func avatarTitle(for id: String) -> String {
        switch id {
        case "fox": value("avatar_fox", defaultValue: "Fox")
        case "rabbit": value("avatar_rabbit", defaultValue: "Rabbit")
        case "bear": value("avatar_bear", defaultValue: "Bear")
        case "cat": value("avatar_cat", defaultValue: "Cat")
        case "dog": value("avatar_dog", defaultValue: "Dog")
        case "otter": value("avatar_otter", defaultValue: "Otter")
        case "owl": value("avatar_owl", defaultValue: "Owl")
        case "turtle": value("avatar_turtle", defaultValue: "Turtle")
        case "siamese": value("avatar_siamese", defaultValue: "Siamese cat")
        case "ragdoll": value("avatar_ragdoll", defaultValue: "Ragdoll cat")
        case "british-shorthair": value("avatar_british_shorthair", defaultValue: "British Shorthair")
        default: value("avatar", defaultValue: "Animal")
        }
    }
    public static var cameraPermission: String { value("camera_permission", defaultValue: "Trust uses the camera only when you choose Take Photo to set your profile picture.") }
    public static var peopleListSizeHint: String { value("people_list_size_hint", defaultValue: "Swipe up or down to change the list size. Double-tap to expand or collapse.") }

    // MARK: Login (A1)

    public static var loginPromise: String {
        value("login_promise", defaultValue: "Sharing stays off until you choose a mode for each person.")
    }
    public static var signInTitle: String { value("sign_in_title", defaultValue: "Sign in to Trust") }
    public static var signInWithApple: String { value("sign_in_with_apple", defaultValue: "Sign in with Apple") }
    public static var signingIn: String { value("signing_in", defaultValue: "Signing in…") }
    public static var signingInShort: String { value("signing_in_short", defaultValue: "Signing in") }
    public static var seeTheApp: String { value("see_the_app", defaultValue: "See the app") }
    public static var trustUsesSignInWithApple: String {
        value("trust_uses_sign_in_with_apple", defaultValue: "Trust uses Sign in with Apple.")
    }
    public static var termsOfService: String { value("terms_of_service", defaultValue: "Terms of Service") }
    public static var terms: String { value("terms", defaultValue: "Terms") }
    public static var privacy: String { value("privacy", defaultValue: "Privacy") }
    public static var support: String { value("support", defaultValue: "Support") }
    public static var demoBannerTitle: String { value("demo_banner_title", defaultValue: "Demo") }
    public static var demoBannerBody: String {
        value("demo_banner_body", defaultValue: "Nine fictional people. Offline — no Sign in with Apple, nothing is sent.")
    }
    public static var demoSimulated: String {
        value("demo_simulated", defaultValue: "Demo — notification is simulated.")
    }

    // MARK: Handle (A2)

    public static var yourHandle: String { value("your_handle", defaultValue: "Your handle") }
    public static var handleIntro: String {
        value("handle_intro", defaultValue: "Pick a handle. This is your name on Trust.")
    }
    public static var handle: String { value("handle", defaultValue: "Handle") }
    public static var handlePlaceholder: String { value("handle_placeholder", defaultValue: "jordan") }
    public static var handleRules: String {
        value("handle_rules", defaultValue: "3–20 characters. Letters, numbers, underscores. Starts with a letter.")
    }
    public static var handleAvailable: String { value("handle_available", defaultValue: "Available") }
    public static var handleTaken: String { value("handle_taken", defaultValue: "Taken") }
    public static var handleReserved: String { value("handle_reserved", defaultValue: "Reserved") }
    public static var handleInvalid: String { value("handle_invalid", defaultValue: "That handle isn’t valid.") }
    public static var enterHandle: String { value("enter_handle", defaultValue: "Enter a handle to continue.") }

    // MARK: Modes & presence (shared vocabulary)

    public static var off: String { value("off", defaultValue: "Off") }
    public static var notSharing: String { value("not_sharing", defaultValue: "Not sharing") }
    public static var untilTheyLook: String { value("until_they_look", defaultValue: "Until they look") }
    public static var always: String { value("always", defaultValue: "Always") }
    public static var sealed: String { value("sealed", defaultValue: "Sealed") }
    public static var available: String { value("available", defaultValue: "Available") }
    public static var presenceHome: String { value("presence_home", defaultValue: "Home") }
    public static var presenceAway: String { value("presence_away", defaultValue: "Away") }
    public static var presenceHidden: String { value("presence_hidden", defaultValue: "Hidden") }
    public static var presenceUnknown: String { value("presence_unknown", defaultValue: "No signal") }
    public static var presenceHiddenBadge: String { value("presence_hidden_badge", defaultValue: "Presence hidden") }

    public static var timed15m: String { value("timed_15m", defaultValue: "15 minutes") }
    public static var timed1h: String { value("timed_1h", defaultValue: "1 hour") }
    public static var timed4h: String { value("timed_4h", defaultValue: "4 hours") }
    public static var timed8h: String { value("timed_8h", defaultValue: "8 hours") }

    // MARK: People home (T1)

    public static var sharedWithYou: String { value("shared_with_you", defaultValue: "Shared with you") }
    public static var notSharingWithYou: String { value("not_sharing_with_you", defaultValue: "Not sharing with you") }
    public static var rowSealedPresenceHidden: String {
        value("row_sealed_presence_hidden", defaultValue: "Sealed · presence hidden")
    }
    public static var rowAvailablePresenceHidden: String {
        value("row_available_presence_hidden", defaultValue: "Available · presence hidden")
    }
    public static func rowSealed(presence: String) -> String {
        format("row_sealed", defaultValue: "%@ · Sealed", presence)
    }
    public static func rowAvailable(presence: String) -> String {
        format("row_available", defaultValue: "%@ · Available", presence)
    }
    public static var rowLookedTapView: String { value("row_looked_tap_view", defaultValue: "Looked · tap View") }
    /// Inbound Off stays on the list. Revoke is not a member flag — the pair leaves, and the log says who removed whom.
    public static func choseOff(name: String) -> String {
        format("chose_off", defaultValue: "%@ chose off", name)
    }
    public static var circleEmptyTitle: String { value("circle_empty_title", defaultValue: "Your people will appear here") }
    public static var circleEmptyBody: String {
        value("circle_empty_body", defaultValue: "Invite someone or choose what to share. Location stays off until you choose a mode for that person.")
    }
    public static var mapSealedHint: String {
        value(
            "map_sealed_hint",
            defaultValue: "Live pins show when someone shares Always."
        )
    }
    public static var recenterMap: String { value("recenter_map", defaultValue: "Recenter map") }
    public static var inviteSomeone: String { value("invite_someone", defaultValue: "Invite someone") }
    public static func lookHint(name: String) -> String {
        format("look_hint", defaultValue: "Look at %@. This records one snapshot and requests a notification.", name)
    }
    public static func viewHint(name: String) -> String {
        format("view_hint", defaultValue: "View %@. The view is logged.", name)
    }

    // MARK: Look confirm (notify first)

    public static var confirm: String { value("confirm", defaultValue: "Confirm") }
    public static func lookAtTitle(name: String) -> String { format("look_at_title", defaultValue: "Look at %@?", name) }
    public static func lookAt(name: String) -> String { format("look_at", defaultValue: "Look at %@", name) }
    public static func willBeNotified(name: String) -> String {
        format("will_be_notified", defaultValue: "A notification will be requested for %@.", name)
    }
    public static var thenOneSnapshot: String {
        value("then_one_snapshot", defaultValue: "One snapshot of their current place.")
    }
    public static func previewLine(viewer: String) -> String {
        format("preview_line", defaultValue: "%@ looked at your location.", viewer)
    }
    public static var receiptNoteSealed: String {
        value("receipt_note_sealed", defaultValue: "Their share stays Sealed.")
    }
    public static func lookNotify(name: String) -> String { format("look_notify", defaultValue: "Look · notify %@", name) }

    // MARK: View (D1)

    public static var oneTimeLook: String { value("one_time_look", defaultValue: "One-time Look") }
    public static var liveShare: String { value("live_share", defaultValue: "Always") }
    public static func receiptNotified(name: String) -> String {
        format("receipt_notified", defaultValue: "Look recorded · notification requested for %@.", name)
    }
    public static func receiptViewLogged(name: String) -> String {
        format("receipt_view_logged", defaultValue: "%@ · view logged", name)
    }
    public static var stripSnapshot: String {
        value("strip_snapshot", defaultValue: "One snapshot. It does not update.")
    }
    public static var stripTrail: String {
        value("strip_trail", defaultValue: "Open Look trail from retained points. Not a driving log.")
    }
    public static var stripLive: String {
        value("strip_live", defaultValue: "Updates while they share Always.")
    }
    public static var circleMap: String { value("circle_map", defaultValue: "People map") }
    public static func snapshotAt(_ time: String) -> String { format("snapshot_at", defaultValue: "Snapshot · %@", time) }
    public static func updatedAt(_ time: String) -> String { format("updated_at", defaultValue: "Updated %@", time) }
    public static func distanceFromYou(_ distance: String) -> String {
        format("distance_from_you", defaultValue: "%@ from you", distance)
    }
    public static var location: String { value("location", defaultValue: "Location") }
    public static var noPlacesYet: String { value("no_places_yet", defaultValue: "No places yet") }
    public static var sealedTitle: String { value("sealed_title", defaultValue: "Sealed") }
    public static func sealedBody(name: String) -> String {
        format("sealed_body", defaultValue: "A Look records one snapshot and requests a notification for %@.", name)
    }
    public static var noLocationYet: String { value("no_location_yet", defaultValue: "Getting location…") }
    public static var noLocationBody: String {
        value("no_location_body", defaultValue: "This usually takes a moment.")
    }

    // MARK: Map (D2)

    public static var noLocationsYet: String { value("no_locations_yet", defaultValue: "No locations yet") }
    public static var mapEmptyBody: String {
        value(
            "map_empty_body",
            defaultValue: "Live pins show when someone shares Always."
        )
    }
    public static var backToCircle: String { value("back_to_circle", defaultValue: "Back to People") }
    public static func onMap(count: Int, sealed: Int) -> String {
        format("on_map", defaultValue: "%d on map · %d not shown", count, sealed)
    }
    public static var mapLegend: String { value("map_legend", defaultValue: "Always") }
    public static var oneLook: String { value("one_look", defaultValue: "One look") }
    public static var snapshot: String { value("snapshot", defaultValue: "Snapshot") }
    public static func sealedNotOnMap(_ count: Int) -> String {
        if count == 1 {
            return value("sealed_not_on_map_one", defaultValue: "1 person not on this map.")
        }
        return format("sealed_not_on_map", defaultValue: "%d people not on this map.", count)
    }
    public static func viewLocation(name: String) -> String {
        format("view_location", defaultValue: "View %@’s location", name)
    }
    public static var mapAccessibility: String {
        value("map_accessibility", defaultValue: "Map. Live pins when someone shares Always.")
    }
    public static var onTheMap: String { value("on_the_map", defaultValue: "On the map") }
    public static func pinAccessibility(name: String, live: Bool) -> String {
        format("pin_accessibility", defaultValue: "%@. %@.", name, live ? available : snapshot)
    }
    public static func showOnMap(name: String) -> String {
        format("show_on_map", defaultValue: "Show %@ on the map", name)
    }

    public static var homeIsSetLabel: String {
        value("home_is_set_label", defaultValue: "Home is set on this phone.")
    }
    public static var homeNeedsAlways: String {
        value("home_needs_always", defaultValue: "Allow Always location so Home and Away update when Trust is closed.")
    }
    public static var homeNotSetLabel: String {
        value("home_not_set_label", defaultValue: "No Home place yet.")
    }
    public static var homePlace: String { value("home_place", defaultValue: "Home place") }
    public static var homePlaceNote: String {
        value(
            "home_place_note",
            defaultValue: "Set from where you are now. Coordinates stay on this phone. With Always location, Trust marks Home or Away for your circle."
        )
    }
    public static func seeTrail(hours: Int) -> String {
        if hours >= 24 {
            let days = hours / 24
            return format("see_trail_days", defaultValue: "See last %d days", days)
        }
        return format("see_trail_hours", defaultValue: "See last %d hours", hours)
    }
    public static var setHomeHere: String { value("set_home_here", defaultValue: "Use current location as Home") }
    public static var clearHome: String { value("clear_home", defaultValue: "Clear Home") }
    public static var homeNeedsLocation: String {
        value("home_needs_location", defaultValue: "Allow location, then set Home from where you are.")
    }
    public static var homeSetToast: String {
        value("home_set_toast", defaultValue: "Home set on this phone. Presence can follow the boundary.")
    }
    public static var homeClearedToast: String {
        value("home_cleared_toast", defaultValue: "Home cleared. Presence stays manual.")
    }

    // MARK: Sharing (T2)

    public static var sharingSub: String { value("sharing_sub", defaultValue: "What each person can see of you.") }
    public static var sharingIntro: String {
        value("sharing_intro", defaultValue: "Sealed gives one snapshot after a Look. Always shares location while it is on.")
    }
    public static func youShareWith(count: Int) -> String {
        format("you_share_with", defaultValue: "You share with · %d", count)
    }
    public static var rowSealedUntilLook: String { value("row_sealed_until_look", defaultValue: "Sealed until Look") }
    public static var rowLocationAvailable: String { value("row_location_available", defaultValue: "Always") }
    public static var descOff: String { value("desc_off", defaultValue: "Not sharing. They cannot see your location.") }
    public static var descUntil: String { value("desc_until", defaultValue: "Sealed. A Look shows one snapshot and requests a notification.") }
    public static var descAlways: String {
        value("desc_always", defaultValue: "Always. They can View.")
    }
    public static func descTimed(until: String) -> String {
        format("desc_timed", defaultValue: "Paused until %@. Then the previous mode returns.", until)
    }
    public static var plus: String { value("plus", defaultValue: "Plus") }
    public static var plusLockHint: String { value("plus_lock_hint", defaultValue: "Always is Plus.") }
    public static var pause: String { value("pause", defaultValue: "Pause") }
    public static var pauseSharing: String { value("pause_sharing", defaultValue: "Pause") }
    public static func pauseTitle(name: String) -> String {
        format("pause_title", defaultValue: "Pause sharing with %@", name)
    }
    public static func pauseReturns(mode: String) -> String {
        format("pause_returns", defaultValue: "Their access pauses, then returns to %@ after the time you choose.", mode)
    }
    public static func pauseUntil(time: String, mode: String) -> String {
        format("pause_until", defaultValue: "Paused until %@. Back to %@.", time, mode)
    }
    public static var stopSharing: String { value("stop_sharing", defaultValue: "Stop sharing") }
    public static var removePerson: String { value("remove_person", defaultValue: "Remove") }
    public static func removePersonConfirm(name: String) -> String {
        format(
            "remove_person_confirm",
            defaultValue: "Remove %@? They leave the list. Stop keeps them as not sharing.",
            name
        )
    }
    public static var stopSharingWarning: String {
        value("stop_sharing_warning", defaultValue: "They cannot see your location.")
    }
    public static var lookNotifiedShort: String {
        value("look_notified_short", defaultValue: "One snapshot · notification requested")
    }
    public static var addSomeone: String { value("add_someone", defaultValue: "Add someone") }
    public static var add: String { value("add", defaultValue: "Add") }
    public static var addPersonExplanation: String { value("add_person_explanation", defaultValue: "Find someone by their exact handle. Connecting never turns sharing on.") }
    public static var theirHandle: String { value("their_handle", defaultValue: "Their handle") }
    public static var handleLookupHelper: String { value("handle_lookup_helper", defaultValue: "Ask them for the handle in their You tab.") }
    public static var search: String { value("search", defaultValue: "Search") }
    public static var connectionLookupCaption: String { value("connection_lookup_caption", defaultValue: "Public handle") }
    public static var connected: String { value("connected", defaultValue: "Connected") }
    public static var requestSent: String { value("request_sent", defaultValue: "Request sent") }
    public static var sendRequest: String { value("send_request", defaultValue: "Send request") }
    public static var acceptRequest: String { value("accept_request", defaultValue: "Accept request") }
    public static var connectionRequests: String { value("connection_requests", defaultValue: "Requests") }
    public static var loadingRequests: String { value("loading_requests", defaultValue: "Loading requests") }
    public static var incomingRequests: String { value("incoming_requests", defaultValue: "Received") }
    public static var sentRequests: String { value("sent_requests", defaultValue: "Sent") }
    public static var declineRequest: String { value("decline_request", defaultValue: "Decline") }
    public static var cancelRequest: String { value("cancel_request", defaultValue: "Cancel request") }
    public static var noConnectionRequests: String { value("no_connection_requests", defaultValue: "No requests right now.") }
    public static var pending: String { value("connection_request_pending", defaultValue: "Pending") }
    public static var verifyNumber: String { value("verify_number", defaultValue: "Verify number") }
    public static var connectionRequestsNeedAccount: String { value("connection_requests_need_account", defaultValue: "Sign in to add people by handle.") }
    public static var connectedSharingOff: String { value("connected_sharing_off", defaultValue: "Connected · sharing stays off.") }
    public static var reviewRequests: String { value("review_requests", defaultValue: "Review requests") }
    public static func sharingRequestsAccessibility(_ count: Int) -> String {
        format("sharing_requests_accessibility", defaultValue: "%@, %d incoming requests", sharing, count)
    }
    public static var copyHandle: String { value("copy_handle", defaultValue: "Copy handle") }
    public static var handleCopied: String { value("handle_copied", defaultValue: "Handle copied") }
    public static func handleInitialsAccessibility(_ handle: String) -> String { format("handle_initials_accessibility", defaultValue: "Initials for @%@", handle) }
    public static var howLong: String { value("how_long", defaultValue: "How long") }
    public static var sharingEmptyTitle: String { value("sharing_empty_title", defaultValue: "No one to share with yet.") }
    public static var sharingEmptyBody: String {
        value("sharing_empty_body", defaultValue: "Add someone. Sharing stays off until you choose a mode.")
    }
    public static func modeUpdated(name: String, mode: String) -> String {
        format("mode_updated", defaultValue: "%@: %@.", name, mode)
    }
    public static func sharingStopped(name: String) -> String {
        format("sharing_stopped", defaultValue: "Location sharing with %@ stopped.", name)
    }
    public static var timerEnded: String {
        value("timer_ended", defaultValue: "Pause ended. The previous mode is back.")
    }
    public static func stopConfirm(name: String) -> String {
        format("stop_confirm", defaultValue: "Stop sharing with %@? They cannot see your location until you choose a mode again.", name)
    }

    // MARK: Always location explainer

    public static var alwaysTitle: String { value("always_title", defaultValue: "Allow background location.") }
    public static var alwaysBody: String {
        value(
            "always_body",
            defaultValue: "A Look still works when Trust is closed. Trust requests a notification when they Look."
        )
    }
    public static var allowAlways: String { value("allow_always", defaultValue: "Allow background location") }
    public static var openSettings: String { value("open_settings", defaultValue: "Open Settings") }
    public static var alwaysNeededForSharing: String {
        value("always_needed_for_sharing", defaultValue: "Sharing needs Always so a Look still works when Trust is closed.")
    }
    public static var keptWhileUsing: String {
        value(
            "kept_while_using",
            defaultValue: "Location updates only while Trust is open. Set background location in Settings."
        )
    }
    public static var locationDeniedBody: String {
        value(
            "location_denied_body",
            defaultValue: "Location is off. You can still Look. Your location is not shared until you allow it."
        )
    }
    public static var locationReducedAccuracy: String {
        value("location_reduced_accuracy", defaultValue: "Approximate location is on. Sharing needs precise location.")
    }
    public static var allowPreciseLocation: String { value("allow_precise_location", defaultValue: "Allow precise location") }
    public static var openIOSSettings: String { value("open_ios_settings", defaultValue: "Open iOS Settings") }
    public static var whileUsing: String { value("while_using", defaultValue: "While using") }
    public static var denied: String { value("denied", defaultValue: "Denied") }
    public static var notAsked: String { value("not_asked", defaultValue: "Not asked") }
    public static var unknown: String { value("unknown", defaultValue: "Unknown") }
    public static var precise: String { value("precise", defaultValue: "Precise") }
    public static var approximate: String { value("approximate", defaultValue: "Approximate") }

    // MARK: Invite (T3)

    public static var inviteSub: String { value("invite_sub", defaultValue: "Add someone.") }
    public static var inviteLine: String { value("invite_line", defaultValue: "Join me on Trust.") }
    public static var inviteDescription: String {
        value("invite_description", defaultValue: "They join. Sharing stays off until each of you chooses a mode.")
    }
    public static var yourCode: String { value("your_code", defaultValue: "Your code") }
    public static var createInvite: String { value("create_invite", defaultValue: "Create invite") }
    public static var shareInviteLink: String { value("share_invite_link", defaultValue: "Share invite link") }
    public static var enterACode: String { value("enter_a_code", defaultValue: "Enter a code") }
    public static var codePlaceholder: String { value("code_placeholder", defaultValue: "ABC123") }
    public static var inviteFootnote: String {
        value("invite_footnote", defaultValue: "Joining does not start sharing.")
    }
    public static var inviteReady: String { value("invite_ready", defaultValue: "Invite ready") }
    public static var inviteReadyBody: String {
        value("invite_ready_body", defaultValue: "Send the link. Nothing is shared until each of you chooses a mode.")
    }
    public static var joined: String { value("joined", defaultValue: "Joined. Sharing is off both ways.") }
    public static var copyInviteLink: String { value("copy_invite_link", defaultValue: "Copy invite link") }
    public static var copied: String { value("copied", defaultValue: "Copied") }
    public static var inviteCodeFallback: String { value("invite_code_fallback", defaultValue: "Use a code instead") }
    public static var invitationToConnect: String { value("invitation_to_connect", defaultValue: "Invitation to connect") }
    public static var invitationAcceptBody: String { value("invitation_accept_body", defaultValue: "Accept to connect. Sharing stays off until you choose a mode.") }
    public static var acceptInvitation: String { value("accept_invitation", defaultValue: "Accept invitation") }
    public static var inviteByPhone: String { value("invite_by_phone", defaultValue: "Invite by phone") }
    public static var phoneInviteMessageBody: String { value("phone_invite_message_body", defaultValue: "Trust prepares a text with your link. It is sent only if you tap Send in Messages.") }
    public static var prepareInviteText: String { value("prepare_invite_text", defaultValue: "Prepare text") }
    public static var messagesUnavailable: String { value("messages_unavailable", defaultValue: "Messages isn’t available here. The invite link was copied.") }
    public static func inviteMessage(code: String) -> String {
        "\(inviteLine)\nhttps://jointrust.app/i/\(code)"
    }
    public static var yourPhone: String { value("your_phone", defaultValue: "Your phone") }
    public static var phoneIntro: String {
        value("phone_intro", defaultValue: "Phone verification is required.")
    }
    public static var phoneConsentDetails: String {
        value("phone_consent_details", defaultValue: "By tapping Send code, you agree to receive Trust verification texts at this number. Standard message and data rates may apply. Up to 8/day. Reply STOP to opt out, HELP for help.")
    }
    public static var verifyPhoneTitle: String { value("verify_phone_title", defaultValue: "Verify your number") }
    public static var phoneCodeIntro: String { value("phone_code_intro", defaultValue: "Enter the code we sent to:") }
    public static var editPhone: String { value("edit_phone", defaultValue: "Edit") }
    public static var verificationCode: String { value("verification_code", defaultValue: "Code") }
    public static var verifyCode: String { value("verify_code", defaultValue: "Verify") }
    public static var phoneNumber: String { value("phone_number", defaultValue: "Phone number") }
    public static var phonePlaceholder: String { value("phone_placeholder", defaultValue: "(415) 555-0100") }
    public static var sendCode: String { value("send_code", defaultValue: "Send code") }
    public static var codeSent: String { value("code_sent", defaultValue: "Code sent. Enter it below to verify your number.") }
    public static var resendCode: String { value("resend_code", defaultValue: "Resend code") }
    public static var phoneCode: String { value("phone_code", defaultValue: "Code") }
    public static var codePlaceholderShort: String { value("code_placeholder_short", defaultValue: "123456") }
    public static var verify: String { value("verify", defaultValue: "Verify") }
    public static var enterPhone: String { value("enter_phone", defaultValue: "Enter a phone number.") }
    public static var enterPhoneCode: String { value("enter_phone_code", defaultValue: "Enter the code.") }
    public static func developmentPhoneCode(_ code: String) -> String {
        format("development_phone_code", defaultValue: "Code %@.", code)
    }
    public static var inviteTextSent: String { value("invite_text_sent", defaultValue: "Invite text sent.") }
    public static func inviteNotTexted(_ code: String) -> String {
        format("invite_not_texted", defaultValue: "No text was sent. Code %@.", code)
    }
    public static var inviteNotTextedPlain: String {
        value("invite_not_texted_plain", defaultValue: "No text was sent.")
    }
    public static var personAdded: String {
        value("person_added", defaultValue: "Added. Sharing is off both ways.")
    }
    public static var alreadyAdded: String { value("already_added", defaultValue: "Already added.") }
    public static var phoneAddNeedsAccount: String {
        value("phone_add_needs_account", defaultValue: "This preview can’t text a phone.")
    }
    public static func seatsUsed(count: Int, limit: Int) -> String {
        format("seats_used", defaultValue: "%d of %d people", count, limit)
    }

    // MARK: You (T4)

    public static var freePlan: String { value("free_plan", defaultValue: "Free plan") }
    public static var plusPlan: String { value("plus_plan", defaultValue: "Plus") }
    public static var status: String { value("status", defaultValue: "Status") }
    public static var sealedByDefault: String { value("sealed_by_default", defaultValue: "Sealed by default") }
    public static func statusSharing(count: Int) -> String {
        if count == 1 {
            return value("status_sharing_one", defaultValue: "Sharing with 1 person.")
        }
        return format("status_sharing", defaultValue: "Sharing with %d people.", count)
    }
    public static var statusNone: String {
        value("status_none", defaultValue: "Not sharing. Nobody can Look.")
    }
    public static var manageSharing: String { value("manage_sharing", defaultValue: "Manage sharing") }
    public static var presence: String { value("presence", defaultValue: "Presence") }
    public static var presenceNote: String {
        value("presence_note", defaultValue: "Home / Away / Hidden — separate from whether location is sealed or available.")
    }
    public static var presenceHomeCopy: String {
        value("presence_home_copy", defaultValue: "Home or Away. Not a location.")
    }
    public static var presenceAwayCopy: String {
        value("presence_away_copy", defaultValue: "Shown as Away when you’re not at Home.")
    }
    public static var presenceHiddenCopy: String {
        value("presence_hidden_copy", defaultValue: "They do not see Home or Away.")
    }
    public static var presenceUnknownCopy: String {
        value("presence_unknown_copy", defaultValue: "Home, Away, or Hidden. Not a location.")
    }
    public static var presenceHiddenToast: String {
        value("presence_hidden_toast", defaultValue: "Status hidden.")
    }
    /// VoiceOver hint on the presence control.
    public static var presenceHint: String {
        value("presence_hint", defaultValue: "Sets Home, Away, or Hidden. Not a location.")
    }
    /// VoiceOver label on a Sharing row's mode control.
    public static func sharingModeLabel(name: String) -> String {
        format("sharing_mode_label", defaultValue: "What %@ can see of you", name)
    }
    public static var selected: String { value("selected", defaultValue: "Selected") }
    public static func presenceSetToast(label: String) -> String {
        format("presence_set_toast", defaultValue: "Status set to %@.", label)
    }
    public static var trustPlus: String { value("trust_plus", defaultValue: "Trust Plus") }
    public static var plusHeadline: String { value("plus_headline", defaultValue: "Always, 20 people, live pins.") }
    public static var plusFreeLine: String {
        value("plus_free_line", defaultValue: "Up to 5 people. Sealed and Look stay on.")
    }
    public static var plusPlusLine: String {
        value("plus_plus_line", defaultValue: "up to 20 · Always · full log")
    }
    public static func plusNote(monthly: String, annual: String) -> String {
        format(
            "plus_note",
            defaultValue: "Plus adds Always, 20 people, and live pins. %@/mo or %@/yr.",
            monthly,
            annual
        )
    }
    public static var seePlus: String { value("see_plus", defaultValue: "See Plus") }
    public static var youHavePlus: String { value("you_have_plus", defaultValue: "You have Plus.") }
    public static var settings: String { value("settings", defaultValue: "Settings") }
    public static var lookNotifications: String { value("look_notifications", defaultValue: "Look notifications") }
    public static var lookNotificationsBody: String {
        value("look_notifications_body", defaultValue: "Sealed Looks request a notification. Views are logged.")
    }
    public static var allowNotifications: String { value("allow_notifications", defaultValue: "Allow notifications") }
    public static var notificationsOff: String {
        value("notifications_off", defaultValue: "Notifications are off in Settings. Looks still show in the log.")
    }
    public static var stopAll: String { value("stop_all", defaultValue: "Stop all location sharing") }
    public static var stopAllConfirm: String {
        value(
            "stop_all_confirm",
            defaultValue: "Stop sharing with everyone? They cannot see your location until you choose a mode again."
        )
    }
    public static var stopAllToast: String {
        value("stop_all_toast", defaultValue: "All outbound location sharing stopped.")
    }
    public static var signOut: String { value("sign_out", defaultValue: "Sign out") }
    public static var deleteAccount: String { value("delete_account", defaultValue: "Delete account") }
    public static var deleteAccountConfirm: String {
        value(
            "delete_account_confirm",
            defaultValue: "Delete your Trust account? Location, views, and who you’re connected to are removed. This cannot be undone."
        )
    }
    public static var weDoNotSellLocation: String {
        value("we_do_not_sell_location", defaultValue: "No ads. We do not sell location.")
    }
    public static var signoff: String { loginPromise }
    public static var signedOutSummary: String { value("signed_out_summary", defaultValue: "Not signed in.") }

    // MARK: View log (D3)

    public static var viewLogIntro: String {
        value("view_log_intro", defaultValue: "Looks, views, and removals.")
    }
    public static func viewLogRetention(freeDays: Int) -> String {
        format("view_log_retention", defaultValue: "Free keeps %d days. Plus keeps a year and can export.", freeDays)
    }
    public static var noViewsYet: String { value("no_views_yet", defaultValue: "No events yet.") }
    public static var allViews: String { value("all_views", defaultValue: "All views") }
    public static func olderEntriesHeld(_ count: Int) -> String {
        format("older_entries_held", defaultValue: "%d older events are outside this log.", count)
    }
    public static var exportLog: String { value("export_log", defaultValue: "Export log") }
    public static func logYouLooked(name: String) -> String { format("log_you_looked", defaultValue: "You looked at %@.", name) }
    public static func logTheyLooked(name: String) -> String { format("log_they_looked", defaultValue: "%@ looked at you.", name) }
    public static func logYouViewed(name: String) -> String { format("log_you_viewed", defaultValue: "You viewed %@.", name) }
    public static func logTheyViewed(name: String) -> String { format("log_they_viewed", defaultValue: "%@ viewed you.", name) }
    public static func logYouRemoved(name: String) -> String { format("log_you_removed", defaultValue: "You removed %@.", name) }
    public static func logTheyRemoved(name: String) -> String { format("log_they_removed", defaultValue: "%@ removed you.", name) }
    public static var kindLook: String { value("kind_look", defaultValue: "Look recorded") }
    public static var kindView: String { value("kind_view", defaultValue: "view logged") }
    public static var kindRemoved: String { value("kind_removed", defaultValue: "removed") }
    public static func lookLogExportRow(timestamp: String, line: String, kind: String) -> String {
        "\(timestamp)\t\(line)\t\(kind)"
    }

    // MARK: Receipts & toasts

    public static func receiptTitle(viewer: String) -> String {
        format("receipt_title", defaultValue: "%@ looked at your location.", viewer)
    }
    public static var receiptBody: String {
        value("receipt_body", defaultValue: "One snapshot of your current place.")
    }
    public static func lookSaved(name: String) -> String {
        format("look_saved", defaultValue: "Look recorded · notification requested for %@.", name)
    }
    public static func viewLogged(name: String) -> String {
        format("view_logged", defaultValue: "%@ · view logged.", name)
    }
    public static var notification: String { value("notification", defaultValue: "Notification") }
    public static var offline: String { value("offline", defaultValue: "Offline") }
    public static func offlineBanner(since: String) -> String {
        format("offline_banner", defaultValue: "Offline · people from %@", since)
    }
    public static var offlineAction: String {
        value("offline_action", defaultValue: "You’re offline. Try again when you’re connected.")
    }

    // MARK: Plus (paywall — `SubscriptionStoreView` shows title, period, price, trial; this is the rest)

    public static func monthlyPrice(_ price: String) -> String { format("monthly_price", defaultValue: "Monthly — %@", price) }
    public static func annualPrice(_ price: String) -> String { format("annual_price", defaultValue: "Annual — %@", price) }
    public static func priceFallback(monthly: String, annual: String) -> String {
        format("price_fallback", defaultValue: "%@/mo or %@/yr. 7-day trial.", monthly, annual)
    }
    public static var trialNote: String { value("trial_note", defaultValue: "7-day trial on both plans.") }
    public static var plusFeatureSeats: String { value("plus_feature_seats", defaultValue: "Up to 20 people.") }
    public static var plusFeatureModes: String {
        value("plus_feature_modes", defaultValue: "Always.")
    }
    public static var plusFeatureMap: String { value("plus_feature_map", defaultValue: "Live pins when someone shares Always.") }
    public static var plusFeatureLog: String { value("plus_feature_log", defaultValue: "Log for a year, with export.") }
    public static var plusStaysFree: String {
        value(
            "plus_stays_free",
            defaultValue: "Look, Pause, Home / Away / Hidden, Stop, Invite, and Delete stay free."
        )
    }
    public static var plusCoveredBody: String {
        value("plus_covered_body", defaultValue: "Always, 20 people, live pins, and 30 days of history.")
    }
    public static func plusActivePlan(name: String, price: String) -> String {
        format("plus_active_plan", defaultValue: "%@ · %@", name, price)
    }
    public static var subscriptionUnavailable: String {
        value("subscription_unavailable", defaultValue: "Plus isn’t available from the App Store right now. Try again later.")
    }
    public static var restorePurchases: String { value("restore_purchases", defaultValue: "Restore purchases") }
    public static var manageSubscription: String { value("manage_subscription", defaultValue: "Manage subscription") }
    public static var unlockPlusForReview: String { value("unlock_plus_for_review", defaultValue: "Unlock Plus for review") }
    public static var plusLegal: String {
        value(
            "plus_legal",
            defaultValue: "Plus is an auto-renewing subscription. Payment is charged to your Apple Account at confirmation. It renews unless you cancel at least 24 hours before the period ends. Family Sharing is off. We do not sell location."
        )
    }
    public static var subscriptionLinked: String {
        value(
            "subscription_linked",
            defaultValue: "This Apple subscription is linked to another Trust account. Contact hello@collapsetechnologies.com."
        )
    }
    public static var plusOnThisAccount: String { value("plus_on_this_account", defaultValue: "Plus is on this account") }
    public static var storeKitVerificationFailed: String {
        value("storekit_verification_failed", defaultValue: "StoreKit verification failed.")
    }

    // MARK: Location purpose strings (Info.plist mirrors)

    public static var locationWhenInUsePurpose: String {
        value(
            "location_when_in_use",
            defaultValue: "Trust uses your location while the app is open so you can see yourself on the map and look at people who share with you. Trust does not sell your location."
        )
    }
    public static var locationAlwaysPurpose: String {
        value(
            "location_always",
            defaultValue: "Trust uses your location in the background so a Look still works when the app is closed. A confirmed Look is recorded and requests a notification. Trust does not sell your location."
        )
    }
    public static var locationPrecisePurpose: String {
        value(
            "location_precise",
            defaultValue: "Trust needs precise location so a Look shows the current place. Approximate location is not enough."
        )
    }

    // MARK: Auth errors

    public static var appleSignInFailed: String { value("apple_sign_in_failed", defaultValue: "Apple could not complete sign-in.") }
    public static var appleSignInTimedOut: String {
        value("apple_sign_in_timed_out", defaultValue: "Apple sign-in did not finish. Try again.")
    }
    public static var invalidAppleCredential: String {
        value("invalid_apple_credential", defaultValue: "Apple did not return a usable sign-in.")
    }
    public static var presentationUnavailable: String {
        value("presentation_unavailable", defaultValue: "Sign-in needs a window to present from.")
    }
    public static var signInInProgress: String { value("sign_in_in_progress", defaultValue: "Sign-in is already in progress.") }

    // MARK: Network errors (never raw NSURLError)

    public static var signInExpired: String { value("sign_in_expired", defaultValue: "Sign in expired. Sign in again.") }
    public static var cannotReachServer: String {
        value("cannot_reach_server", defaultValue: "Trust can’t reach the server. Check your connection.")
    }
    public static func cannotReachHost(_ host: String) -> String {
        format("cannot_reach_host", defaultValue: "Trust can’t reach %@. Start the API or wait for production.", host)
    }
    public static var signInTimedOut: String { value("sign_in_timed_out", defaultValue: "Timed out. Try again.") }
    public static func signInTimedOutHost(_ host: String) -> String {
        format("sign_in_timed_out_host", defaultValue: "Timed out talking to %@.", host)
    }
    public static var serverUnavailable: String {
        value("server_unavailable", defaultValue: "Trust’s server is temporarily unavailable. Try again shortly.")
    }
    public static func serverUnavailableHost(status: Int, host: String) -> String {
        format("server_unavailable_host", defaultValue: "Trust’s server is unavailable (%d) at %@.", status, host)
    }
    public static var decodingError: String {
        value("decoding_error", defaultValue: "The server sent something this app could not read.")
    }
    public static var requestFailed: String { value("request_failed", defaultValue: "Request failed.") }
    public static func requestFailedStatus(_ status: Int) -> String {
        format("request_failed_status", defaultValue: "Request failed (%d).", status)
    }
    public static func cannotReachLocal(_ host: String) -> String {
        format("cannot_reach_local", defaultValue: "Trust can’t reach %@. Start the API on port 5088, or deploy production.", host)
    }

    /// Known API error codes → plain copy. Unknown codes pass the server message through.
    public static func apiError(code: String?, fallback: String?) -> String {
        switch code {
        case "confirmation_required":
            return value("api_confirmation_required", defaultValue: "Look needs a confirm first.")
        case "not_connected":
            return value("api_not_connected", defaultValue: "This person is not connected to you.")
        case "pair_inactive":
            return value("api_pair_inactive", defaultValue: "They removed you.")
        case "invalid_code":
            return value("api_invalid_code", defaultValue: "That invite code doesn’t match or has expired.")
        case "own_invite":
            return value("api_own_invite", defaultValue: "That’s your own invite.")
        case "seat_limit":
            return value("api_seat_limit", defaultValue: "Free is 5 people. Plus is 20.")
        case "pro_required":
            return value("api_pro_required", defaultValue: "Always is Plus.")
        case "no_location":
            return value("api_no_location", defaultValue: "Getting location…")
        case "share_off":
            return value("api_share_off", defaultValue: "They chose off.")
        case "look_requires_sealed":
            return value("api_look_requires_sealed", defaultValue: "Their location is already available. Use View.")
        case "view_requires_available":
            return value("api_view_requires_available", defaultValue: "Sealed. Look instead to record one snapshot and request a notification.")
        case "unauthorized":
            return value("api_unauthorized", defaultValue: "Sign in is required.")
        case "invalid_handle":
            return value("api_invalid_handle", defaultValue: "That handle isn’t valid.")
        case "handle_not_found", "person_not_found":
            return value("api_handle_not_found", defaultValue: "No Trust account was found for that handle.")
        case "verification_required":
            return value("api_verification_required", defaultValue: "Verify your phone number before connecting.")
        case "request_declined_recently":
            return value("api_request_declined_recently", defaultValue: "That person recently declined a request. Try again later.")
        case "request_limit":
            return value("api_request_limit", defaultValue: "You’ve sent too many requests. Try again later.")
        case "request_expired", "request_not_found":
            return value("api_request_expired", defaultValue: "That request has expired or is no longer available.")
        case "reserved_handle":
            return value("api_reserved_handle", defaultValue: "That handle is reserved.")
        case "handle_in_use":
            return value("api_handle_in_use", defaultValue: "That handle is taken.")
        case "invalid_name":
            return value("api_invalid_name", defaultValue: "Enter a display name of at least two characters.")
        case "invalid_phone":
            return value("api_invalid_phone", defaultValue: "Enter a valid phone number, including country code.")
        case "otp_not_configured":
            return value("api_otp_not_configured", defaultValue: "Phone texts are not configured on this server.")
        case "otp_cooldown":
            return value("api_otp_cooldown", defaultValue: "Wait a moment before requesting another code.")
        case "otp_expired":
            return value("api_otp_expired", defaultValue: "That code expired. Request a new one.")
        case "otp_invalid":
            return value("api_otp_invalid", defaultValue: "That code does not match.")
        case "otp_exhausted":
            return value("api_otp_exhausted", defaultValue: "Too many attempts. Request a new code.")
        case "otp_send_failed":
            return value("api_otp_send_failed", defaultValue: "Trust could not send a text. Try again.")
        case "phone_in_use":
            return value("api_phone_in_use", defaultValue: "That phone is already on another Trust account.")
        case "phone_unavailable":
            return value("api_phone_unavailable", defaultValue: "This number can't be used for this account.")
        case "own_phone":
            return value("api_own_phone", defaultValue: "That number is already on this account.")
        case "invalid_state":
            return value("api_invalid_state", defaultValue: "Presence must be Home, Away, or Hidden.")
        case "invalid_token":
            return value("api_invalid_token", defaultValue: "Sign-in could not be completed. Try again.")
        case "apple_unavailable":
            return value("api_apple_unavailable", defaultValue: "Apple sign-in timed out. Try again.")
        case "invalid_apple_token":
            return value("api_invalid_apple_token", defaultValue: "Apple could not verify this sign-in. Try again.")
        case "storekit_unavailable":
            return value("api_storekit_unavailable", defaultValue: "StoreKit is not available on this server.")
        case "storekit_unverified":
            return value("api_storekit_unverified", defaultValue: "Purchase or restore Plus, then try again.")
        case "invalid_storekit":
            return value("api_invalid_storekit", defaultValue: "The App Store transaction could not be verified.")
        case "storekit_account_mismatch":
            return subscriptionLinked
        case "storekit_not_linked":
            return value("api_storekit_not_linked", defaultValue: "This Apple transaction could not be linked to the signed-in Trust account.")
        case "invalid_device":
            return value("api_invalid_device", defaultValue: "A push token and installation id are required.")
        case "invalid_bundle":
            return value("api_invalid_bundle", defaultValue: "That push topic is not this app.")
        case "invalid_product":
            return value("api_invalid_product", defaultValue: "That product is not available.")
        case "stripe_price_missing", "stripe_unconfigured", "stripe_error":
            return value("api_stripe_unavailable", defaultValue: "Web checkout is not available. Use Plus on iPhone.")
        default:
            let trimmed = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? requestFailed : trimmed
        }
    }
}

/// A user can follow iOS's preferred app language or choose any shipped localization.
/// The explicit preference is stored independently of country/region so travel never
/// silently changes the language the person chose.
public enum TrustAppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case german = "de"
    case french = "fr"
    case brazilianPortuguese = "pt-BR"

    public static let storageKey = "trust.appLanguage"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: TrustCopy.followIPhoneLanguage
        case .english: TrustCopy.englishLanguage
        case .simplifiedChinese: TrustCopy.simplifiedChineseLanguage
        case .japanese: TrustCopy.japaneseLanguage
        case .german: TrustCopy.germanLanguage
        case .french: TrustCopy.frenchLanguage
        case .brazilianPortuguese: TrustCopy.brazilianPortugueseLanguage
        }
    }

    public static var selected: TrustAppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return .system }
        return TrustAppLanguage(rawValue: raw) ?? .system
    }

    public var resolvedLocale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    public static var currentLocale: Locale {
        selected.resolvedLocale
    }

    fileprivate static var resourceBundle: Bundle {
        guard selected != .system,
              let path = Bundle.main.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
