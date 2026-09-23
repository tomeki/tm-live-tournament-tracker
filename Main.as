// Live Tournament Tracker plugin - reports the local player's Time Attack results
// to the Genesis Tournament server.

// Prefer the playground path: proven correct while racing. LocalPlayerInfo
// (CGameCtnApp, the app-level base class) is a fallback for menu/loading
// screens, where ClientManiaAppPlayground is null.
string LocalAccountId() {
  auto net = GetApp().Network;
  if (net !is null) {
    auto pg = cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground);
    if (pg !is null && pg.LocalUser !is null) return pg.LocalUser.WebServicesUserId;
  }
  auto info = GetApp().LocalPlayerInfo;
  if (info is null) return "";
  return info.WebServicesUserId;
}

string LocalName() {
  auto net = GetApp().Network;
  if (net !is null) {
    auto pg = cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground);
    if (pg !is null && pg.LocalUser !is null) return pg.LocalUser.Name;
  }
  auto info = GetApp().LocalPlayerInfo;
  if (info is null) return "";
  return info.Name;
}

string CurrentMapUid() {
  auto app = GetApp();
  if (app.RootMap is null || app.RootMap.MapInfo is null) return "";
  return app.RootMap.MapInfo.MapUid;
}

string CurrentMapName() {
  auto app = GetApp();
  if (app.RootMap is null || app.RootMap.MapInfo is null) return "";
  return app.RootMap.MapInfo.Name;
}

string g_status = "Idle.";

// Strips a trailing slash (e.g. pasted from a browser address bar), which
// would otherwise produce a double slash that doesn't match the server route.
string ServerUrlTrimmed() {
  string u = Setting_ServerUrl;
  if (u.Length > 0 && u.SubStr(u.Length - 1, 1) == "/") return u.SubStr(0, u.Length - 1);
  return u;
}

// Raised by OnPairCodeChanged() (Settings.as), consumed by Main(). The
// onchange callback isn't a coroutine and can't yield on the HTTP call, so it
// only raises this flag; the actual request happens on the plugin's own tick.
bool g_pairRequested = false;

void RequestPairing() { g_pairRequested = true; }

// Pairing codes are single-use server-side (deleted as soon as a /pair call
// succeeds), so replaying the same code a second time always fails with
// "unknown or expired" - harmless, but worth silencing. onchange can fire
// more than once for what the player perceives as a single edit (e.g. an
// OpenPlanet text field re-committing its still-visible buffer after this
// script clears the setting), so track the last code actually sent and
// ignore a repeat. Snapshotted from the persisted value on the first Main()
// tick, not at declaration - global initializers run before OpenPlanet
// applies settings loaded from disk - so a value merely reloaded from disk
// at startup isn't treated as a fresh edit either.
string g_lastPairCodeSent = "";
bool g_pairStartupSeen = false;

void TryPair() {
  if (!g_pairStartupSeen) { g_pairStartupSeen = true; g_lastPairCodeSent = Setting_PairCode; }
  if (!g_pairRequested) return;
  if (Setting_ServerUrl == "" || Setting_PairCode == "" || Setting_PairCode == g_lastPairCodeSent) {
    g_pairRequested = false;
    return;
  }

  string accId = LocalAccountId();
  // Keep the flag set and retry every tick until an identity is available
  // (e.g. no map loaded yet) - no HTTP call happens until then.
  if (accId == "") { g_status = "Identity not found - wait for a map to load or restart Trackmania."; return; }
  g_lastPairCodeSent = Setting_PairCode;
  g_pairRequested = false;

  // Openplanet-verified identity: a short-lived (~5 min) token the server checks
  // with openplanet.dev. A server that requires it ignores accountId/name below,
  // which are only kept for servers that don't (e.g. a local test server).
  g_status = "Pairing...";
  auto tokenTask = Auth::GetToken();
  while (!tokenTask.Finished()) yield();

  Json::Value req = Json::Object();
  req["code"] = Setting_PairCode;
  req["opToken"] = tokenTask.Token();
  req["accountId"] = accId;
  req["name"] = LocalName();

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/pair", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() != 200) { g_status = "Pairing rejected (" + r.ResponseCode() + ") " + r.String(); return; }
  Json::Value resp = Json::Parse(r.String());
  Setting_Token = string(resp["token"]);
  Setting_PairCode = "";
  // OpenPlanet only writes settings to disk at specific triggers (panel
  // close, plugin reload), not on every script assignment - save explicitly
  // so the token and cleared code survive a full game restart.
  Meta::SaveSettings();
  g_status = "Paired.";
}

// Finish-line detection, per map. g_cpArmed only becomes true after seeing the
// player below the finish threshold (CpCount < CPsToFinish) at least once on
// this map, so resuming with CpCount already at max (player already finished
// before the plugin looked) doesn't register as a fresh finish.
string g_cpMapUid = "";
bool g_cpArmed = false;
int g_lastCpCount = -1;
// True once a real spawn has been seen on the current map (see IsSpawned
// guard in TryIngest). Reset on every map change.
bool g_everSpawnedThisMap = false;

// Tells the active CTM room a new attempt just started (run counter, server
// side). Best-effort and silent, like TryAmbient(): never touches g_status.
void SendAttemptStarted() {
  if (Setting_Token == "") return;
  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/attempt", Json::Write(req), "application/json");
  while (!r.Finished()) yield();
}

// Live progress ping, best-effort and silent (never touches g_status).
// CurrentRaceTime keeps counting after the finish line until the next
// attempt starts, so once cp >= toFinish we freeze on LastCpTime instead.
void SendProgress(int cp, int toFinish, int raceMs) {
  if (Setting_Token == "") return;
  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["cp"] = cp;
  req["cpTotal"] = toFinish;
  req["raceMs"] = raceMs;
  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/progress", Json::Write(req), "application/json");
  while (!r.Finished()) yield();
}

