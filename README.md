# TP2 — Pipeline PokeAPI → n8n → PostgreSQL + MinIO

## Architecture

```
PokeAPI (REST) → n8n (ETL) → PostgreSQL (stockage structuré)
                            → MinIO (stockage objet / Data Lake)
```

Tout tourne en local via Docker Compose.

---

# TP2 — Data Warehouse

## Partie A — Lancement de l'environnement

```bash
docker-compose up -d
```

- **PostgreSQL** : `localhost:5432` (user: `pokemon`, password: `pokemon`, db: `pokemon_db`)
- **n8n** : `http://localhost:5678`

Le fichier `init.sql` est exécuté automatiquement au premier démarrage de PostgreSQL.

---

## Partie B — Structure SQL

### Table `ingestion_runs`

| Colonne            | Type         | Description                        |
|--------------------|--------------|------------------------------------|
| run_id             | SERIAL PK    | Identifiant unique du run          |
| source             | VARCHAR(255) | Source des données (pokeapi)       |
| started_at         | TIMESTAMP    | Date de démarrage                  |
| finished_at        | TIMESTAMP    | Date de fin                        |
| status             | VARCHAR(50)  | running / success / error          |
| records_received   | INT          | Nombre d'enregistrements reçus     |
| records_inserted   | INT          | Nombre d'enregistrements insérés   |

### Table `pokemon`

| Colonne                  | Type         | Description                              |
|--------------------------|--------------|------------------------------------------|
| pokemon_id               | INT          | ID du Pokémon (PK avec run_id)           |
| pokemon_name             | VARCHAR(255) | Nom du Pokémon                           |
| base_experience          | INT          | Expérience de base                       |
| height                   | INT          | Taille                                   |
| weight                   | INT          | Poids                                    |
| main_type                | VARCHAR(100) | Type principal                           |
| has_official_artwork     | BOOLEAN      | Indicateur artwork officiel              |
| has_front_sprite         | BOOLEAN      | Indicateur sprite frontal                |
| source_last_updated_at   | TIMESTAMP    | Date de récupération depuis la source    |
| ingested_at              | TIMESTAMP    | Date d'insertion en base                 |
| run_id                   | INT FK       | Référence vers ingestion_runs            |

---

## Partie C — Description du workflow n8n

Le workflow est composé de **8 nœuds** exécutés séquentiellement :

1. **Start** (Manual Trigger) — Déclenchement manuel du pipeline.
2. **Create Run** (Postgres) — Insère une ligne dans `ingestion_runs` avec le statut `running` et récupère le `run_id`.
3. **Fetch Pokemon List** (HTTP Request) — Appelle `https://pokeapi.co/api/v2/pokemon?limit=150` pour obtenir la liste des 150 premiers Pokémon.
4. **Split URLs** (Code) — Extrait les URLs individuelles de chaque Pokémon depuis la réponse JSON.
5. **Fetch Pokemon Detail** (HTTP Request) — Appelle chaque URL pour récupérer les données détaillées de chaque Pokémon.
6. **Transform Data** (Code) — Transformations appliquées :
   - Renommage des champs (`name` → `pokemon_name`, `id` → `pokemon_id`)
   - Gestion des valeurs manquantes (`base_experience`, `height`, `weight` → `null` si absent ; `main_type` → `'unknown'` si absent)
   - Création d'indicateurs booléens (`has_official_artwork`, `has_front_sprite`)
   - Ajout des métadonnées (`ingested_at`, `run_id`, `source_last_updated_at`)
7. **Insert Pokemon** (Postgres) — Insère les enregistrements transformés dans la table `pokemon`.
8. **Update Run** (Postgres) — Met à jour `ingestion_runs` avec `finished_at`, `status = 'success'`, `records_received` et `records_inserted`.

### Import du workflow

1. Ouvrir n8n sur `http://localhost:5678`
2. Créer un nouveau workflow
3. Menu `...` → **Import from File** → sélectionner `n8n-workflow.json`
4. Configurer le credential PostgreSQL :
   - Host: `postgres` (nom du service Docker)
   - Port: `5432`
   - Database: `pokemon_db`
   - User: `pokemon`
   - Password: `pokemon`
5. Associer ce credential aux 3 nœuds Postgres (Create Run, Insert Pokemon, Update Run)
6. Exécuter le workflow

---

## Partie E — Requêtes de contrôle

Voir le fichier `queries.sql` :

1. Nombre total de Pokémon chargés
2. Nombre de Pokémon sans artwork officiel
3. Nombre de Pokémon sans sprite frontal
4. Répartition par type principal
5. Pokémon dont le nom est vide ou manquant

---

## Partie F — Justification Data Warehouse

Cette architecture relève d'une logique **Data Warehouse** pour les raisons suivantes :

