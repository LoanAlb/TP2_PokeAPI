-- ============================================
-- Partie B — Préparation de la base (TP2)
-- ============================================

CREATE TABLE IF NOT EXISTS ingestion_runs (
    run_id            SERIAL PRIMARY KEY,
    source            VARCHAR(255) NOT NULL,
    started_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    finished_at       TIMESTAMP,
    status            VARCHAR(50) NOT NULL DEFAULT 'running',
    records_received  INT DEFAULT 0,
    records_inserted  INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pokemon (
    pokemon_id              INT NOT NULL,
    pokemon_name            VARCHAR(255),
    base_experience         INT,
    height                  INT,
    weight                  INT,
    main_type               VARCHAR(100),
    has_official_artwork    BOOLEAN DEFAULT FALSE,
    has_front_sprite        BOOLEAN DEFAULT FALSE,
    source_last_updated_at  TIMESTAMP,
    ingested_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    run_id                  INT REFERENCES ingestion_runs(run_id),
    PRIMARY KEY (pokemon_id, run_id)
);

-- ============================================
-- Partie B — Base enrichie (Data Lake)
-- ============================================

CREATE TABLE IF NOT EXISTS pokemon_files (
    file_id     SERIAL PRIMARY KEY,
    pokemon_id  INT NOT NULL,
    bucket_name VARCHAR(255) NOT NULL,
    object_key  VARCHAR(512) NOT NULL,
    file_name   VARCHAR(255) NOT NULL,
    file_type   VARCHAR(100) NOT NULL,
    file_size   INT,
    mime_type   VARCHAR(100),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS file_ingestion_log (
    log_id          SERIAL PRIMARY KEY,
    file_name       VARCHAR(255) NOT NULL,
    bucket_name     VARCHAR(255) NOT NULL,
    object_key      VARCHAR(512) NOT NULL,
    source          VARCHAR(255),
    status          VARCHAR(50) NOT NULL DEFAULT 'success',
    file_size       INT,
    mime_type       VARCHAR(100),
    processed_at    TIMESTAMP NOT NULL DEFAULT NOW()
);
