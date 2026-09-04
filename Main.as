// Genesis Trackmania - pousse le meilleur temps Contre-la-montre vers l'app.
// Spec : docs/superpowers/specs/2026-09-04-trackmania-plugin-aide-design.md §3.4-3.5
//
// INCERTITUDES (§3.5, non testables ici - à vérifier au premier essai réel) :
//   1. nom exact de la méthode MLFeed pour le joueur local
//   2. nom exact de la propriété du meilleur temps total
//   3. LocalUser.WebServicesUserId peut être vide en solo local pur
//   4. syntaxe exacte Json::Object/Json::Write/Json::Parse
//   5. syntaxe exacte de déclaration de dépendance dans info.toml

string LocalAccountId() {
  auto net = GetApp().Network;
  if (net is null) return "";
  auto pg = cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground);
  if (pg is null || pg.LocalUser is null) return "";
  return pg.LocalUser.WebServicesUserId;
}

string LocalName() {
  auto net = GetApp().Network;
  auto pg = (net !is null) ? cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground) : null;
  return (pg !is null && pg.LocalUser !is null) ? pg.LocalUser.Name : "";
}

string CurrentMapUid() {
  auto app = GetApp();
  return (app.RootMap !is null && app.RootMap.MapInfo !is null) ? app.RootMap.MapInfo.MapUid : "";
}

string g_status = "Inactif.";

void TryPair() {
  if (Setting_Token != "" || Setting_ServerUrl == "" || Setting_PairCode == "") return;
  string accId = LocalAccountId();
  if (accId == "") { g_status = "Identite introuvable - relance une carte."; return; }

  Json::Value req = Json::Object();
  req["code"] = Setting_PairCode;
  req["accountId"] = accId;
  req["name"] = LocalName();

  auto r = Net::HttpPost(Setting_ServerUrl + "/api/trackmania/pair", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() != 200) { g_status = "Appairage refuse (" + r.ResponseCode() + ")"; return; }
  Json::Value resp = Json::Parse(r.String());
  Setting_Token = string(resp["token"]);
  Setting_PairCode = "";
  g_status = "Appaire.";
}

float g_lastSentTime = -1.0;   // en mémoire seulement - un redémarrage renvoie
                                 // le PB courant, le serveur ne garde que le min

void TryIngest() {
  if (Setting_Token == "") return;
  auto raceData = MLFeed::GetRaceData_V4();
  if (raceData is null) return;

  auto me = raceData.GetPlayer_V4(LocalName());
  if (me is null) return;

  float best = me.BestTime;
  if (best <= 0.0 || best == g_lastSentTime) return;

  string mapUid = CurrentMapUid();
  if (mapUid == "") return;

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["timeMs"] = int(best * 1000.0);

  auto r = Net::HttpPost(Setting_ServerUrl + "/api/trackmania/ingest", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() == 200) { g_lastSentTime = best; g_status = "Envoye : " + best + "s"; }
  else if (r.ResponseCode() == 401) { Setting_Token = ""; g_status = "Lien expire - re-appaire."; }
  else { g_status = "Erreur (" + r.ResponseCode() + ")"; }
}

void Main() {
  while (true) {
    TryPair();
    TryIngest();
    sleep(1000);
  }
}

bool g_windowOpen = false;

void RenderMenu() {
  if (UI::MenuItem("Genesis Trackmania", "", g_windowOpen)) g_windowOpen = !g_windowOpen;
}

void Render() {
  if (!g_windowOpen) return;
  UI::Begin("Genesis Trackmania", g_windowOpen);
  UI::Text(g_status);
  UI::End();
}
