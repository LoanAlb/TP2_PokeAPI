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
