# Asset & Glyph Inventory

This document is the canonical glyph map for the iOS redesign. Every imageset in `Sources/Assets.xcassets` is listed with its source artwork filename (extracted verbatim from `Contents.json`) and every Swift surface that references it by name. A rebuilder can source equivalent artwork from the Lucide icon library (prefix `li_`) or the bespoke originals noted below, then register each under the same asset-catalog name to achieve a pixel-identical result without access to the original source files.

All imagesets listed here are net-new on the `ios-ui-redesign` branch — none existed on `main` before the redesign. Two imagesets (`DrawerClockGlyph`, `DrawerFilesGlyph`) existed on `main` but had their source SVG replaced; the new filenames are recorded below.

---

## Rendering conventions

All `Glyph` imagesets are SVG vector art rendered as SwiftUI `Image(name).renderingMode(.template)` so they inherit `.foregroundStyle(...)` tint at the call site. The three exceptions are:

- `ChatAvatarImage` — PNG photo composite, rendered **Original** (`.renderingMode` not set), clipped to a 34×34 circle.
- `ConnectionMascotImage`, `openclaw mascot` — PNG illustration, rendered **Original**.
- `OnboardingDustCloud`, `OnboardingStars` — PNG art layers, rendered **Original**, `.scaledToFill()`.
- `ChannelWhatsappGlyph`, `FeedbackTailscaleGlyph` — PNG, rendered **Original** (brand marks). `SettingsChevronsUpDownGlyph` is also a PNG but every call site overrides to `.renderingMode(.template)`, so it renders as a tintable template, not Original.

---

## Domain groups

### Chat

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `ChatAvatarImage` | `Frame 120.png`, `chatavatar2.png`, `chatavatar3.png` | `ChatRootSurface` top-bar avatar pill (34×34 circle, opens drawer on tap) — `ChatRootSurface.swift:943` |
| `ChatBackGlyph` | `li_chevron-left.svg` | `InstancesScreen` header back button — `InstancesScreen.swift:124`; `FilesGridScreen` header back button — `FilesGridScreen.swift:74`; `SkillsScreen` list header back — `SkillsScreen.swift:71`; `UsageScreen` header back — `UsageScreen.swift:72`; `DreamingScreen` header back — `DreamingScreen.swift:66` |
| `ChatCameraGlyph` | `li_camera.svg` | Attachment tray "Camera" row — `ChatRootSurface.swift:1384` |
| `ChatCheckGlyph` | `li_check.svg` | Outgoing bubble meta row: shown when `row.isError` is true (single tick = send failure) — `ChatRootSurface.swift:1984,1999` |
| `ChatCheckCheckGlyph` | `li_check-check.svg` | Outgoing bubble meta row: shown when `row.isError` is false (double tick = delivered) — `ChatRootSurface.swift:1984,1999` |
| `ChatCloseGlyph` | `li_x.svg` | Attachment strip remove button — `ChatRootSurface.swift:1469`; Canvas embed viewer close — `ChatRootSurface.swift:2267`; `ConnectionSheet` close — `ConnectionSheet.swift:125`; `DreamingScreen` skill-detail close — `DreamingScreen.swift:319`; `SkillsScreen` detail close — `SkillsScreen.swift:422`; `ChatDrawer` close button — `ChatDrawer.swift:476`; `ChatImageViewer` close — `ChatImageViewer.swift:111`; `CanvasPanelHeader` (default leading glyph) — `CanvasArtifacts.swift:172` |
| `ChatDownloadGlyph` | `li_download.svg` | `ChatImageViewer` save-image button (shown when `!saved`) — `ChatImageViewer.swift:114` |
| `ChatFilesGlyph` | `li_files.svg` | Attachment tray "Files" row — `ChatRootSurface.swift:1385` |
| `ChatImagePlusGlyph` | `li_image-plus.svg` | Attachment tray "Images" row — `ChatRootSurface.swift:1383` |
| `ChatMicGlyph` | `li_mic.svg` | Composer input field mic button (visible only when attachments list is empty) — `ChatRootSurface.swift:1177` |
| `ChatPlusGlyph` | `li_plus.svg` | `ChatDrawer` header "new session" button — `ChatDrawer.swift:243`; `SettingsDestinationScreens` "Add Channel" pill leading icon — `SettingsDestinationScreens.swift:453`; Wake Words screen header add button — `SettingsDestinationScreens.swift:840` |
| `ChatSettingsGlyph` | `li_settings.svg` | `ChatRootSurface` top-bar settings button (40×40 glass capsule) — `ChatRootSurface.swift:975` |
| `ChatStickerGlyph` | `li_sticker.svg` | Attachment tray "GIFs" row — `ChatRootSurface.swift:1382` |

