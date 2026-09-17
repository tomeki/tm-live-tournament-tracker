// Persistent plugin settings. OpenPlanet keeps them across sessions and
// renders the settings panel itself - no UI code needed here.

[Setting category="Compte" name="Adresse du serveur"]
string Setting_ServerUrl = "https://genesis-tournament.tbrissonnet.ovh";

[Setting category="Compte" name="Code d'appairage" onchange="OnPairCodeChanged"]
string Setting_PairCode = "";

// Hidden: this is a secret token, never shown to the user, logged, or echoed
// back by the server outside of the pairing response itself.
[Setting hidden]
string Setting_Token = "";

// Fires only on a real edit through the OpenPlanet settings UI, not on the
// script's own resets after a successful pair - so pairing is requested
// exactly once per pasted code.
void OnPairCodeChanged() {
  RequestPairing();
}
