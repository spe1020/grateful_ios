import Foundation

/// Account copy, verbatim from Prep's final M5 flows
/// (`PLANS/GRATEFUL_DAY_IOS_M5_FLOWS_AND_COPY_2026_11_21.md`). Change only
/// together with that document. "nsec" appears only on the import screen
/// (`importPrompt`) and on the export intro (`exportIntroBody1`): S6, and
/// Prep's final export copy (`PLANS/GRATEFUL_DAY_IOS_KEY_EXPORT_AND_SAVE_SYNC_PRODUCT_2026_11_22.md`).
enum AccountCopy {
    // F1
    static let connectHeading = "Keep your reflections safe"
    static let usedBefore = "I've used Grateful Day before"
    static let createKey = "Create a journal key"
    static let useNostr = "Use my Nostr account"

    // F2
    static let backupHeading = "Keep a backup of your journal key?"
    static let backupBody = "Your journal key opens your private reflections. If this iPhone is lost and there's no backup, they can't be opened again, even though they're saved to your account. We can keep a copy of your journal key in iCloud Keychain. Anyone who can sign in to your Apple account on a trusted device could restore it."
    static let backupYes = "Back up to iCloud Keychain"
    static let backupNo = "Don't back up"
    static let backupSaved = "Journal key backup saved. It reaches your other devices if iCloud Keychain is on (Settings → your name → iCloud → Passwords & Keychain)."
    static let declineConfirm = "Without a backup, losing this iPhone means your private reflections can't be opened again."
    static let goBack = "Go back"
    static let continueWithout = "Continue without backup"
    static let backUpLater = "Back up journal key"

    // F3
    static let searching = "Looking for your journal key backup…"
    static let foundOne = "We found your journal key backup."
    static let restore = "Restore"
    static func backupFrom(_ date: Date?) -> String {
        guard let date else { return "Journal key backup" }
        return "Backup from \(date.formatted(date: .long, time: .omitted))"
    }
    static let noneYet = "Your backup hasn't arrived from iCloud yet. Make sure iCloud Keychain is on in Settings, then try again. If you never made a backup, your old journal key can't be restored here."
    static let tryAgain = "Try again"
    static let back = "Back"
    static let stillLooking = "Still looking for your journal key backup."

    // F4
    static let createHeading = "Make a new journal key?"
    static let createBody = "If you've used Grateful Day before, reflections saved with your old journal key won't open with a new one."
    static let makeNewKey = "Make a new key"
    static let usedItBefore = "I've used it before"

    // F5
    static let importPrompt = "Paste your Nostr secret key (nsec). It stays on this iPhone and is never sent anywhere."
    /// Audit r3 co-review: Universal Clipboard hint.
    static let clipboardHint = "If you copied it on a Mac, it may still be on that Mac's clipboard."
    static let importInvalid = "That doesn't look like a Nostr key."
    static func importConfirm(_ npub: String) -> String { "This is the account \(npub)." }
    static let importSave = "Use this account"
    static let importSaveFailed = "Couldn't save the key."
    static let importAnotherAccount = "Your journal key isn't on this iPhone. Restore it from your backup to keep saving to your account. Your reflections on this iPhone are still here."

    // F6
    static let keyMissing = "Your journal key isn't on this iPhone. Restore it from your backup to keep saving to your account. Your reflections on this iPhone are still here."
    static let mismatch = "This iPhone has a different journal key from the one your journal uses. Nothing will be saved to your account until this is sorted out. Your reflections on this iPhone are still here."

    // F7
    static let signOut = "Sign out"
    static let signOutHeading = "Sign out on this iPhone?"
    static let signOutAlways = "Your journal key will be removed from this iPhone. Your reflections stay here, and you can keep writing."
    // Prep, #27 (owner at write time).
    static func signOutUnsynced(_ n: Int) -> String {
        n == 1
            ? "1 reflection hasn't been saved to your account yet. It'll stay on this iPhone and will be saved when you sign back in to this account. It won't be saved to any other account."
            : "\(n) reflections haven't been saved to your account yet. They'll stay on this iPhone and will be saved when you sign back in to this account. They won't be saved to any other account."
    }
    static func signOutGuestUnsaved(_ m: Int) -> String {
        m == 1
            ? "1 reflection written before you signed in hasn't been saved yet. It'll stay on this iPhone and can be added to the next account you sign in with."
            : "\(m) reflections written before you signed in haven't been saved yet. They'll stay on this iPhone and can be added to the next account you sign in with."
    }
    static let signOutNoBackup = "There's no backup of your journal key. Without it, you can't sign back in, and your private reflections can't be opened on any other device."
    static let backUpFirst = "Back up first"
    static let signOutAnyway = "Sign out anyway"
    static let cancel = "Cancel"
    static let signOutFailed = "Couldn't sign out just now. Nothing has changed."