---

### Drawer (side-nav)

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `DrawerClockGlyph` | `li_clock.svg` *(replaced from `li_clock-12.svg`)* | `ChatDrawer` "Cron Jobs" destination row — `ChatDrawer.swift:284` |
| `DrawerFilesGlyph` | `li_folder-closed.svg` *(replaced from `li_files.svg`)* | `ChatDrawer` "Files" destination row — `ChatDrawer.swift:287` |
| `DrawerMoonStarGlyph` | `li_moon-star.svg` | `ChatDrawer` "Dreaming" destination row — `ChatDrawer.swift:275`; `DreamingScreen` entry list icon (35×35 inside 50.5×50.5 circle tile) — `DreamingScreen.swift:111` |
| `DrawerMoreGlyph` | `li_more-horizontal.svg` | Registered in asset catalog; no Swift call site found on this branch (reserved glyph) |
| `DrawerPaletteGlyph` | `li_palette.svg` | `ChatDrawer` "Canvas" destination row — `ChatDrawer.swift:290` |
| `DrawerPieChartGlyph` | `li_pie-chart.svg` | `ChatDrawer` "Usage" destination row — `ChatDrawer.swift:278` |
| `DrawerScrollGlyph` | `li_scroll-text.svg` | `ChatDrawer` "Skills" destination row — `ChatDrawer.swift:293`; `SkillsScreen` skill detail icon tile fallback (44×44 inside 16-pt-radius card, when skill has no emoji) — `SkillsScreen.swift:463` |
| `DrawerServerGlyph` | `li_server.svg` | `ChatDrawer` "Instances" destination row — `ChatDrawer.swift:281` |

---

### Cron Jobs

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `CronJobsCheckGlyph` | `li_check-circle.svg` | `CronJobsScreen` action button glyph when `!job.enabled` ("Enable" state) — `CronJobsScreen.swift:163` |
| `CronJobsDisableGlyph` | `li_x.svg` | `CronJobsScreen` action button glyph when `job.enabled` ("Disable" state) — `CronJobsScreen.swift:163` |
| `CronJobsPlayGlyph` | `Polygon 3.svg` | `CronJobsScreen` "Run" action button — `CronJobsScreen.swift:159` |
| `CronJobsReloadGlyph` | `li_iteration-ccw.svg` | `CronJobsScreen` recurring-job badge (16×16, tinted `Color(red: 52/255, green: 199/255, blue: 89/255)`) — `CronJobsScreen.swift:203` |

---

### Files

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `FilesFileGlyph` | `li_file.svg` | `FilesGridScreen` tile icon when `!entry.isFolder` (37×37 template, 75 % primary opacity, inside 108pt-tall tile) — `FilesGridScreen.swift:137` |
| `FilesFolderGlyph` | `li_folder.svg` | `FilesGridScreen` tile icon when `entry.isFolder` — `FilesGridScreen.swift:137` |

---

### Canvas

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `CanvasFileGlyph` | `li_file-terminal.svg` | `CanvasThumbnailTile` placeholder glyph (33×33 template, 35 % / 20 % primary in dark/light) — `CanvasArtifacts.swift:154`; `CanvasReplayPanel` failure state glyph (64×64, 15 % primary) — `CanvasArtifacts.swift:396` |

---

### Usage / Filter

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `UsageFilterGlyph` | `li_list-filter.svg` | `DreamingScreen` filter pill (glass chrome menu button) — `DreamingScreen.swift:74`; `UsageScreen` filter pill — `UsageScreen.swift:82`; `CronJobsScreen` filter pill — `CronJobsScreen.swift:105` |