- **Extraction depuis une source externe** : les données brutes proviennent d'une API REST (PokeAPI), ce qui correspond à la phase d'extraction d'un pipeline ETL classique.
- **Transformation structurée** : les données JSON sont nettoyées, renommées, enrichies d'indicateurs calculés et mises dans un format tabulaire normalisé — c'est la phase de transformation.
- **Chargement dans un entrepôt relationnel** : les données sont insérées dans PostgreSQL avec un schéma structuré, typé et contraint (clés primaires, clés étrangères) — c'est la phase de chargement.
- **Traçabilité des ingestions** : la table `ingestion_runs` permet de suivre chaque exécution du pipeline (date, statut, volumétrie), ce qui est une pratique standard dans un Data Warehouse pour l'audit et la qualité des données.
- **Données orientées analyse** : le schéma final est conçu pour être interrogé facilement (agrégations par type, comptages, filtres), ce qui correspond à l'objectif d'un entrepôt de données : fournir une couche de données fiable et exploitable pour l'analyse.

Il ne s'agit pas d'une base transactionnelle (OLTP) mais bien d'un stockage orienté lecture et analyse (OLAP), alimenté par un pipeline ETL reproductible.

---

## Livrables — Data Warehouse

| Livrable | Emplacement |
|---|---|
| Structure SQL des tables | `init.sql` (tables `ingestion_runs` et `pokemon`) |
| Description du workflow n8n | Ce README, Partie C + fichier `n8n-workflow.json` |
| Preuve de chargement dans PostgreSQL | 150 Pokémon insérés, vérifiable via `queries.sql` |
| Repo GitHub | Ce dépôt |
| 5 requêtes SQL de contrôle | `queries.sql` |
| Réponse rédigée (justification DW) | Ce README, Partie F |

---

# TP Data Lake

## Partie A — Stockage objet avec MinIO

MinIO est ajouté au `docker-compose.yml` et expose :

- **API S3** : `http://localhost:9000`
- **Console Web** : `http://localhost:9001` (login: `minioadmin` / `minioadmin`)

### Organisation des buckets

| Bucket           | Contenu                                      |
|------------------|----------------------------------------------|
| `raw-pokemon`    | Réponses JSON brutes de la PokeAPI           |
| `pokemon-images` | Images (sprites, artworks) des Pokémon       |
| `reports`        | Rapports CSV/JSON générés                    |

Les 3 buckets sont créés automatiquement au démarrage via le service `minio-init`.

---

## Partie B — Base enrichie

### Table `pokemon_files`

| Colonne     | Type         | Description                          |
|-------------|--------------|--------------------------------------|
| file_id     | SERIAL PK    | Identifiant unique du fichier        |
| pokemon_id  | INT          | ID du Pokémon associé                |
| bucket_name | VARCHAR(255) | Nom du bucket MinIO                  |
| object_key  | VARCHAR(512) | Chemin complet de l'objet            |
| file_name   | VARCHAR(255) | Nom du fichier                       |
| file_type   | VARCHAR(100) | Type de fichier (json, png, csv)     |
| file_size   | INT          | Taille en octets                     |
| mime_type   | VARCHAR(100) | Type MIME                            |
| created_at  | TIMESTAMP    | Date de création                     |

### Table `file_ingestion_log`

| Colonne      | Type         | Description                          |
|--------------|--------------|--------------------------------------|
| log_id       | SERIAL PK    | Identifiant unique du log            |
| file_name    | VARCHAR(255) | Nom du fichier                       |
| bucket_name  | VARCHAR(255) | Nom du bucket                        |
| object_key   | VARCHAR(512) | Chemin complet de l'objet            |
| source       | VARCHAR(255) | Source des données                   |
| status       | VARCHAR(50)  | Statut (success / error)             |
| file_size    | INT          | Taille en octets                     |
| mime_type    | VARCHAR(100) | Type MIME                            |
| processed_at | TIMESTAMP    | Date de traitement                   |

---

## Partie C — Workflow n8n Data Lake

Le workflow `n8n-workflow-datalake.json` est composé de **7 nœuds** :

1. **Start** — Déclenchement manuel.
2. **Get Pokemon List** (Postgres) — Récupère les 10 premiers Pokémon depuis la base.
3. **Fetch Raw JSON** (HTTP Request) — Appelle la PokeAPI pour chaque Pokémon.
4. **Prepare Files** (Code) — Prépare le nom de fichier, la clé objet, et le contenu JSON.
5. **Upload to MinIO** (HTTP Request) — Envoie le fichier JSON brut dans le bucket `raw-pokemon` via l'API S3 de MinIO.
6. **Build SQL** (Code) — Génère les requêtes INSERT pour `pokemon_files` et `file_ingestion_log`.
7. **Insert Metadata** (Postgres) — Exécute les INSERT en base.

