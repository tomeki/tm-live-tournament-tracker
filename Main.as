// Genesis Trackmania - pousse le meilleur temps Contre-la-montre vers l'app.
// Spec : docs/superpowers/specs/2026-09-04-trackmania-plugin-aide-design.md §3.4-3.5
//
// INCERTITUDES (§3.5, non testables ici - à vérifier au premier essai réel) :
//   1. nom exact de la méthode MLFeed pour le joueur local
//   3. LocalUser.WebServicesUserId peut être vide en solo local pur
//   4. syntaxe exacte Json::Object/Json::Write/Json::Parse
//
// INCERTITUDES (2026-09-05, sous-chantier 2 - "checkpoints + respawns", écrites
// en pleine nuit sans Thomas disponible pour tester, non confirmées) :
//   a. Json::Array()/.Add()/.Length/opIndex : confirmés contre la doc officielle
//      openplanet.dev/docs/api/Json/Value (pas juste supposés), mais jamais
//      exercés en conditions réelles ici.
//   b. me.NbRespawnsRequested et me.CpTimes : noms de champs confirmés contre la
//      doc MLFeed officielle, mais valeur/comportement réel non vérifié (même
//      prudence que BestTime avant le 3e essai réel - un nom de champ correct ne
//      garantit pas la sémantique attendue).
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
//
// CORRIGE (2026-09-05, 5e essai réel - "Identité introuvable" hors course) :
// LocalAccountId()/LocalName() lisaient Network.ClientManiaAppPlayground.LocalUser,
// documenté (spike §9) comme null hors playground (menu, chargement) - or
// l'appairage n'a rien à voir avec le fait d'être en course. Remplacé par
// GetApp().LocalPlayerInfo (CGameCtnApp, la classe de base, confirmé contre la
// doc officielle next.openplanet.dev/Game/CGameCtnApp) - NON TESTÉ EN JEU, à
// confirmer par Thomas (aucun harnais AngelScript ici).
//
// CORRIGE (2026-09-05, 6e essai réel - échec de compilation) : LocalPlayerInfo
// est un `const CGamePlayerInfo@` (confirmé contre la doc), pas un `CGamePlayerInfo@`
// simple - assigner une valeur const à une variable `auto` inférée non-const
// ("Can't implicitly convert from 'CGamePlayerInfo@&' to 'CGamePlayerInfo&'")
// ne compile pas. LocalPlayerInfoPlayground() déclarée en retour `const`, comme
// les deux sources qu'elle unifie.
//
// CORRIGE (2026-09-05, 7e essai réel - échec de compilation) : le correctif
// ci-dessus a inversé l'erreur ("Can't implicitly convert from 'CGamePlayerInfo@&'
// to 'const CGamePlayerInfo&'" sur la RÉASSIGNATION `info = GetApp().LocalPlayerInfo`)
// - la const-ness réelle de chaque source, contradictoire d'un essai à l'autre,
// n'est pas fiable à deviner depuis la doc en ligne. Plus aucune réassignation
// entre les deux sources : chaque variable est affectée UNE SEULE fois depuis
// UNE SEULE source (voir LocalAccountId/LocalName plus bas).

// LocalPlayerInfo vit sur CGameCtnApp (la classe de base que GetApp() renvoie),
// PAS sous Network.ClientManiaAppPlayground - qui, lui, est documente (spike
// openplanet-spike-dossier.md §9) comme null hors playground (menu, chargement,
// ecran de fin). L'appairage n'a rien a voir avec le fait d'etre en course : il
// ne devrait pas dependre de cette restriction (retour Thomas, 2026-09-05 :
// "Identite introuvable" tant qu'aucune carte n'etait chargee).
//
// Priorite au chemin Playground quand il existe : c'est celui deja PROUVE correct
// par tous les appairages reussis precedents (en course). LocalPlayerInfo
// (CGameCtnApp, confirme contre la doc officielle next.openplanet.dev/Game/
// CGameCtnApp) sert de repli SEULEMENT hors playground - non teste en jeu par
// manque de harnais AngelScript. Si "Appairage refuse (400)" persiste en menu,
// le corps de la reponse (TryPair) dira si WebServicesUserId n'est pas un GUID
// valide dans ce contexte.
// Pas de fonction partagee qui renvoie CGamePlayerInfo@ : nommer explicitement ce
// type de retour est precisement ce qui a fait echouer les 2 essais precedents
// (constness de CGamePlayerInfo contradictoire d'un essai reel a l'autre, methode
// get_WebServicesUserId()/get_Name() elle-meme non-const malgre un retour const -
// AngelScript refuse de l'appeler sur une reference const, cf. changelog ci-dessus).
// Chaque chemin reste une suite d'expressions `auto` + acces direct, exactement le
// style de l'ancien code deja PROUVE correct (tous les appairages reussis en
// course) - jamais besoin de nommer le type, jamais de reassignation entre les
// deux sources.
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