---

### Skills

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `SkillScrollGlyph` | `li_scroll.svg` | `SkillsScreen` skill list row icon tile fallback (35×35 inside 45×45 rounded rect, when skill has no emoji) — `SkillsScreen.swift:157` |

---

### Settings

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `SettingsArrowUpRightGlyph` | `li_arrow-up-right.svg` | `SettingsRootScreen` external link-pill rows (trailing icon, replaces chevron for URLs that open in browser) — `SettingsRootScreen.swift:296` |
| `SettingsBellGlyph` | `li_bell.svg` | `SettingsRootScreen` "Notifications" card row icon — `SettingsRootScreen.swift:53` |
| `SettingsBookGlyph` | `li_book-open.svg` | `SettingsRootScreen` "Docs" link-pill icon — `SettingsRootScreen.swift:71` |
| `SettingsChevronRightGlyph` | `li_chevron-left.svg` *(note: artwork faces right despite filename)* | Used as trailing disclosure chevron throughout: `SettingsRootScreen` card rows — `SettingsRootScreen.swift:212`; `CanvasEmbedCard` — `CanvasArtifacts.swift:237`; `DreamingScreen` entry row — `DreamingScreen.swift:133`; `InstancesScreen` row — `InstancesScreen.swift:89`; `LicenseDocuments` row — `LicenseDocuments.swift:135`; `SettingsDestinationScreens` multiple rows — `SettingsDestinationScreens.swift:154,696`; `SkillsScreen` skill name — `SkillsScreen.swift:120`; `PermissionsScreen` row — `SettingsDestinationScreens.swift:154` |
| `SettingsChevronsUpDownGlyph` | `li_chevrons-up-down.png` *(PNG raster)* | `ConnectionSheet` gateway access level picker — `ConnectionSheet.swift:231`; `SettingsRootScreen` default-agent picker — `SettingsRootScreen.swift:314`; `VoiceSettingsScreen` picker rows — `SettingsDestinationScreens.swift:678` |
| `SettingsFileWarningGlyph` | `li_file-warning.svg` | `SettingsRootScreen` "Licenses" card row icon — `SettingsRootScreen.swift:76` |
| `SettingsRefreshGlyph` | `li_refresh-cw.svg` | Wake Words screen "Reset Defaults" destructive row (tinted `Self.resetRed`) — `SettingsDestinationScreens.swift:882` |
| `SettingsShieldGlyph` | `shield.svg` | `SettingsRootScreen` "Approvals" card row icon — `SettingsRootScreen.swift:45` |
| `SettingsSunGlyph` | `li_sun-medium.svg` | `SettingsRootScreen` Appearance section theme picker row — `SettingsRootScreen.swift:257` |
| `SettingsToggleGlyph` | `li_toggle-right.svg` | `SettingsRootScreen` "Permissions" card row icon — `SettingsRootScreen.swift:47` |
| `SettingsUnplugGlyph` | `li_unplug.svg` | `SettingsRootScreen` "Channels & Integrations" card row icon — `SettingsRootScreen.swift:58`; `ChannelsScreen` channel pill fallback icon (when `channel.iconAsset` is nil) — `SettingsDestinationScreens.swift:413` |
| `SettingsUsersGlyph` | `li_users.svg` | `SettingsRootScreen` "Default Agent" row icon — `SettingsRootScreen.swift:226` |
| `SettingsWaveformGlyph` | `waveform.svg` | `SettingsRootScreen` "Voice settings" card row icon — `SettingsRootScreen.swift:63` |
| `SettingsWifiGlyph` | `li_wifi.svg` | `SettingsRootScreen` "Connection" pill leading icon (tinted `OpenClawBrand.welcomeLink`) — `SettingsRootScreen.swift:171` |

---

