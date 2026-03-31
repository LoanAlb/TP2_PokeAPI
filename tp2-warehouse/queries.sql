-- ============================================
-- Partie E — Requêtes SQL de contrôle
-- ============================================

-- 1. Nombre total de Pokémon chargés
SELECT COUNT(*) AS total_pokemon FROM pokemon;

-- 2. Nombre de Pokémon sans image officielle (official artwork)
SELECT COUNT(*) AS sans_artwork
FROM pokemon
WHERE has_official_artwork = FALSE;

-- 3. Nombre de Pokémon sans sprite frontal
SELECT COUNT(*) AS sans_front_sprite
FROM pokemon
WHERE has_front_sprite = FALSE;

-- 4. Répartition par type principal
SELECT main_type, COUNT(*) AS nb
FROM pokemon
GROUP BY main_type
ORDER BY nb DESC;

-- 5. Pokémon dont le nom est vide ou manquant
SELECT pokemon_id, pokemon_name
FROM pokemon
WHERE pokemon_name IS NULL OR pokemon_name = '';