string g_status = "Inactif.";
string g_lastPairCodeTried = "";
int g_pairAttempts = 0;
bool g_pairStartupSeen = false;

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
  // Un code colle est un ordre EXPLICITE de (re)appairer - ne jamais l'ignorer sous
  // pretexte qu'un token local existe deja : ce token peut etre perime cote serveur
  // (bac reinitialise, compte delie...) sans que le plugin ne le sache avant d'avoir
  // fini une course (le seul chemin qui decouvre un 401). Sans ce correctif, coller
  // un nouveau code ne faisait rigoureusement rien tant qu'aucune course n'etait
  // terminee (retour Thomas, 2026-09-05 : "Verifier" muet + widget bloque "Inactif").
  // Reappairer avec un token deja valide est sans risque : le serveur en emet juste
  // un nouveau (server/trackmania.js, /pair).
  // Photo de demarrage (2026-09-05, retour Thomas : "Code inconnu ou expire" au
  // relancement, avec le DERNIER code ayant deja reussi) : OpenPlanet n'ecrit sur
  // disque que les [Setting] non-defaut (doc officielle) - Setting_PairCode="" (son
  // defaut, pose apres un appairage reussi) risque de ne jamais ecraser l'ancienne
  // valeur non-vide deja sur le disque, qui revient donc au relancement suivant.
  // Peu importe la cause exacte cote disque : la valeur presente au tout premier
  // appel de TryPair() est traitee comme "deja tentee" d'office, silencieusement -
  // seul un code QUI CHANGE APRES coup (colle en jeu) est un ordre explicite reel.
  // BUG (2026-09-05) : la photo seule ne suffisait pas - g_pairAttempts demarrait a 0,
  // donc la garde "else if (g_pairAttempts>0) return" plus bas ne se declenchait PAS
  // au tout premier appel (0>0 est faux), laissant passer une tentative reelle malgre
  // tout. g_pairAttempts=1 pose ICI directement (confirme par Thomas : le meme
  // "Code inconnu ou expire" persistait malgre la photo).
  if (!g_pairStartupSeen) { g_pairStartupSeen = true; g_lastPairCodeTried = Setting_PairCode; g_pairAttempts = 1; }
  if (Setting_ServerUrl == "" || Setting_PairCode == "") return;
  string accId = LocalAccountId();
  if (accId == "") { g_status = "Identite introuvable - patiente ou relance Trackmania."; return; }

  // Compteur + GARDE "un seul essai par code" (2026-09-05, confirme par Thomas :
  // "tentative #9 et ca continue de monter" sur un code deja mort - la boucle a 1Hz
  // retentait indefiniment le MEME code, echouant a chaque fois puisque deja
  // consomme/invalide - jamais de nouvelle valeur pour s'arreter tout seul). Un code
  // n'est tente qu'UNE fois ; un nouveau code colle (valeur differente) redevient
  // tentable normalement. La cause du tout premier echec (parfois ca marche du 1er
  // coup, parfois pas - intermittent, cf. changelog) reste a elucider, mais spammer
  // le serveur indefiniment avec un code deja mort n'a de toute facon aucun interet.
  if (Setting_PairCode != g_lastPairCodeTried) { g_lastPairCodeTried = Setting_PairCode; g_pairAttempts = 0; }
  else if (g_pairAttempts > 0) return;
  g_pairAttempts++;
  int thisAttempt = g_pairAttempts;

  Json::Value req = Json::Object();
  req["code"] = Setting_PairCode;
  req["accountId"] = accId;
  req["name"] = LocalName();

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/pair", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  // Diagnostic (2026-09-05, retour Thomas : "Appairage refuse (400)" purement en menu,
  // juste apres le passage a GetApp().LocalPlayerInfo pour lire l'identite hors course) :
  // le serveur distingue 3 causes de 400 (AccountId invalide / Code inconnu ou expire /
  // Compte introuvable, server/trackmania.js /pair) - le corps de la reponse dit
  // laquelle, plutot que de deviner. accId affiche aussi : verifie que c'est bien un
  // GUID complet (8-4-4-4-12 caracteres hexa), pas une valeur vide/tronquee/differente
  // de celle lue via l'ancien chemin (Network.ClientManiaAppPlayground.LocalUser).
  if (r.ResponseCode() != 200) { g_status = "Appairage refuse (" + r.ResponseCode() + ") tentative #" + thisAttempt + " " + r.String() + " | accId=" + accId; return; }
  Json::Value resp = Json::Parse(r.String());
  Setting_Token = string(resp["token"]);
  Setting_PairCode = "";
  // Meta::SaveSettings() (2026-09-05, retour Thomas : "j'aimerais qu'a l'avenir
  // l'appairage persiste") : OpenPlanet n'ecrit les [Setting] sur disque qu'a des
  // moments precis (fermeture du panneau reglages, rechargement du plugin) - PAS
  // a chaque affectation depuis le script (doc officielle, tutoriel "Plugin
  // settings"). Sans cet appel explicite, fermer completement le jeu SANS passer
  // par un de ces declencheurs perdait le token fraichement obtenu ET le code
  // efface, revenant a un ancien code perime sauvegarde bien plus tot -
  // exactement le symptome observe ("Code inconnu ou expire" au relancement,
  // alors qu'aucun nouvel appairage n'avait ete demande).
  Meta::SaveSettings();
  g_status = "Appaire (tentative #" + thisAttempt + ").";
}