### Permissions

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `PermissionsCalendarGlyph` | `li_calendar-days.svg` | `PermissionsScreen` "Calendar" row icon — `SettingsDestinationScreens.swift:102` |
| `PermissionsCameraGlyph` | `permissions camera.svg` | `PermissionsScreen` "Camera" row icon — `SettingsDestinationScreens.swift:112` |
| `PermissionsClipboardGlyph` | `li_clipboard-list.svg` | `PermissionsScreen` "Reminders" row icon — `SettingsDestinationScreens.swift:104` |
| `PermissionsContactGlyph` | `li_contact.svg` | `PermissionsScreen` "Contacts" row icon — `SettingsDestinationScreens.swift:106` |
| `PermissionsImageGlyph` | `li_image.svg` | `PermissionsScreen` "Photos" row icon — `SettingsDestinationScreens.swift:110` |
| `PermissionsMicGlyph` | `permissions mic.svg` | `PermissionsScreen` "Microphone" row icon — `SettingsDestinationScreens.swift:108` |
| `PermissionsPinGlyph` | `li_map-pin.svg` | `PermissionsScreen` "Location" row icon — `SettingsDestinationScreens.swift:100` |

---

### Channels

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `ChannelDiscordGlyph` | `discord icon.svg` | `ChannelsScreen` channel pill brand icon for channel id `"discord"` (22×22 Original, no template) — `SettingsDestinationScreens.swift:515` |
| `ChannelTelegramGlyph` | `telegram icon.svg` | `ChannelsScreen` channel pill brand icon for channel id `"telegram"` — `SettingsDestinationScreens.swift:515` |
| `ChannelWhatsappGlyph` | `whatsapp icon.png` *(PNG)* | `ChannelsScreen` channel pill brand icon for channel id `"whatsapp"` — `SettingsDestinationScreens.swift:517` |

The `brandAsset(_:)` switch in `ChannelsScreenHost` maps lowercase channel IDs to these three names; any unknown id falls back to `SettingsUnplugGlyph` — `SettingsDestinationScreens.swift:513–519`.

---

### Feedback / Setup (Onboarding connection flow)

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `FeedbackCopyGlyph` | `Copy1.svg` | `ChatCodeBlock` "Copy" button icon (14×14, toggled to SF Symbol `checkmark` after copy) — `ChatRootSurface.swift:2758` |
| `FeedbackErrorGlyph` | `exclamcircled.svg` | `OnboardingFeedbackStep` `.error` state glyph (via `stateGlyph`) — `OnboardingWizardSteps.swift:1152` |
| `FeedbackInfoGlyph` | `infocircledyellow.svg` | `OnboardingFeedbackStep` `.awaitingApproval` state glyph — `OnboardingWizardSteps.swift:1048` |
| `FeedbackLoaderGlyph` | `li_loader.svg` | `FeedbackLoaderSpinner` — 70×70, continuous `rotationEffect` 0→360, `.linear(duration: 1.2).repeatForever(autoreverses: false)` — `OnboardingWizardSteps.swift:1385` |
| `FeedbackSuccessGlyph` | `greencheckmark.svg` | `OnboardingSuccessStepView` — 70×70 — `OnboardingWizardSteps.swift:1407` |
| `FeedbackTailscaleGlyph` | `tailscale icon.png` *(PNG)* | `OnboardingFeedbackStep` `.installTailscale` state glyph — `OnboardingWizardSteps.swift:1099` |
| `SetupCheckGlyph` | `Check Circled.svg` | `SetupCheckIcon` light-mode variant (24×24); also `ChannelsScreen` connected-channel pill trailing checkmark — `OnboardingWizardSteps.swift:878`; `SettingsDestinationScreens.swift:437` |
| `SetupCheckDarkGlyph` | `Check Circled dark.svg` | `SetupCheckIcon` dark-mode variant (24×24) — `OnboardingWizardSteps.swift:878` |
| `SetupErrorGlyph` | `xcircledred.svg` | `SetupErrorIcon` light-mode variant (21×21) — `OnboardingWizardSteps.swift:889` |
| `SetupErrorDarkGlyph` | `blackredcircle.svg` | `SetupErrorIcon` dark-mode variant (21×21) — `OnboardingWizardSteps.swift:889` |
| `SetupSpinnerGlyph` | `li_loader-2.svg` | `SetupScanningSpinner` — 24×24 template, continuous `rotationEffect`, `.linear(duration: 0.9).repeatForever(autoreverses: false)` — `OnboardingWizardSteps.swift:860` |

