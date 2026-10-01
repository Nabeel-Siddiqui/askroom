// Playwright driver invoked by scripts/record_demo (see that file for
// setup/usage). Opens two windows against the already-running local
// server — a phone-sized audience view and a desktop-sized projector
// view, both already "inside" the seeded demo event — and records
// until an audience vote cast on the phone shows up as a live bar-
// chart update on the projector, with no page reload on either side.

import { chromium } from "playwright";
import { mkdirSync, renameSync, readdirSync } from "node:fs";
import { join } from "node:path";

const BASE_URL = "http://localhost:4000";
const PRESENTER_EMAIL = "demo@askroom.dev";
const PRESENTER_PASSWORD = "demo-password-please-change";
const EVENT_ID = process.env.DEMO_EVENT_ID;
const JOIN_CODE = process.env.DEMO_JOIN_CODE;
const OUT_DIR = "tmp_demo_recording";

if (!EVENT_ID || !JOIN_CODE) {
  console.error("DEMO_EVENT_ID and DEMO_JOIN_CODE env vars are required (set by scripts/record_demo)");
  process.exit(1);
}

mkdirSync(OUT_DIR, { recursive: true });

const browser = await chromium.launch();

// Log the presenter in once, outside of any recorded context, and reuse
// the session for the projector recording — nobody wants a GIF of
// someone typing a password.
const warmupContext = await browser.newContext();
const warmupPage = await warmupContext.newPage();
await warmupPage.goto(`${BASE_URL}/presenters/log_in`);
await warmupPage.fill('input[name="presenter[email]"]', PRESENTER_EMAIL);
await warmupPage.fill('input[name="presenter[password]"]', PRESENTER_PASSWORD);
await Promise.all([
  warmupPage.waitForLoadState("load"),
  warmupPage.getByRole("button", { name: "Log in" }).click(),
]);
const presenterStorageState = await warmupContext.storageState();
await warmupContext.close();

// Desktop window: the projector, logged in as the presenter.
const desktopDir = join(OUT_DIR, "desktop");
mkdirSync(desktopDir, { recursive: true });
const desktopContext = await browser.newContext({
  storageState: presenterStorageState,
  viewport: { width: 960, height: 640 },
  recordVideo: { dir: desktopDir, size: { width: 960, height: 640 } },
});
const desktopPage = await desktopContext.newPage();

// Phone-sized window: a brand-new audience participant, joined fresh —
// the join flow itself (scanning a code, landing straight on the event)
// is part of what's worth showing.
const phoneDir = join(OUT_DIR, "phone");
mkdirSync(phoneDir, { recursive: true });
const phoneContext = await browser.newContext({
  viewport: { width: 390, height: 760 },
  recordVideo: { dir: phoneDir, size: { width: 390, height: 760 } },
});
const phonePage = await phoneContext.newPage();

await Promise.all([
  desktopPage.goto(`${BASE_URL}/dashboard/events/${EVENT_ID}/projector`),
  phonePage.goto(`${BASE_URL}/join/${JOIN_CODE}`),
]);

// Scroll the phone to the live poll so the tap that's about to happen
// is in frame, and give both LiveViews a moment to settle first.
await phonePage.getByText("Which feature should we build next?").scrollIntoViewIfNeeded();
await desktopPage.waitForTimeout(800);

// The single moment: tap an answer on the phone, watch its bar appear
// on the projector, live, with no reload on either screen.
await phonePage.getByRole("button", { name: "Word cloud" }).click();

const wordCloudRow = desktopPage.locator("div", { hasText: "Word cloud" }).last();
await wordCloudRow.locator("span.font-bold", { hasText: "1" }).waitFor({ state: "visible", timeout: 10_000 });

// Hold briefly so a viewer's eye can land on the result.
await desktopPage.waitForTimeout(1_200);

await desktopContext.close();
await phoneContext.close();
await browser.close();

// Playwright names video files after an internal id, not something
// predictable — find each one and give it a stable name for ffmpeg.
const desktopVideo = readdirSync(desktopDir).find((f) => f.endsWith(".webm"));
const phoneVideo = readdirSync(phoneDir).find((f) => f.endsWith(".webm"));
renameSync(join(desktopDir, desktopVideo), join(OUT_DIR, "desktop.webm"));
renameSync(join(phoneDir, phoneVideo), join(OUT_DIR, "phone.webm"));

console.log("Recorded:", join(OUT_DIR, "desktop.webm"), join(OUT_DIR, "phone.webm"));
