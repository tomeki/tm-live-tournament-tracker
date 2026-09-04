// Genesis Trackmania - pousse le meilleur temps Contre-la-montre vers l'app.
// Spec : docs/superpowers/specs/2026-09-04-trackmania-plugin-aide-design.md §3.4-3.5
//
// INCERTITUDES (§3.5, non testables ici - à vérifier au premier essai réel) :
//   1. nom exact de la méthode MLFeed pour le joueur local
//   2. nom exact de la propriété du meilleur temps total
//   3. LocalUser.WebServicesUserId peut être vide en solo local pur
//   4. syntaxe exacte Json::Object/Json::Write/Json::Parse
//
// CORRIGE (2026-09-04, premier essai réel de Thomas) :
//   5/6. info.toml utilisait des clés à plat - la dépendance MLFeed n'était donc
//        jamais réellement câblée ("No matching symbol 'MLFeed::GetRaceData_V4'"
//        alors que MLFeed était bien installé). Confirmé contre la doc officielle
//        OpenPlanet (docs/reference/info-toml, docs/tutorials/plugin-dependencies) :
//        le schéma exige des tables [meta]/[script], "dependencies" vit sous
//        [script], "version" doit être une chaîne. info.toml corrigé en
//        consequence.
//   - Le ternaire `cond ? cast<Handle>(...) : null` ne compilait pas dans
//     LocalName() ("Can't find unambiguous implicit conversion") - AngelScript
//     ne sait pas unifier un handle caste et le littéral null dans un ternaire.
//     Réécrit en if/else, même patron que LocalAccountId() ci-dessous (qui,
//     lui, compilait déjà).

string LocalAccountId() {
  auto net = GetApp().Network;
  if (net is null) return "";
  auto pg = cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground);
  if (pg is null || pg.LocalUser is null) return "";
  return pg.LocalUser.WebServicesUserId;
}

string LocalName() {
  auto net = GetApp().Network;
  if (net is null) return "";
  auto pg = cast<CGameManiaAppPlaygroundCommon>(net.ClientManiaAppPlayground);
  if (pg is null || pg.LocalUser is null) return "";
  return pg.LocalUser.Name;
}

string CurrentMapUid() {
  auto app = GetApp();
  return (app.RootMap !is null && app.RootMap.MapInfo !is null) ? app.RootMap.MapInfo.MapUid : "";
}

string g_status = "Inactif.";

// Retire un antislash final de l'adresse collee par le joueur : sans ca, une URL collee
// avec un "/" en trop (copier-coller depuis un navigateur, par ex.) produit un double
// slash qui ne correspond plus a la route exacte du serveur. SubStr : API AngelScript
// non verifiee ici (incertitude non listee en tete de fichier, mais du meme ordre).
string ServerUrlTrimmed() {
  string u = Setting_ServerUrl;
  if (u.Length > 0 && u.SubStr(u.Length - 1, 1) == "/") return u.SubStr(0, u.Length - 1);
  return u;
}

void TryPair() {
  if (Setting_Token != "" || Setting_ServerUrl == "" || Setting_PairCode == "") return;
  string accId = LocalAccountId();
  if (accId == "") { g_status = "Identite introuvable - relance une carte."; return; }

  Json::Value req = Json::Object();
  req["code"] = Setting_PairCode;
  req["accountId"] = accId;
  req["name"] = LocalName();

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/pair", Json::Write(req), "application/json");
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

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ingest", Json::Write(req), "application/json");
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