`SetupCheckGlyph`/`SetupCheckDarkGlyph` and `SetupErrorGlyph`/`SetupErrorDarkGlyph` are paired light/dark variants selected via `@Environment(\.colorScheme)` rather than using a single adaptive asset. This lets the artwork itself differ (not just tint) between modes.

---

### Onboarding

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `OnboardingDustCloud` | `Dust Cloud.png` | `OnboardingWelcomeStep` background — dark-mode only overlay, `.scaledToFill()`, `accessibilityHidden(true)` — `OnboardingWizardSteps.swift:358` |
| `OnboardingStars` | `Stars.png` | `OnboardingWelcomeStep` background — dark-mode only overlay above dust cloud, `.scaledToFill()` — `OnboardingWizardSteps.swift:361` |
| `QRCodeGlyph` | `qrcode.svg` | `OnboardingWelcomeStep` "Scan QR Code" primary pill button leading icon (24×24) — `OnboardingWizardSteps.swift:317` |

---

### Connection / Mascot

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `ConnectionMascotImage` | `image 15.png` | `ConnectionSheet` top hero image (139×139, `.scaledToFit()`, `.padding(.top, 56)`) — `ConnectionSheet.swift:35` |

---

### Mascot / Avatar

| Asset name | Source file | Consuming surface(s) |
|---|---|---|
| `openclaw mascot` | `openclaw.png` | `OnboardingWelcomeStep` mascot hero (146×146, shadow `OpenClawBrand.welcomeGlow` radius 10, `accessibilityHidden(true)`) — `OnboardingWizardSteps.swift:293` |

---

## Summary table (all 71 imagesets)