// Detection de ligne d'arrivee par piste : g_cpArmed ne passe a true qu'apres avoir
// VU le joueur sous le seuil de fin (CpCount < CPsToFinish) au moins une fois sur
// cette piste - sans ca, un plugin qui reprend la main alors que CpCount est deja
// au max (joueur deja arrive avant que le plugin ne regarde) declencherait un faux
// "juste fini". Remis a zero a chaque nouvelle piste (CurrentMapUid change).
string g_cpMapUid = "";
bool g_cpArmed = false;
int g_lastCpCount = -1;
// Vrai des qu'un spawn reel a ete vu sur la carte courante (cf. TryIngest, garde
// IsSpawned) - remis a false a chaque changement de carte.
bool g_everSpawnedThisMap = false;

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

// Progression en direct (2026-09-05, demande Thomas) : ping best-effort et
// silencieux (comme TryAmbient/SendAttemptStarted, jamais g_status). CurrentRaceTime
// (chrono VIVANT) est correct PENDANT la course, mais continue de tourner apres la
// ligne d'arrivee (doc MLFeed) - une fois cp>=toFinish il faut figer sur LastCpTime,
// sinon la barre en direct continue de defiler apres l'arrivee tant que la run n'est
// pas relancee (retour Thomas 2026-09-05). Choix fait par l'appelant (TryIngest).
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

  // Pas encore reellement sur la piste (ex: menu "seul/avec fantomes" juste apres avoir
  // charge la carte) : CpCount et CurrentRaceTime peuvent deja bouger avant le spawn reel
  // - confirme par Thomas (chrono qui defile, statut "En course" alors qu'aucune tentative
  // n'a commence). Doc officielle MLFeed : IsSpawned distingue precisement ce cas (spawn
  // status NotSpawned/Spawning/Spawned).
  if (me.IsSpawned) g_everSpawnedThisMap = true;
  // Le MEME menu "seul/avec fantomes" reapparait ENTRE deux tentatives (retour Thomas :
  // le suivi live disparaissait a tort apres une run si on restait dessus) - IsSpawned y
  // redevient faux la aussi. Ne bloquer que tant qu'AUCUN spawn reel n'a encore eu lieu
  // sur cette carte (1er chargement) : une fois qu'on a vraiment couru, le suivi (fige au
  // temps d'arrivee par ailleurs) doit rester visible meme si IsSpawned reflue en attendant
  // la tentative suivante. Sortir tot, AVANT de toucher g_lastCpCount, pour que la vraie
  // transition "juste demarre" soit detectee au reel spawn, pas au chargement.
  if (!me.IsSpawned && !g_everSpawnedThisMap) return;

  int cp = me.CpCount;
  int toFinish = int(raceData.CPsToFinish);
  // course en cours OU juste finie (retour Thomas 2026-09-05 : la barre n'affichait
  // jamais 100% - <= au lieu de < continue de pinguer une fois l'arrivee franchie,
  // tant que le joueur reste sur l'ecran de fin sans relancer. cp retombe a 0 des
  // qu'une nouvelle tentative demarre, qui reprend alors le ping normalement.
  // Le rate-limit serveur (~1.5s, PROGRESS_MIN_GAP_MS) absorbe le fait que Main()
  // tourne a 1Hz, plus vite que la cadence voulue.
  int liveMs = (cp < toFinish) ? me.CurrentRaceTime : me.LastCpTime;
  if (cp <= toFinish && liveMs > 0) SendProgress(cp, toFinish, liveMs);
  bool justFinished = g_cpArmed && g_lastCpCount < toFinish && cp >= toFinish;
  // "nouvelle tentative" (compteur de runs, 2026-09-05) : CpCount retombe a 0 -
  // couvre a la fois un redemarrage complet ET le tout premier passage a 0 juste
  // apres un changement de piste (g_lastCpCount initialise a -1 ci-dessus).
  // Approximatif par nature : compte aussi une "tentative" si le joueur spawn sur la
  // piste sans jamais rouler - assume, signale a Thomas des la conception (aucun signal
  // MLFeed "abandon" n'existe). Le garde IsSpawned ci-dessus evite au moins de compter
  // une tentative rien qu'en chargeant la carte (menu solo/fantomes avant le spawn).
  bool justStarted = (cp == 0 && g_lastCpCount != 0);
  if (cp < toFinish) g_cpArmed = true;
  g_lastCpCount = cp;
  if (justStarted) SendAttemptStarted();
  if (!justFinished) return;

  // CORRIGE (2026-09-05, 8e essai reel - temps envoye systematiquement trop grand,
  // ecart variable < 1s) : l'hypothese "CurrentRaceTime se fige a la ligne" etait
  // fausse. Doc officielle MLFeed (XertroV/tm-mlfeed-race-data, MLFeed.autodoc.md) :
  // CurrentRaceTime = "with latency taken into account" (chrono VIVANT, continue de
  // tourner) ; LastCpTime = "player's last CP time as on their chronometer" (temps
  // FIGE au dernier CP passe - a l'instant precis ou CpCount atteint CPsToFinish,
  // c'est donc exactement le temps de cette run, contrairement a CurrentRaceTime lu
  // jusqu'a 1s plus tard par le polling a 1 Hz de TryIngest).
  int raceMs = me.LastCpTime;
  // Ce cas ne devrait pas arriver (le chrono est cense etre fige a l'arrivee) - mais un
  // retour muet ici laissait le widget afficher le dernier "Envoye : Xs" reussi, l'air
  // de dire que CE run venait d'etre envoye alors qu'il avait ete silencieusement ignore
  // (retour Thomas, 2026-09-05 : record battu apres une pause, jamais transmis). Statut
  // explicite le temps qu'on comprenne si/quand ce cas se produit vraiment.
  if (raceMs <= 0) { g_status = "Run ignore (temps invalide) - non envoye."; return; }

  Json::Value req = Json::Object();
  req["token"] = Setting_Token;
  req["mapUid"] = mapUid;
  req["mapName"] = CurrentMapName();
  req["timeMs"] = raceMs;
  // respawns + temps aux checkpoints de CETTE run (celle qui vient de finir) -
  // champs optionnels cote serveur, ignores silencieusement si absents ou mal
  // formes (compat avec un serveur plus ancien). CpTimes : array<int>@ AngelScript
  // standard (Length/opIndex), pas du Json - converti en Json::Array() ici.
  req["respawns"] = int(me.NbRespawnsRequested);
  Json::Value cps = Json::Array();
  auto cpArr = me.CpTimes;
  if (cpArr !is null) {
    for (uint i = 0; i < cpArr.Length; i++) cps.Add(cpArr[i]);
  }
  req["cpTimes"] = cps;

  auto r = Net::HttpPost(ServerUrlTrimmed() + "/api/trackmania/ingest", Json::Write(req), "application/json");
  while (!r.Finished()) yield();

  if (r.ResponseCode() == 200) { g_status = "Envoye : " + (raceMs / 1000.0) + "s"; }
  else if (r.ResponseCode() == 401) { Setting_Token = ""; Meta::SaveSettings(); g_status = "Lien expire - re-appaire."; }
  else {
    // Messages explicites (2026-09-05, retour Thomas : "Erreur (409)" generique qui
    // revient sans arret n'est pas rassurant, meme quand c'est parfaitement normal -
    // quota de runs ou minuteur ecoule, server/trackmania.js ctmAttemptsExhausted/
    // ctmRunRejectedByTimer). Distingue le cas attendu d'une vraie erreur.
    string reason = "";
    Json::Value errBody = Json::Parse(r.String());
    if (errBody !is null) reason = string(errBody["error"]);
    if (reason == "attempts") g_status = "Quota de runs atteint - normal, ton meilleur temps est deja enregistre.";
    else if (reason == "time_up") g_status = "Minuteur ecoule avant ce run - normal, il ne compte pas.";
    else if (reason == "map") g_status = "Piste differente de celle verrouillee pour cette manche.";
    else { g_status = "Erreur (" + r.ResponseCode() + ") " + r.String(); }
  }
}

// Signal indicatif ("niveau" du joueur sur la piste courante) - piste + record
// deja existant (BestTime), independant de tout salon actif et jamais ecrit comme
// temps officiel. Rate-limite cote plugin (~10s, boucle Main() a 1 Hz, demande
// Thomas 2026-09-05 - reduit de 20s) - un filet cote serveur existe aussi
// (AMBIENT_MIN_GAP_MS=5s, server/trackmania.js, marge de 2x conservee).
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
  // ReadOnly (2026-09-05, demande Thomas) : champ selectionnable/copiable (clic
  // dedans, Ctrl+A puis Ctrl+C) plutot que du texte simple - evite de retaper les
  // messages d'erreur a la main pour me les transmettre.
  UI::InputText("##status", g_status, UI::InputTextFlags::ReadOnly);
  UI::End();
}