void TryIngest() {
  if (Setting_Token == "") return;
  auto raceData = MLFeed::GetRaceData_V4();
  if (raceData is null) return;

  auto me = raceData.GetPlayer_V4(LocalName());
  if (me is null) return;

  string mapUid = CurrentMapUid();
  if (mapUid == "") return;
  if (mapUid != g_cpMapUid) { g_cpMapUid = mapUid; g_cpArmed = false; g_lastCpCount = -1; g_everSpawnedThisMap = false; }

  // Not actually racing yet (e.g. the solo/ghosts menu right after loading a
  // map): CpCount and CurrentRaceTime can move before the real spawn.
  // IsSpawned distinguishes this from a real run. The same menu reappears
  // between attempts, so only block while no spawn has happened yet on this
  // map - once a real run has happened, keep the frozen progress visible.
  if (me.IsSpawned) g_everSpawnedThisMap = true;
  if (!me.IsSpawned && !g_everSpawnedThisMap) return;

  int cp = me.CpCount;
  int toFinish = int(raceData.CPsToFinish);
  // Racing or just finished: <= (not <) keeps pinging once the finish line is
  // crossed, while the player stays on the results screen. cp resets to 0 as
  // soon as a new attempt starts, resuming the normal ping.
  int liveMs = (cp < toFinish) ? me.CurrentRaceTime : me.LastCpTime;
  if (cp <= toFinish && liveMs > 0) SendProgress(cp, toFinish, liveMs);

  bool justFinished = g_cpArmed && g_lastCpCount < toFinish && cp >= toFinish;
  // New attempt: CpCount drops back to 0. Approximate by nature (also counts
  // a "attempt" if the player spawns without ever driving - MLFeed has no
  // "abandoned" signal), but the IsSpawned guard above at least avoids
  // counting one just from loading the map.
  bool justStarted = (cp == 0 && g_lastCpCount != 0);
  if (cp < toFinish) g_cpArmed = true;
  g_lastCpCount = cp;
  if (justStarted) SendAttemptStarted();
  if (!justFinished) return;

  // LastCpTime ("player's last CP time as on their chronometer") is frozen at
  // the moment CpCount reaches CPsToFinish, so it's the exact time of this
  // run. CurrentRaceTime keeps counting with latency until the next poll and
  // would overshoot by up to one tick.
  int raceMs = me.LastCpTime;
  if (raceMs <= 0) { g_status = "Run ignored (invalid time) - not sent."; return; }

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["mapName"] = CurrentMapName();
  req["timeMs"] = raceMs;
  req["respawns"] = int(me.NbRespawnsRequested);
  Json::Value cps = Json::Array();
  auto cpArr = me.CpTimes;
  if (cpArr !is null) {
    for (uint i = 0; i < cpArr.Length; i++) cps.Add(cpArr[i]);
  }
  req["cpTimes"] = cps;

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ingest", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() == 200) { g_status = "Sent: " + (raceMs / 1000.0) + "s"; }
  else if (r.ResponseCode() == 401) { Setting_Token = ""; Meta::SaveSettings(); g_status = "Link expired - pair again."; }
  else {
    // Distinguish expected server rejections from real errors.
    string reason = "";
    Json::Value errBody = Json::Parse(r.String());
    if (errBody !is null) reason = string(errBody["error"]);
    if (reason == "attempts") g_status = "Run quota reached - normal, your best time is already recorded.";
    else if (reason == "time_up") g_status = "Timer ran out before this run - normal, it doesn't count.";
    else if (reason == "map") g_status = "Map differs from the one locked for this round.";
    else { g_status = "Error (" + r.ResponseCode() + ") " + r.String(); }
  }
}

// Indicative "skill level" signal for the current map: the player's existing
// best time (BestTime), independent of any active room, never written as an
// official time. Rate-limited client-side (~10s at the plugin's 1 Hz tick); a
// server-side floor also exists as a backstop.
int g_ambientTicks = 0;
const int AMBIENT_EVERY_TICKS = 10;

void TryAmbient() {
  if (Setting_Token == "") return;
  g_ambientTicks++;
  if (g_ambientTicks < AMBIENT_EVERY_TICKS) return;
  g_ambientTicks = 0;

  auto raceData = MLFeed::GetRaceData_V4();
  if (raceData is null) return;
  auto me = raceData.GetPlayer_V4(LocalName());
  if (me is null) return;

  int bestMs = me.BestTime;
  if (bestMs <= 0) return;
  string mapUid = CurrentMapUid();
  if (mapUid == "") return;

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["mapName"] = CurrentMapName();
  req["bestMs"] = bestMs;

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ambient", Json::Write(req), "application/json");
  while (!r.Finished()) yield();
  // Silent: never touches g_status, which is reserved for the official flow
  // (TryIngest) so a real "Sent"/"Error" is never drowned out.
}

void Main() {
  while (true) {
    TryPair();
    TryIngest();
    TryAmbient();
    sleep(1000);
  }
}

bool g_windowOpen = false;

void RenderMenu() {
  if (UI::MenuItem("Live Tournament Tracker", "", g_windowOpen)) g_windowOpen = !g_windowOpen;
}

void Render() {
  if (!g_windowOpen) return;
  UI::Begin("Live Tournament Tracker", g_windowOpen);
  // ReadOnly, not plain text: the field stays selectable/copyable (click,
  // Ctrl+A, Ctrl+C) so an error message can be copied instead of retyped.
  UI::InputText("##status", g_status, UI::InputTextFlags::ReadOnly);
  UI::End();
}