| # | Asset name | Source filename | Domain | Notes |
|---|---|---|---|---|
| 1 | `CanvasFileGlyph` | `li_file-terminal.svg` | Canvas | Template SVG |
| 2 | `ChannelDiscordGlyph` | `discord icon.svg` | Channels | Original (brand color) |
| 3 | `ChannelTelegramGlyph` | `telegram icon.svg` | Channels | Original (brand color) |
| 4 | `ChannelWhatsappGlyph` | `whatsapp icon.png` | Channels | PNG, Original |
| 5 | `ChatAvatarImage` | `Frame 120.png` + 2 variants | Chat | PNG, Original, 3-variant |
| 6 | `ChatBackGlyph` | `li_chevron-left.svg` | Chat | Template SVG |
| 7 | `ChatCameraGlyph` | `li_camera.svg` | Chat | Template SVG |
| 8 | `ChatCheckCheckGlyph` | `li_check-check.svg` | Chat | Template SVG |
| 9 | `ChatCheckGlyph` | `li_check.svg` | Chat | Template SVG |
| 10 | `ChatCloseGlyph` | `li_x.svg` | Chat | Template SVG |
| 11 | `ChatDownloadGlyph` | `li_download.svg` | Chat | Template SVG |
| 12 | `ChatFilesGlyph` | `li_files.svg` | Chat | Template SVG |
| 13 | `ChatImagePlusGlyph` | `li_image-plus.svg` | Chat | Template SVG |
| 14 | `ChatMicGlyph` | `li_mic.svg` | Chat | Template SVG |
| 15 | `ChatPlusGlyph` | `li_plus.svg` | Chat | Template SVG |
| 16 | `ChatSettingsGlyph` | `li_settings.svg` | Chat | Template SVG |
| 17 | `ChatStickerGlyph` | `li_sticker.svg` | Chat | Template SVG |
| 18 | `ConnectionMascotImage` | `image 15.png` | Connection | PNG, Original |
| 19 | `CronJobsCheckGlyph` | `li_check-circle.svg` | Cron | Template SVG |
| 20 | `CronJobsDisableGlyph` | `li_x.svg` | Cron | Template SVG |
| 21 | `CronJobsPlayGlyph` | `Polygon 3.svg` | Cron | Bespoke play triangle |
| 22 | `CronJobsReloadGlyph` | `li_iteration-ccw.svg` | Cron | Template SVG |
| 23 | `DrawerClockGlyph` | `li_clock.svg` | Drawer | Template SVG |
| 24 | `DrawerFilesGlyph` | `li_folder-closed.svg` | Drawer | Template SVG |
| 25 | `DrawerMoonStarGlyph` | `li_moon-star.svg` | Drawer | Template SVG |
| 26 | `DrawerMoreGlyph` | `li_more-horizontal.svg` | Drawer | Template SVG; reserved, no active call site |
| 27 | `DrawerPaletteGlyph` | `li_palette.svg` | Drawer | Template SVG |
| 28 | `DrawerPieChartGlyph` | `li_pie-chart.svg` | Drawer | Template SVG |
| 29 | `DrawerScrollGlyph` | `li_scroll-text.svg` | Drawer | Template SVG |
| 30 | `DrawerServerGlyph` | `li_server.svg` | Drawer | Template SVG |
| 31 | `FeedbackCopyGlyph` | `Copy1.svg` | Feedback | Template SVG |
| 32 | `FeedbackErrorGlyph` | `exclamcircled.svg` | Feedback | Bespoke (custom red circle) |
| 33 | `FeedbackInfoGlyph` | `infocircledyellow.svg` | Feedback | Bespoke (yellow info circle) |
| 34 | `FeedbackLoaderGlyph` | `li_loader.svg` | Feedback | Template SVG; spin animation |
| 35 | `FeedbackSuccessGlyph` | `greencheckmark.svg` | Feedback | Bespoke (green checkmark) |
| 36 | `FeedbackTailscaleGlyph` | `tailscale icon.png` | Feedback | PNG, Original (brand mark) |
| 37 | `FilesFileGlyph` | `li_file.svg` | Files | Template SVG |
| 38 | `FilesFolderGlyph` | `li_folder.svg` | Files | Template SVG |
| 39 | `OnboardingDustCloud` | `Dust Cloud.png` | Onboarding | PNG, Original, dark-mode only |
| 40 | `OnboardingStars` | `Stars.png` | Onboarding | PNG, Original, dark-mode only |
| 41 | `PermissionsCalendarGlyph` | `li_calendar-days.svg` | Permissions | Template SVG |
| 42 | `PermissionsCameraGlyph` | `permissions camera.svg` | Permissions | Bespoke SVG (not standard Lucide) |
| 43 | `PermissionsClipboardGlyph` | `li_clipboard-list.svg` | Permissions | Template SVG |
| 44 | `PermissionsContactGlyph` | `li_contact.svg` | Permissions | Template SVG |
| 45 | `PermissionsImageGlyph` | `li_image.svg` | Permissions | Template SVG |
| 46 | `PermissionsMicGlyph` | `permissions mic.svg` | Permissions | Bespoke SVG (not standard Lucide) |
| 47 | `PermissionsPinGlyph` | `li_map-pin.svg` | Permissions | Template SVG |
| 48 | `QRCodeGlyph` | `qrcode.svg` | Onboarding | Template SVG |
| 49 | `SettingsArrowUpRightGlyph` | `li_arrow-up-right.svg` | Settings | Template SVG |
| 50 | `SettingsBellGlyph` | `li_bell.svg` | Settings | Template SVG |
| 51 | `SettingsBookGlyph` | `li_book-open.svg` | Settings | Template SVG |
| 52 | `SettingsChevronRightGlyph` | `li_chevron-left.svg` | Settings | Template SVG; artwork faces right |
| 53 | `SettingsChevronsUpDownGlyph` | `li_chevrons-up-down.png` | Settings | PNG; call sites override to `.renderingMode(.template)` |
| 54 | `SettingsFileWarningGlyph` | `li_file-warning.svg` | Settings | Template SVG |
| 55 | `SettingsRefreshGlyph` | `li_refresh-cw.svg` | Settings | Template SVG |
| 56 | `SettingsShieldGlyph` | `shield.svg` | Settings | Bespoke SVG |
| 57 | `SettingsSunGlyph` | `li_sun-medium.svg` | Settings | Template SVG |
| 58 | `SettingsToggleGlyph` | `li_toggle-right.svg` | Settings | Template SVG |
| 59 | `SettingsUnplugGlyph` | `li_unplug.svg` | Settings | Template SVG; also channel fallback |
| 60 | `SettingsUsersGlyph` | `li_users.svg` | Settings | Template SVG |
| 61 | `SettingsWaveformGlyph` | `waveform.svg` | Settings | Bespoke SVG |
| 62 | `SettingsWifiGlyph` | `li_wifi.svg` | Settings | Template SVG |
| 63 | `SetupCheckDarkGlyph` | `Check Circled dark.svg` | Setup | Bespoke; dark-mode only |
| 64 | `SetupCheckGlyph` | `Check Circled.svg` | Setup | Bespoke; light-mode + channels |
| 65 | `SetupErrorDarkGlyph` | `blackredcircle.svg` | Setup | Bespoke; dark-mode only |
| 66 | `SetupErrorGlyph` | `xcircledred.svg` | Setup | Bespoke; light-mode only |
| 67 | `SetupSpinnerGlyph` | `li_loader-2.svg` | Setup | Template SVG; spin animation |
| 68 | `SkillScrollGlyph` | `li_scroll.svg` | Skill | Template SVG |
| 69 | `UsageFilterGlyph` | `li_list-filter.svg` | Usage | Template SVG |
| 70 | `openclaw mascot` | `openclaw.png` | Mascot | PNG, Original |

