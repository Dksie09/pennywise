# Penny — personal expense tracker for iPhone

Logs UPI, card and receipt-email spending automatically. Everything stays on your phone.

- **Home**: what you spent this month, compared with the same days last month, plus a bar per day (tap a bar to see just that day) and every payment grouped by day
- **Breakdown**: totals per place or per tag for the month
- **Tap a payment** to rename the vendor, add tags or a note, see receipt line items, or mark it as a refund or "don't count"
- **Saved payees**: e.g. a therapist's UPI name or number becomes "Therapist" with the `#health` tag, for past and future payments
- **No double counting**: the same SMS twice, two SMS for one debit, or a bank SMS plus the receipt email for the same payment all become one entry
- **Private**: no server, no login, no analytics, no network calls. Data is stored with SwiftData on the device. You can export to CSV.

## 1. Install on your iPhone (needs a Mac with Xcode 15+)

```bash
brew install xcodegen
```

```bash
cd Penny && xcodegen && open Penny.xcodeproj
```

In Xcode, open target **Penny**, then **Signing & Capabilities**:
- Choose your Apple ID as the Team
- Change the bundle ID to something unique, e.g. `com.<yourname>.penny`

Plug in your iPhone and press Run. On the phone, turn on **Settings → Privacy & Security → Developer Mode**, then trust your developer certificate under **Settings → General → VPN & Device Management**.

> With a free Apple ID the app expires after 7 days. Press Run again to renew it; your data is kept. A paid developer account ($99/yr) extends this to a year.

**No XcodeGen?** In Xcode, create a new iOS App called `Penny` (SwiftUI, Storage: None). Delete the generated `ContentView.swift` and `PennyApp.swift`, then drag the `Penny/` folder from this repo into the project.

## 2. Set up automatic logging (one-time, in the Shortcuts app)

iOS doesn't let any app read your SMS or Mail. Instead, a Shortcuts automation passes each message to Penny in the background. The app does not open.

**Bank SMS**
1. Shortcuts → Automation → **+** → **Message**
2. *Message Contains* `Dr INR` → **Run Immediately**, turn off *Notify When Run* → Next
3. New Blank Automation → add **Log Expense Message** (Penny)
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
