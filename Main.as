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
//
// CORRIGE (2026-09-05, 3e essai réel - temps aberrant "PR toutes parties
// confondues" envoyé avant même de démarrer une run) :
//   me.BestTime n'est PAS le temps de la manche en cours : c'est le record
//   personnel déjà existant sur cette piste, réaffiché par le jeu dès le
//   chargement (avant toute run de la session), y compris après un rechargement
//   de piste entre deux salons. TryIngest() ne mesurait donc jamais "le temps que
//   je viens de faire", juste "mon record historique sur cette piste". Remplacé
//   par une vraie détection de ligne d'arrivée : CpCount (nombre de points de
//   passage validés) atteint CPsToFinish (nombre total requis pour finir, doc
//   MLFeed) - à cette transition précise, CurrentRaceTime est le temps réel de
//   CETTE run. Non testable ici (aucun harnais AngelScript) - à confirmer par
//   Thomas au prochain essai réel.
//
// AJOUT (2026-09-05, "niveau indicatif" au roster) : me.BestTime, le champ
// écarté ci-dessus pour l'envoi OFFICIEL, est exactement le bon champ pour un
// indicatif de niveau (c'est bien un record historique qu'on veut ici). Envoyé
// par TryAmbient(), route et donnée séparées de TryIngest() - jamais mélangé au
// temps officiel d'une manche.
//
// CORRIGE (2026-09-05, 4e essai réel - échec de compilation) : même famille
// d'erreur que le ternaire déjà corrigé plus haut ("Can't find unambiguous
// implicit conversion") - CurrentMapName() (ajoutée pour "niveau indicatif")
// utilisait un ternaire `cond ? MapInfo.Name : ""`, qui ne compile pas même
// entre deux string. CurrentMapUid(), même patron, réécrite en if/else par
// précaution (elle compilait jusque-là, mais rien ne garantit qu'elle
// continuerait après ce correctif).

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
  if (app.RootMap is null || app.RootMap.MapInfo is null) return "";
  return app.RootMap.MapInfo.MapUid;
}

string CurrentMapName() {
  auto app = GetApp();
  if (app.RootMap is null || app.RootMap.MapInfo is null) return "";
  return app.RootMap.MapInfo.Name;
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

// Detection de ligne d'arrivee par piste : g_cpArmed ne passe a true qu'apres avoir
// VU le joueur sous le seuil de fin (CpCount < CPsToFinish) au moins une fois sur
// cette piste - sans ca, un plugin qui reprend la main alors que CpCount est deja
// au max (joueur deja arrive avant que le plugin ne regarde) declencherait un faux
// "juste fini". Remis a zero a chaque nouvelle piste (CurrentMapUid change).
string g_cpMapUid = "";
bool g_cpArmed = false;
int g_lastCpCount = -1;

// Signale "une nouvelle tentative vient de commencer" au salon CTM actif (compteur
// de runs, cote serveur - cf. server/trackmania.js route /attempt). Best-effort et
// silencieux, comme TryAmbient() : ne touche jamais g_status.
void SendAttemptStarted() {
  if (Setting_Token == "") return;
  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/attempt", Json::Write(req), "application/json");
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
  if (mapUid != g_cpMapUid) { g_cpMapUid = mapUid; g_cpArmed = false; g_lastCpCount = -1; }

  int cp = me.CpCount;
  int toFinish = int(raceData.CPsToFinish);
  bool justFinished = g_cpArmed && g_lastCpCount < toFinish && cp >= toFinish;
  // "nouvelle tentative" (compteur de runs, 2026-09-05) : CpCount retombe a 0 -
  // couvre a la fois un redemarrage complet ET le tout premier passage a 0 juste
  // apres un changement de piste (g_lastCpCount initialise a -1 ci-dessus).
  // Approximatif par nature : compte aussi une "tentative" si le joueur charge la
  // piste sans jamais rouler - assume, signale a Thomas des la conception (aucun
  // signal MLFeed "abandon" n'existe).
  bool justStarted = (cp == 0 && g_lastCpCount != 0);
  if (cp < toFinish) g_cpArmed = true;
  g_lastCpCount = cp;
  if (justStarted) SendAttemptStarted();
  if (!justFinished) return;

  // CurrentRaceTime : le chrono de course s'arrete au franchissement de la ligne
  // (mecanique standard Trackmania) - la valeur lue ici, meme une seconde plus
  // tard (boucle de TryIngest a 1 Hz), reste celle de cette run precise.
  int raceMs = me.CurrentRaceTime;
  if (raceMs <= 0) return;

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["timeMs"] = raceMs;

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ingest", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() == 200) { g_status = "Envoye : " + (raceMs / 1000.0) + "s"; }
  else if (r.ResponseCode() == 401) { Setting_Token = ""; g_status = "Lien expire - re-appaire."; }
  else { g_status = "Erreur (" + r.ResponseCode() + ")"; }
}

// Signal indicatif ("niveau" du joueur sur la piste courante) - piste + record
// deja existant (BestTime), independant de tout salon actif et jamais ecrit comme
// temps officiel. Rate-limite cote plugin (~20s, boucle Main() a 1 Hz) - un filet
// cote serveur existe aussi (AMBIENT_MIN_GAP_MS, server/trackmania.js).
int g_ambientTicks = 0;
const int AMBIENT_EVERY_TICKS = 20;

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
  // best-effort et silencieux : ne touche jamais g_status, reserve au flux
  // officiel (TryIngest) pour ne pas noyer un vrai "Envoye"/"Erreur".
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
  if (UI::MenuItem("Genesis Trackmania", "", g_windowOpen)) g_windowOpen = !g_windowOpen;
}

void Render() {
  if (!g_windowOpen) return;
  UI::Begin("Genesis Trackmania", g_windowOpen);
  UI::Text(g_status);
  UI::End();
}