    // F8
    static let remove = "Remove account and local data"
    static let removeHeading = "Remove account and local data?"
    static let removeBody = "This removes your journal key and every reflection from this iPhone. Reflections already saved to your account stay there."
    static func removeUnsynced(_ n: Int) -> String {
        "\(n) \(n == 1 ? "reflection is" : "reflections are") only on this iPhone and will be permanently deleted."
    }
    static let removeNoBackup = "There's no backup of your journal key, so the reflections saved to your account can't be opened again."
    static func removeIncludesOther(_ n: Int) -> String {
        "This includes \(n) \(n == 1 ? "reflection" : "reflections") from another account."
    }
    static let removeButton = "Remove"
    static func removeSecond(_ n: Int) -> String {
        n > 0 ? "Permanently delete \(n) \(n == 1 ? "reflection" : "reflections") from this iPhone?" : "Remove everything from this iPhone?"
    }
    static let delete = "Delete"
    static let deleteBackupHeading = "Also delete the iCloud backup of your journal key?"
    static let deleteBackupBody = "If you delete it, you can't restore this journal key later, and reflections saved to your account can only be opened with it."
    static let keepBackup = "Keep backup"
    static let deleteBackup = "Delete backup"
    /// Key delete not confirmed (Prep, flows doc "Key delete not confirmed",
    /// Audit #13 L1). Makes no claim about the key. Shown with [Try again].
    static let removeUnconfirmed = "We couldn't confirm that your journal key was removed from this iPhone. Your reflections haven't been deleted."
    static let signOutUnconfirmed = "We couldn't confirm that you've been signed out on this iPhone. Your reflections are still here."
    /// Audit M5a L3; Prep's final copy. True because restore never
    /// overwrites or deletes a backup.
    static func backupsSkipped(_ n: Int) -> String {
        n == 1 ? "One backup couldn't be read, so it isn't listed. It hasn't been deleted."
            : "\(n) backups couldn't be read, so they aren't listed. They haven't been deleted."
    }
    static let removeNothingDone = "Couldn't remove everything just now. Nothing has been deleted."
    static let removeKeyOnly = "Your journal key was removed, but the reflections on this iPhone couldn't be deleted yet."

    // Days from another account
    static let fromAnotherAccount = "From another account"
    static let fromAnotherAccountExplain = "This reflection was written while signed in to a different account. It stays on this iPhone, read-only, and isn't saved to the account you're using now."
    static let alsoWroteToday = "You also wrote today under another account."
    static func otherAccountKept(_ n: Int) -> String {
        "\(n) earlier \(n == 1 ? "reflection" : "reflections") from another account \(n == 1 ? "is" : "are") kept on this iPhone."
    }

    // Export (show journal key). Prep's final strings, "Part 1 — Final UX
    // and security copy" in the key export doc. Change only with that doc.
    static let exportSection = "Advanced"
    static let exportRow = "Use your journal key in another app"
    static let exportTitle = "Journal key"
    static let exportIntroHeading = "Your journal key is your account"
    static let exportIntroBody1 = "Your journal key is your Nostr secret key (nsec). Paste it into another Nostr app to use the same account there."
    static let exportIntroBody2 = "Anyone who has it can read all your private reflections, including earlier versions, and save to your account as you. This can't be undone by changing a password. There isn't one."
    static let exportBullets = [
        "Only paste it into an app you trust.",
        "Never send it in a message or email, or post it.",
        "No one from Grateful Day will ever ask you for it.",
        // Seth P165 (Option 2): a browser's Save Password prompt isn't the
        // app's own iCloud Keychain backup.
        "If your browser offers to save your private key as a password, choose Not Now.",
    ]
    static let exportShow = "Show journal key"
    /// Also `NSFaceIDUsageDescription` in the app target's Info.plist settings.
    static let exportAuthReason = "Confirm it's you to show your journal key."
    static let exportNoPasscode = "To show your journal key, turn on a passcode for this iPhone in Settings."
    static let exportAccount = "Account"
    static let exportReveal = "Show"
    static let exportConceal = "Hide"
    static let exportCopy = "Copy journal key"
    static let exportCopied = "Copied. It will be cleared from the clipboard in 1 minute. Paste it now."
    static let exportCaptured = "Your screen is being recorded or shared, so your key is hidden."
    static let exportScreenshot = "Your screenshot includes your journal key. Delete it from Photos, and from Recently Deleted."
    static let exportHiddenLabel = "Journal key, hidden"
    static let exportVoiceOverHint = "VoiceOver reads your key aloud. Use headphones if others are nearby."
    static let exportDone = "Done"
}
