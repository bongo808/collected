# BikeTracker

App iPhone qui détecte automatiquement vos trajets à vélo, les enregistre en
arrière-plan et les exporte vers Strava sans intervention manuelle.

## Fonctionnalités

- **Détection automatique** du début et de la fin d'un trajet à vélo via
  `CMMotionActivityManager` (capteur de mouvement / classifieur d'activité
  d'iOS).
- **Enregistrement GPS en arrière-plan** avec `CoreLocation`
  (`startMonitoringSignificantLocationChanges` pour réveiller l'app, puis
  `startUpdatingLocation` haute précision pendant la sortie).
- **Statistiques** : distance, durée, vitesse moyenne, dénivelé positif,
  carte du parcours.
- **Export GPX** local (partage iOS standard).
- **Upload automatique vers Strava** via OAuth 2.0 + endpoint `/uploads` de
  l'API Strava v3.
- **Démarrage / arrêt manuel** également possible si vous préférez.

## Architecture

```
BikeTracker/
├── BikeTrackerApp.swift          # point d'entrée SwiftUI
├── Models/
│   ├── Ride.swift                # modèle de sortie + RidePoint
│   └── RideStore.swift           # persistance JSON dans Documents/
├── Services/
│   ├── LocationTracker.swift     # CoreLocation (WhenInUse → Always)
│   ├── ActivityDetector.swift    # CMMotionActivityManager (cyclisme)
│   ├── RideRecorder.swift        # state machine idle ↔ recording
│   ├── GPXExporter.swift         # génération GPX 1.1
│   └── StravaUploader.swift      # OAuth + multipart upload + polling
├── Views/
│   ├── ContentView.swift         # TabView principale
│   ├── LiveView.swift            # statut + bouton start/stop
│   ├── RideListView.swift        # historique
│   ├── RideDetailView.swift      # carte + stats + upload manuel
│   └── SettingsView.swift        # auto-détection, compte Strava
└── Resources/
    └── Info.plist                # permissions + URL scheme
```

### State machine de l'enregistreur

```
   ┌─ activité = cycling ───────────┐
   │                                ▼
[idle] ─ Démarrer manuellement ─► [recording]
   ▲                                │
   │     pas de cyclisme depuis     │
   └────  5 min, ou Stop manuel ────┘
              │
              ▼
   sauvegarde JSON + upload Strava (si auto-upload)
```

## Configuration

### 1. Créer une app Xcode

Cette source est livrée sans `.xcodeproj` (un projet Xcode est généré
automatiquement par Xcode). Pour la compiler:

1. Ouvrez Xcode → **File → New → Project → iOS → App**.
2. Nom: `BikeTracker`, interface: **SwiftUI**, langage: **Swift**.
3. Supprimez le `ContentView.swift` et l'`App.swift` créés par défaut.
4. Glissez le contenu de `BikeTracker/` dans le projet (cocher "Copy items if
   needed").
5. Remplacez le `Info.plist` généré par celui fourni dans `Resources/` (ou
   recopiez les clés).
6. Dans **Signing & Capabilities**, ajoutez la capability
   **Background Modes** et cochez **Location updates**.
7. Cible minimum: **iOS 17.0**.

### 2. Créer une app Strava

1. Allez sur https://www.strava.com/settings/api
2. Créez une application ; renseignez:
   - **Authorization Callback Domain**: `strava` (correspond au *host* du
     redirect URI `biketracker://strava/callback`). Si Strava refuse cette
     valeur, utilisez `localhost` et changez `redirectURI` dans
     `StravaUploader.swift` en `biketracker://localhost/callback`.
3. Récupérez `Client ID` et `Client Secret`.
4. Dans `BikeTracker/Resources/Info.plist`, remplacez:
   ```xml
   <key>StravaClientID</key>
   <string>VOTRE_CLIENT_ID</string>
   <key>StravaClientSecret</key>
   <string>VOTRE_CLIENT_SECRET</string>
   ```

> **Note**: stocker le `client_secret` côté client n'est pas idéal pour une
> app de production. Pour une publication App Store, déplacez l'échange
> `code → token` derrière un petit serveur que vous contrôlez. Pour un usage
> personnel, c'est suffisant.

### 3. Permissions iOS

À la première utilisation, l'app demande:

1. **Localisation pendant l'utilisation** → puis **Toujours** (nécessaire
   pour l'auto-démarrage).
2. **Mouvement et forme** (CoreMotion) pour la détection de cyclisme.

## Flux d'utilisation

### Mode automatique (recommandé)

1. Vous montez sur le vélo et commencez à pédaler.
2. iOS détecte l'activité `cycling` au bout de 30–60 s.
3. BikeTracker passe en `recording` et active le GPS haute précision.
4. Vous roulez. L'app reste active en arrière-plan grâce au
   *background mode* "location updates".
5. Vous arrivez. Au bout de 5 min sans détection de cyclisme, l'app
   considère la sortie terminée.
6. Le trajet est sauvegardé puis envoyé à Strava (si vous êtes connecté et
   que l'auto-upload est activé).

### Mode manuel

Onglet **En cours → Démarrer une sortie**, puis **Terminer la sortie**.

## Limitations connues

- L'auto-détection prend ~30–60 s au démarrage et peut manquer les très
  courts trajets (< 1 min, < 200 m sont ignorés).
- iOS suspend les apps en arrière-plan : le scheduler système peut
  retarder/relancer la détection. Le *significant location change* sert de
  filet de sécurité pour réveiller l'app.
- Strava traite les uploads de façon asynchrone : l'`activity_id` peut
  prendre 5–30 s à apparaître, l'app fait du polling pendant 30 s puis
  s'arrête (l'upload reste valide côté Strava).
- Le `client_secret` est embarqué côté app (cf. note ci-dessus).

## Test sans iPhone

Le simulateur iOS ne peut pas générer d'événements `CMMotionActivity` ; il
faut un appareil réel pour tester l'auto-détection. Le simulateur peut
néanmoins simuler la localisation (Debug → Location → City Bicycle Ride),
ce qui permet de tester l'enregistrement GPS en mode manuel.

## Licence

Code fourni à titre d'exemple, à adapter à vos besoins.