### Import

1. Créer un nouveau workflow dans n8n
2. Importer `n8n-workflow-datalake.json`
3. Associer le credential PostgreSQL aux nœuds Postgres
4. Configurer le credential S3/HTTP pour MinIO si nécessaire
5. Exécuter le workflow

---

## Partie D — Justification Data Lake / Lakehouse

L'ajout de MinIO transforme l'architecture en une logique **Data Lake / Lakehouse**. MinIO apporte une couche de stockage objet compatible S3 qui permet de conserver les données brutes (JSON complets de la PokeAPI) dans leur format d'origine, sans transformation ni perte d'information. Contrairement à la base relationnelle qui ne stocke que les champs sélectionnés et transformés, le Data Lake conserve l'intégralité de la réponse API, ce qui permet de retraiter les données ultérieurement si de nouveaux besoins apparaissent. La base PostgreSQL ne contient pas les fichiers eux-mêmes mais uniquement leurs métadonnées (emplacement, taille, type, date), ce qui maintient la base légère et performante tout en gardant la traçabilité complète. Cette séparation entre stockage brut (MinIO) et stockage structuré (PostgreSQL) est le principe fondamental d'un Lakehouse : combiner la flexibilité d'un Data Lake avec la rigueur d'un Data Warehouse. L'architecture est donc plus riche qu'une simple base relationnelle car elle gère à la fois des données structurées, semi-structurées et des fichiers binaires dans un système cohérent et interrogeable.

---

## Livrables — Data Lake

| Livrable | Emplacement |
|---|---|
| Ajout de MinIO dans Docker | `docker-compose.yml` (services `minio` + `minio-init`) |
| Création des buckets | Automatique via `minio-init` (raw-pokemon, pokemon-images, reports) |
| Structure SQL ajoutée | `init.sql` (tables `pokemon_files` et `file_ingestion_log`) |
| Description du workflow n8n | Ce README, Partie C Data Lake + fichier `n8n-workflow-datalake.json` |
| Exemple d'objet stocké dans MinIO | Fichiers JSON bruts dans `raw-pokemon/raw/` (ex: `1_bulbasaur.json`) |
| Métadonnées en base | Tables `pokemon_files` et `file_ingestion_log` (capture : `datalake_preuve_metadonnees_base`) |
| Réponse rédigée (justification Data Lake) | Ce README, Partie D |

---

# TP3 — Restitution analytique et automatisation Telegram

## Partie A — Couche analytique

Cinq vues SQL ont été créées dans `analytics.sql` :

| Vue | Description |
|---|---|
| `v_pokemon_quality` | Qualité par Pokémon : complétude de chaque fiche (complet/incomplet), présence d'images et de fichiers associés |
| `v_type_distribution` | Répartition par type principal avec pourcentage |
| `v_files_summary` | Synthèse des fichiers stockés dans MinIO (nombre, taille totale, taille moyenne) |
| `v_kpi_global` | KPI globaux du référentiel en une seule ligne |
| `v_pokemon_incomplete` | Liste des Pokémon incomplets avec détail des champs manquants |

---

## Partie B — KPI retenus

| KPI | Description | Justification |
|---|---|---|
| Total Pokémon | Nombre total de Pokémon en base | Volume de référence du catalogue |
| Taux de fiches complètes | % de Pokémon ayant toutes les données renseignées | Indicateur principal de qualité du référentiel |
| Taux d'artwork officiel | % de Pokémon avec image officielle | Mesure la richesse visuelle du catalogue |
| Taux de sprite frontal | % de Pokémon avec sprite | Complétude des assets graphiques |
| Pokémon avec fichier brut | Nombre de Pokémon dont le JSON brut est stocké dans MinIO | Couverture du Data Lake |
| Total fichiers stockés | Nombre de fichiers dans MinIO | Volume du stockage objet |
| Stockage total (Mo) | Taille cumulée des fichiers dans MinIO | Suivi de la consommation de stockage |
| Répartition par type | Nombre et % par type principal | Équilibre du catalogue |

---

## Partie C — Restitution visuelle (Metabase)

Metabase est ajouté au `docker-compose.yml` et accessible sur `http://localhost:3000`.

