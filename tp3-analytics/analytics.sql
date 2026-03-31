-- ============================================
-- TP3 — Partie A : Couche analytique
-- ============================================

-- Vue 1 : Qualité par Pokémon (complétude des fiches)
CREATE OR REPLACE VIEW v_pokemon_quality AS
SELECT
    p.pokemon_id,
    p.pokemon_name,
    p.main_type,
    p.base_experience,
    p.height,
    p.weight,
    p.has_official_artwork,
    p.has_front_sprite,
    CASE WHEN pf.pokemon_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_raw_file,
    CASE
        WHEN p.pokemon_name IS NOT NULL
         AND p.base_experience IS NOT NULL
         AND p.height IS NOT NULL
         AND p.weight IS NOT NULL
         AND p.main_type IS NOT NULL AND p.main_type != 'unknown'
         AND p.has_official_artwork = TRUE
         AND p.has_front_sprite = TRUE
        THEN 'complet'
        ELSE 'incomplet'
    END AS completude,
    p.ingested_at
FROM pokemon p
LEFT JOIN (SELECT DISTINCT pokemon_id FROM pokemon_files) pf ON pf.pokemon_id = p.pokemon_id;

-- Vue 2 : Répartition par type principal
CREATE OR REPLACE VIEW v_type_distribution AS
SELECT
    main_type,
    COUNT(*) AS nb_pokemon,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM pokemon
GROUP BY main_type
ORDER BY nb_pokemon DESC;

-- Vue 3 : Synthèse des fichiers stockés dans MinIO
CREATE OR REPLACE VIEW v_files_summary AS
SELECT
    bucket_name,
    file_type,
    COUNT(*) AS nb_files,
    SUM(file_size) AS total_size_bytes,
    ROUND(AVG(file_size)) AS avg_size_bytes
FROM pokemon_files
GROUP BY bucket_name, file_type
ORDER BY bucket_name, file_type;

-- Vue 4 : KPI globaux du référentiel
CREATE OR REPLACE VIEW v_kpi_global AS
SELECT
    (SELECT COUNT(*) FROM pokemon) AS total_pokemon,
    (SELECT COUNT(*) FROM pokemon WHERE has_official_artwork = TRUE) AS with_artwork,
    (SELECT COUNT(*) FROM pokemon WHERE has_official_artwork = FALSE) AS without_artwork,
    (SELECT COUNT(*) FROM pokemon WHERE has_front_sprite = TRUE) AS with_sprite,
    (SELECT COUNT(*) FROM pokemon WHERE has_front_sprite = FALSE) AS without_sprite,
    (SELECT COUNT(*) FROM pokemon
     WHERE pokemon_name IS NOT NULL
       AND base_experience IS NOT NULL
       AND height IS NOT NULL
       AND weight IS NOT NULL
       AND main_type IS NOT NULL AND main_type != 'unknown'
       AND has_official_artwork = TRUE
       AND has_front_sprite = TRUE) AS fiches_completes,
    (SELECT COUNT(DISTINCT pokemon_id) FROM pokemon_files) AS pokemon_with_files,
    (SELECT COUNT(*) FROM pokemon_files) AS total_files_stored,
    (SELECT COALESCE(SUM(file_size), 0) FROM pokemon_files) AS total_storage_bytes;

-- Vue 5 : Pokémon incomplets (données manquantes)
CREATE OR REPLACE VIEW v_pokemon_incomplete AS
SELECT
    pokemon_id,
    pokemon_name,
    main_type,
    CASE WHEN base_experience IS NULL THEN 'base_experience ' ELSE '' END ||
    CASE WHEN height IS NULL THEN 'height ' ELSE '' END ||
    CASE WHEN weight IS NULL THEN 'weight ' ELSE '' END ||
    CASE WHEN main_type IS NULL OR main_type = 'unknown' THEN 'main_type ' ELSE '' END ||
    CASE WHEN has_official_artwork = FALSE THEN 'artwork ' ELSE '' END ||
    CASE WHEN has_front_sprite = FALSE THEN 'sprite ' ELSE '' END AS champs_manquants
FROM pokemon
WHERE base_experience IS NULL
   OR height IS NULL
   OR weight IS NULL
   OR main_type IS NULL OR main_type = 'unknown'
   OR has_official_artwork = FALSE
   OR has_front_sprite = FALSE;