> Note: The asset catalog root `Contents.json` (entry 71) is not an imageset — it is the catalog namespace descriptor and carries no artwork.

---

## Lucide source mapping

Most `li_*` filenames correspond to Lucide icons by the same base name. The mapping between the file stem and the published Lucide icon name is straightforward: strip the `li_` prefix. Confirmed mappings:

| File stem (drop `li_`) | Lucide icon name |
|---|---|
| `arrow-up-right` | `arrow-up-right` |
| `bell` | `bell` |
| `book-open` | `book-open` |
| `calendar-days` | `calendar-days` |
| `camera` | `camera` |
| `check` | `check` |
| `check-check` | `check-check` |
| `check-circle` | `check-circle` |
| `chevron-left` | `chevron-left` |
| `chevrons-up-down` | `chevrons-up-down` |
| `clipboard-list` | `clipboard-list` |
| `clock` | `clock` |
| `contact` | `contact` |
| `download` | `download` |
| `file` | `file` |
| `file-terminal` | `file-terminal` |
| `file-warning` | `file-warning` |
| `files` | `files` |
| `folder` | `folder` |
| `folder-closed` | `folder-closed` |
| `image` | `image` |
| `image-plus` | `image-plus` |
| `iteration-ccw` | `iteration-ccw` |
| `list-filter` | `list-filter` |
| `loader` | `loader` |
| `loader-2` | `loader-2` |
| `map-pin` | `map-pin` |
| `mic` | `mic` |
| `moon-star` | `moon-star` |
| `more-horizontal` | `more-horizontal` |
| `palette` | `palette` |
| `pie-chart` | `pie-chart` |
| `plus` | `plus` |
| `refresh-cw` | `refresh-cw` |
| `scroll` | `scroll` |
| `scroll-text` | `scroll-text` |
| `server` | `server` |
| `settings` | `settings` |
| `sticker` | `sticker` |
| `sun-medium` | `sun-medium` |
| `toggle-right` | `toggle-right` |
| `unplug` | `unplug` |
| `users` | `users` |
| `wifi` | `wifi` |
| `x` | `x` |

Bespoke artwork that has no Lucide equivalent: `Polygon 3.svg` (play triangle for cron), `Copy1.svg`, `exclamcircled.svg`, `infocircledyellow.svg`, `greencheckmark.svg`, `Check Circled.svg`, `Check Circled dark.svg`, `xcircledred.svg`, `blackredcircle.svg`, `shield.svg`, `waveform.svg`, `permissions camera.svg`, `permissions mic.svg`, `qrcode.svg`, and all PNG originals.
