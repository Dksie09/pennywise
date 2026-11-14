# Pennywise — personal expense tracker for iPhone

Shows as **Pennywise** on the home screen and **Penny** inside the app.

Logs UPI, card and receipt-email spending automatically. Everything stays on your phone.

- **Home**: what you spent this month, compared with the same days last month, plus a bar per day (tap a bar to see just that day) and every payment grouped by day. Swipe a payment right to open it, left to delete
- **Penny ⌄**: tap the title to switch between Home, **Calendar** (the month as a grid, shaded by spending) and **Breakdown** (where the money went, by place or tag, as a list or tiles)
- **Add** (+): paste a bank SMS or receipt, or add by hand with the keypad
- **Tap a payment** to see it; **Edit** to change the name, amount, date, tags, note or type (expense, refund, money received, transfer, excluded). *More details* shows the account, reference and original SMS
- **Saved payees**: e.g. a therapist's UPI name or number becomes "Therapist" with the `health` tag, for past and future payments
- **Remembered tags**: tag a payment and its place's new payments get the same tags (the latest tags you choose win). Turn it off, or tag untagged past payments in one go, in Settings
- **No double counting**: the same SMS twice, two SMS for one debit, or a bank SMS plus the receipt email for the same payment all become one entry
- **Private**: no server, no login, no analytics, no network calls. Data is stored with SwiftData on the device. You can export to CSV.

## 1. Install on your iPhone (needs a Mac with Xcode 15+)

```bash
brew install xcodegen
cd penny && xcodegen && open Penny.xcodeproj
```

Signing is preset in `project.yml` (`DEVELOPMENT_TEAM`, bundle ID `com.dksie09.pennywise`). If you build with a different Apple ID, change those two values and run `xcodegen` again.

1. Plug your iPhone into the Mac with a cable and unlock it. Tap **Trust** if asked.
2. In Xcode's toolbar, pick your iPhone as the run destination, then press **Run** (⌘R).
3. First time only, on the phone:
   - **Settings → Privacy & Security → Developer Mode** → on, then restart the phone
   - After the first install, **Settings → General → VPN & Device Management** → your Apple ID → **Trust**
4. Press Run again. Pennywise opens on your phone.

> With a free Apple ID the app stops opening after 7 days. Plug in and press Run again to renew it; your data is kept. A paid developer account ($99/yr) extends this to a year.

**No XcodeGen?** In Xcode, create a new iOS App called `Penny` (display name Pennywise) (SwiftUI, Storage: None). Delete the generated `ContentView.swift` and `PennyApp.swift`, then drag the `Penny/` folder from this repo into the project.

## 2. Set up automatic logging (one-time, in the Shortcuts app)

iOS doesn't let any app read your SMS or Mail. Instead, a Shortcuts automation passes each message to Penny in the background. The app does not open.

**Bank SMS**
1. Shortcuts → Automation → **+** → **Message**
2. *Message Contains* `Dr INR` → **Run Immediately**, turn off *Notify When Run* → Next
3. New Blank Automation → add **Log Expense Message** (Pennywise)
4. Tap *Message* → **Shortcut Input**, then tap it again and choose **Content**
5. Optional: repeat with `Cr INR` to track money received

**Receipt emails** (Apple Mail app; add your Gmail account to Mail if needed)
1. Automation → **+** → **Email** → *Subject Contains* `receipt` → Run Immediately
2. Add a **Text** action: `Shortcut Input › Subject`, new line, `Shortcut Input › Body`
3. Add **Log Expense Message** with that Text
4. Optional: repeat for `invoice` / `order`

To check that it works, paste any bank SMS into the app's **Add payment** screen.

## How de-duplication works

| Situation | Rule |
|---|---|
| Same message twice | SHA-256 fingerprint of the normalised text |
| Two SMS for one debit | Same amount and the same UPI/card reference or the same balance |
| Receipt + bank SMS (either order) | Within 4 days and the vendor names match (or the INR amounts match). Merged into one entry: the bank's INR amount counts, and the receipt adds the USD amount and line items |
| Same receipt twice | Same receipt number, or same vendor, amount and day |

## Code layout

- `Penny/Parser.swift`: SMS and receipt parsing (pure functions, unit-tested)
- `Penny/Ingestor.swift`: de-duplication and merging into the database
- `Penny/Intents.swift`: the "Log Expense Message" Shortcuts action
- `Penny/Models.swift`: `Txn` and `Payee` models
- `Penny/Views/`: SwiftUI screens
- `PennyTests/`: tests built from your real message formats (run with ⌘U)

## Ideas for later
- Face ID lock
- Item extraction from Blinkit / Zepto / Swiggy order emails
- Monthly budget and alerts, trends across months, home-screen widget
