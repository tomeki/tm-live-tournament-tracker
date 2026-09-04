// Genesis Trackmania - pousse le meilleur temps Contre-la-montre vers l'app.
// Spec : docs/superpowers/specs/2026-09-04-trackmania-plugin-aide-design.md §3.4-3.5
//
// INCERTITUDES (§3.5, non testables ici - à vérifier au premier essai réel) :
//   1. nom exact de la méthode MLFeed pour le joueur local
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
//
// CORRIGE (2026-09-04, 2e essai réel - appairage OK, ingest silencieux) :
//   2. me.BestTime est bien la bonne propriété (confirmé contre la doc officielle
//      MLFeed, github.com/XertroV/tm-mlfeed-race-data/MLFeed.autodoc.md), mais
//      c'est un `int` DEJA en millisecondes ("this player's best time this
//      session") - le code multipliait par 1000 en pensant convertir des
//      secondes, d'où un temps envoyé 1000x trop grand ("Envoye : 18164s" pour
//      un temps réel de 18.164s). TryIngest() corrigé pour traiter BestTime
//      comme des ms directement.
//   - g_lastSentTime (garde "valeur inchangée") ne se réinitialisait jamais
//      entre deux salons : un redémarrage de manche sur la même piste avec un
//      temps identique ou non amélioré ne renvoyait plus jamais rien, sans le
//      moindre changement de g_status pour le signaler. Garde retirée : le
//      serveur fait déjà le tri (n'écrit que si le temps améliore la cellule).

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

// Pas de garde "valeur inchangee" ici : BestTime tient depuis le chargement de la
// carte, un simple redemarrage de manche (meme piste, nouveau salon) peut renvoyer
// la meme valeur - une garde en memoire bloquait alors tout renvoi. Le serveur fait
// deja le tri (n'ecrit que si le temps ameliore la cellule), un POST/s inutile ne
// coute rien de plus qu'avant.
void TryIngest() {
  if (Setting_Token == "") return;
  auto raceData = MLFeed::GetRaceData_V4();
  if (raceData is null) return;

  auto me = raceData.GetPlayer_V4(LocalName());
  if (me is null) return;

  // BestTime est deja en millisecondes (doc MLFeed : "int BestTime") - PAS des
  // secondes. Le code precedent faisait `int(best * 1000.0)` en pensant convertir
  // des secondes en ms, ce qui multipliait par 1000 une valeur deja en ms (bug reel
  // trouve par Thomas : "Envoye : 18164s" au lieu de 18.164s).
  int bestMs = me.BestTime;
  if (bestMs <= 0) return;

  string mapUid = CurrentMapUid();
  if (mapUid == "") return;

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["timeMs"] = bestMs;

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ingest", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() == 200) { g_status = "Envoye : " + (bestMs / 1000.0) + "s"; }
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