Le dashboard contient :
- Les KPI globaux (total, taux de complétude, taux d'artwork, taux de sprite)
- Un graphique en barres de la répartition par type principal
- Un tableau des Pokémon incomplets
- Un résumé du stockage MinIO

### Configuration Metabase

1. Ouvrir `http://localhost:3000`
2. Créer un compte admin
3. Ajouter la base PostgreSQL :
   - Host: `postgres`
   - Port: `5432`
   - Database: `pokemon_db`
   - User: `pokemon`
   - Password: `pokemon`
4. Créer les questions à partir des vues `v_kpi_global`, `v_type_distribution`, `v_pokemon_incomplete`, `v_files_summary`
5. Assembler dans un dashboard

---

## Partie D — Automatisation Telegram

### Création du bot

1. Ouvrir Telegram et chercher **@BotFather**
2. Envoyer `/newbot`
3. Choisir un nom et un username
4. Récupérer le **token** fourni par BotFather

---

## Partie E — Commandes du bot

| Commande | Description |
|---|---|
| `/stats` | Affiche les KPI globaux du référentiel (total, complétude, artwork, sprite, stockage) |
| `/types` | Affiche la répartition par type principal avec emojis et pourcentages |
| `/incomplete` | Liste les Pokémon incomplets avec le détail des champs manquants |
| `/help` | Affiche la liste des commandes disponibles |

### Exemples de réponses

**`/stats`** :
```
📊 KPI du Référentiel Pokémon

🔢 Total Pokémon : 150
✅ Fiches complètes : 150 (100%)
🖼 Avec artwork : 150 (100%)
👾 Avec sprite : 150 (100%)
📁 Pokémon avec fichier brut : 5
💾 Fichiers stockés (MinIO) : 5
📦 Stockage total : 1.3 Mo
```

**`/types`** :
```
📋 Répartition par Type Principal

💧 water : 28 (18.7%)
⚪ normal : 22 (14.7%)
☠️ poison : 14 (9.3%)
🌿 grass : 12 (8.0%)
🔥 fire : 12 (8.0%)
...
```

**`/incomplete`** :
```
✅ Aucun Pokémon incomplet !
Toutes les fiches du référentiel sont complètes.
```

---

## Partie F — Workflow n8n Telegram

Le workflow `n8n-workflow-telegram.json` est composé de **13 nœuds** :

1. **Telegram Trigger** — Reçoit les messages envoyés au bot
2. **Route Command** (Code) — Identifie la commande (`/stats`, `/types`, `/incomplete`, `/help`)
3. **Switch** — Aiguille vers la branche correspondante
4. **Query Stats / Query Types / Query Incomplete** (Postgres) — Interroge les vues analytiques
5. **Format Stats / Format Types / Format Incomplete / Format Help** (Code) — Met en forme la réponse avec emojis et structure lisible
6. **Send Stats / Send Types / Send Incomplete / Send Help** (Telegram) — Envoie la réponse dans Telegram

### Import

1. Créer un nouveau workflow dans n8n
2. Importer `n8n-workflow-telegram.json`
3. Créer un credential **Telegram API** avec le token du bot
4. Associer ce credential au **Telegram Trigger** et aux 4 nœuds **Send**
5. Associer le credential PostgreSQL aux 3 nœuds **Query**
6. **Activer** le workflow (bouton toggle en haut à droite)

---

## Partie H — Réponse rédigée

La couche analytique intermédiaire (vues SQL) est essentielle car elle découple les tables techniques d'ingestion de la logique métier : les vues pré-calculent les indicateurs de qualité, les taux et les répartitions, ce qui évite de réécrire des requêtes complexes dans chaque outil de restitution. Les KPI ont été choisis pour couvrir les trois dimensions de qualité du référentiel : la complétude des données (fiches complètes, champs manquants), la richesse des assets (artwork, sprites), et la couverture du Data Lake (fichiers stockés, volumétrie). La restitution Metabase permet à un utilisateur non technique de comprendre en un coup d'œil l'état du catalogue grâce à des indicateurs chiffrés et des graphiques de répartition. Telegram constitue un point d'entrée complémentaire car il rend les KPI accessibles sans ouvrir un dashboard : un simple message suffit pour obtenir une synthèse à jour, ce qui est adapté à un usage mobile ou à une vérification rapide. La différence fondamentale entre une requête SQL et une automatisation Telegram est que la première nécessite un accès technique à la base, tandis que la seconde expose les données à n'importe quel utilisateur via une interface conversationnelle, avec une mise en forme lisible et une logique de routage par commande.

---

## Livrables — TP3

| Livrable | Emplacement |
|---|---|
| Vues SQL analytiques | `analytics.sql` (5 vues) |
| KPI retenus et justification | Ce README, Partie B TP3 |
| Restitution visuelle | Metabase (`http://localhost:3000`) (`Telegram_Metabase.png`)|
| Workflow n8n Telegram | `n8n-workflow-telegram.json` (`Telegram_n8n.png`) |
| Commandes Telegram | `/stats`, `/types`, `/incomplete`, `/help` |
| Exemples de réponses bot | Ce README, Partie E TP3 (`Telegram_result_preuve.png`)|
| Réponse rédigée | Ce README, Partie H TP3 |
