// Réglages persistants du plugin (OpenPlanet les garde entre les sessions et
// affiche automatiquement un panneau dans son overlay - aucune UI à coder).
// Spec : docs/superpowers/specs/2026-09-04-trackmania-plugin-aide-design.md §3.3

[Setting category="Compte" name="Adresse du serveur"]
string Setting_ServerUrl = "https://genesis-tournament.tbrissonnet.ovh";

[Setting category="Compte" name="Code d'appairage"]
string Setting_PairCode = "";

// Jamais affiché : le token est un secret (sous-projet A, spec §3.1). Il n'est
// JAMAIS montré à l'utilisateur, ni loggué, ni renvoyé par le serveur ailleurs
// que dans la réponse de pairing elle-même.
[Setting hidden]
string Setting_Token = "";
