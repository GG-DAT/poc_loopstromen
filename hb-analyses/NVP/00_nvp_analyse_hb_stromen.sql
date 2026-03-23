-- CREATE SCHEMA hb_stromen;

-- CREATE INDEX od_locations_geom_idx
-- ON nvp_2022.od_locations
-- USING GIST (geom);

-- CREATE INDEX sensed_trips_origin_idx
-- ON federico_test.sensed_trips_2022_no_route (origin);

-- CREATE INDEX sensed_trips_destination_idx
-- ON federico_test.sensed_trips_2022_no_route (destination);

-- CREATE INDEX od_locations_geom_idx
-- ON nvp_2022.od_locations
-- USING GIST (geom);

--maken koppeltabel zonder duplicates
/* DROP TABLE IF EXISTS federico_test.koppeltabel_zonder_dup;
CREATE TABLE federico_test.koppeltabel_zonder_dup AS
SELECT *
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY sensing_record_id ORDER BY journey_id) AS rn
  FROM federico_test.koppeltabel
) sub
WHERE rn = 1;

CREATE INDEX idx_koppeltabel_zonder_dup_sensing_record_id
ON federico_test.koppeltabel_zonder_dup (sensing_record_id);

CREATE INDEX idx_koppeltabel_zonder_dup_journey_id
ON federico_test.koppeltabel_zonder_dup (journey_id); */

--FUNCTIES
CREATE OR REPLACE FUNCTION bepaal_od_locaties_vlakken(
    p_schema text,
    p_tabelnaam text,
    p_bron_tabel text,
    p_buffer_m integer DEFAULT 25
)
RETURNS void AS $$
DECLARE
    volledige_tabelnaam text := format('%I.%I', p_schema, p_tabelnaam);
    sql text;
BEGIN
    sql := format($f$
        DROP TABLE IF EXISTS %s;
        CREATE TABLE %s AS
        WITH buffer_om_polygoon AS (
            SELECT *,
                ST_Transform(
                    ST_Buffer(ST_Transform(geom, 28992), %L),
                    4326
                ) AS geom_buffer
            FROM %s
        )
        SELECT 
            od.*,
            buffer.geom AS geom_polygoon,
            buffer.name AS naam,
			buffer.code AS code
        FROM nvp_2022.od_locations od
        JOIN (
            SELECT *,
                ST_Transform(geom_buffer, 28992) AS geom_buffer_28992
            FROM buffer_om_polygoon
        ) buffer
        ON ST_Within(od.geom, buffer.geom_buffer_28992);
    $f$, volledige_tabelnaam, volledige_tabelnaam, p_buffer_m, p_bron_tabel);

    EXECUTE sql;
	
	EXECUTE format(
    'ALTER TABLE %I.%I 
     ALTER COLUMN geom_polygoon TYPE geometry(MultiPolygon, 28992)
     USING ST_Transform(geom_polygoon, 28992);',
    p_schema, p_tabelnaam
	);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bepaal_od_locaties_punten(
    p_schema TEXT,
    p_tabelnaam TEXT,
    p_bron_tabel TEXT,
    p_vlakken_tabel TEXT
)
RETURNS void AS $$
DECLARE
    volledige_tabelnaam TEXT := format('%I.%I', p_schema, p_tabelnaam);
    vlakken_tabelnaam TEXT := format('%I.%I', p_schema, p_vlakken_tabel);
    sql TEXT;
BEGIN
    sql := format($f$
        DROP TABLE IF EXISTS %s;
        CREATE TABLE %s AS
        WITH straal AS (
            SELECT   
                code,
                AVG(ST_Area(ST_Transform(geom_polygoon, 28992))) AS oppervlakte_m2,
                ROUND(SQRT(AVG(ST_Area(ST_Transform(geom_polygoon, 28992))) / pi())::numeric, 0) AS straal_meter
            FROM %s
            GROUP BY code
        ),
        buffer_om_punt AS (
            SELECT 
                p.*,
                s.straal_meter,
                ST_Transform(
                    ST_Buffer(ST_Transform(p.geom, 28992), s.straal_meter),
                    4326
                ) AS geom_buffer
            FROM %s p
            JOIN straal s ON p.code = s.code
        )
        SELECT 
            od.*,
            buffer.geom_buffer AS geom_polygoon,
            buffer.name AS naam,
			buffer.code AS code
        FROM nvp_2022.od_locations od
        JOIN (
            SELECT *,
                   ST_Transform(geom_buffer, 28992) AS geom_buffer_28992
            FROM buffer_om_punt
        ) buffer
        ON ST_Within(od.geom, buffer.geom_buffer_28992);
    $f$, volledige_tabelnaam, volledige_tabelnaam, vlakken_tabelnaam, p_bron_tabel);

    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION filter_locaties_op_aantallen(
    p_schema TEXT,
    p_tabel_naam TEXT,
    p_bron_tabel TEXT,
    p_min_aantal INTEGER,
    p_distinct_tabel_naam TEXT
)
RETURNS void AS $$
DECLARE
    sql TEXT;
BEGIN
    -- Drop bestaande tabellen als ze bestaan
    sql := format('DROP TABLE IF EXISTS %I.%I;', p_schema, p_tabel_naam);
    EXECUTE sql;

    sql := format('DROP TABLE IF EXISTS %I.%I;', p_schema, p_distinct_tabel_naam);
    EXECUTE sql;

    -- Maak gefilterde tabel aan op basis van minimum aantal
    sql := format($f$
        CREATE TABLE %I.%I AS
        WITH aantal_ods_per_polygoon AS (
            SELECT 
                naam,
                COUNT(*) AS aantal,
                geom_polygoon
            FROM %I.%I
            GROUP BY naam, geom_polygoon
        )
        SELECT *
        FROM %I.%I
        LEFT JOIN aantal_ods_per_polygoon USING(geom_polygoon, naam)
        WHERE aantal > %L;
    $f$, p_schema, p_tabel_naam, p_schema, p_bron_tabel, p_schema, p_bron_tabel, p_min_aantal);
    EXECUTE sql;

    -- Maak een tabel met unieke geometrieën + uniek ID
    sql := format($f$
        CREATE TABLE %I.%I AS
        SELECT 
            ROW_NUMBER() OVER () AS poi_id,
            naam,
            aantal,
            geom_polygoon
        FROM (
            SELECT DISTINCT naam, aantal, geom_polygoon
            FROM %I.%I
        ) sub;
    $f$, p_schema, p_distinct_tabel_naam, p_schema, p_tabel_naam);
    EXECUTE sql;

    -- Zorg voor juiste geometrie-type
    EXECUTE format(
        'ALTER TABLE %I.%I 
         ALTER COLUMN geom_polygoon TYPE geometry(MultiPolygon, 28992)
         USING ST_Transform(geom_polygoon, 28992);',
        p_schema, p_distinct_tabel_naam
    );

    -- Voeg id-kolom toe aan originele tabel
    EXECUTE format('ALTER TABLE %I.%I ADD COLUMN poi_id INTEGER;', p_schema, p_tabel_naam);

    -- Vul id-kolom op basis van match op naam en geom_polygoon
    EXECUTE format($f$
        UPDATE %I.%I t
        SET poi_id = d.poi_id
        FROM %I.%I d
        WHERE t.naam = d.naam AND ST_Equals(
            ST_Transform(t.geom_polygoon, 28992)::geometry(MultiPolygon, 28992),
            d.geom_polygoon
      );
    $f$, p_schema, p_tabel_naam, p_schema, p_distinct_tabel_naam);
	
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION toevoegen_trip_informatie(
    p_schema TEXT,
    p_tabelnaam TEXT,
    p_bron_tabel TEXT
)
RETURNS void AS
$$
BEGIN
    EXECUTE format('
        DROP TABLE IF EXISTS %I.%I;
        CREATE TABLE %I.%I AS
        SELECT 
			selectie.poi_id,
            selectie.tracker_id,
            selectie.od_id,
            ods.origin,
            ods.destination,
            ods.sensing_record_id,
            ods.trip_mode,
            ods.infra_distance,
            ods.observed_distance,
            ods.starting_point_28992,
            ods.ending_point_28992,
            selectie.naam,
            selectie.geom_polygoon,
            selectie.geom
        FROM %I.%I selectie
        LEFT JOIN federico_test.sensed_trips_2022_no_route ods
            ON (selectie.od_id::text = ods.origin OR selectie.od_id::text = ods.destination)
        WHERE route_is_valid = ''true'';
    ',
    p_schema, p_tabelnaam,
    p_schema, p_tabelnaam,
    p_schema, p_bron_tabel);
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION toevoegen_journey_informatie(
    p_schema TEXT,
    p_target_table TEXT,
    p_source_table TEXT
)
RETURNS void AS
$$
DECLARE
    sql TEXT;
BEGIN
    -- Dynamisch SQL-statement samenstellen
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         WITH koppeling_trip_journey AS (
             SELECT trips.*,
                    koppel.journey_id
             FROM %I.%I trips
             LEFT JOIN federico_test.koppeltabel_zonder_dup koppel
             ON trips.sensing_record_id = koppel.sensing_record_id::INTEGER
         )
         SELECT *
         FROM koppeling_trip_journey
         LEFT JOIN federico_test.journeys2022 USING(journey_id);

         -- Indexen op ruimtelijke kolommen
         CREATE INDEX %I_ending_point_idx
         ON %I.%I
         USING GIST (ending_point_28992);

         CREATE INDEX %I_starting_point_idx
         ON %I.%I
         USING GIST (starting_point_28992);',
        -- Parameters voor DROP/CREATE
        p_schema, p_target_table,
        p_schema, p_target_table,
        p_schema, p_source_table,
        -- Index naam + tabel voor ending_point
        p_target_table, p_schema, p_target_table,
        -- Index naam + tabel voor starting_point
        p_target_table, p_schema, p_target_table
    );

    -- Uitvoeren van de samengestelde SQL
    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bepaal_dichtstbijzijnde_station(
    p_schema TEXT,
    p_target_table TEXT,
    p_source_table TEXT
)
RETURNS void AS
$$
DECLARE
    sql TEXT;
BEGIN
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         WITH pois_met_centroid AS (
             SELECT 
                 poi_id,
                 naam,
                 aantal,
                 geom_polygoon,
                 ST_Centroid(geom_polygoon) AS geom_middelpunt
             FROM %I.%I
         )
         SELECT 
             pois.poi_id,
             pois.naam,
             pois.aantal,
             stations.station AS station_naam,
             stations.inuit,
             stations.station_type,
             ST_Distance(
                 ST_Transform(pois.geom_middelpunt, 4326)::geography,
                 ST_Transform(stations.geometry, 4326)::geography
             ) AS afstand_poi_station,
             pois.geom_polygoon,
             pois.geom_middelpunt,
             stations.geometry AS station_geom
         FROM 
             pois_met_centroid pois
         JOIN LATERAL (
             SELECT 
                 stations.station,
                 stations."InUit2019" AS inuit,
                 stations.type AS station_type,
                 stations.geometry
             FROM 
                 stations.stations_spectrum_ns stations
             ORDER BY 
                 pois.geom_middelpunt <-> stations.geometry
             LIMIT 1
         ) stations ON true;',
        p_schema, p_target_table,
        p_schema, p_target_table,
        p_schema, p_source_table
    );

    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION selecteren_trips_vanaf_station(
    p_schema TEXT,
    p_target_table_main TEXT,
    p_source_table_journey TEXT,
    p_source_table_pois TEXT,
    p_target_table_csv TEXT
)
RETURNS void AS
$$
DECLARE
    sql TEXT;
BEGIN
    -- Eerste tabel: hoofd-analysetabel
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         SELECT 
             tripdata.poi_id,
             tripdata.tracker_id,
             tripdata.sensing_record_id,
             tripdata.journey_id,
			 weights.ndays,
             CAST(1 AS NUMERIC) / CAST(weights.ndays AS NUMERIC) AS weight,
             tripdata.od_id,
             tripdata.origin,
             tripdata.destination,
			 tripdata.distance AS journey_distance,
             tripdata.infra_distance,
             tripdata.observed_distance,
             tripdata.dominant_transport_mode,
             tripdata.odin_doel,
             CASE WHEN tripdata.od_id = tripdata.origin::bigint THEN ''vanaf_poi''
                  ELSE ''naar_poi''
             END AS richting_trip,
             tripdata.trip_mode,
             CASE 
                 WHEN EXISTS (
                     SELECT 1
                     FROM stations.stations_ns_buffer buffer
                     WHERE 
                         (ST_Within(tripdata.ending_point_28992, geom_buffer_28992) AND tripdata.origin::bigint = tripdata.od_id)
                         OR 
                         (ST_Within(tripdata.starting_point_28992, geom_buffer_28992) AND tripdata.destination::bigint = tripdata.od_id)
                 )
                 THEN TRUE
                 WHEN trip_mode = ''TRAIN'' THEN TRUE
                 ELSE FALSE
             END AS vanaf_station_obv_buffer,
             CASE 
                 WHEN dominant_transport_mode = ''TRAIN'' THEN TRUE
                 ELSE FALSE
             END AS vanaf_station,
             tripdata.ending_point_28992,
             tripdata.starting_point_28992,
             ST_MakeLine(tripdata.starting_point_28992, tripdata.ending_point_28992) AS lijn_start_eind,
             geom_polygoon
         FROM %I.%I tripdata
         LEFT JOIN federico_test.weights_trackers weights USING(tracker_id) 
         LEFT JOIN %I.%I pois USING(geom_polygoon)
         WHERE tripdata.ending_point_28992 IS NOT NULL
            OR tripdata.starting_point_28992 IS NOT NULL;',
        -- DROP/CREATE hoofdtabel
        p_schema, p_target_table_main,
        p_schema, p_target_table_main,
        -- Brontabellen journey en pois
        p_schema, p_source_table_journey,
        p_schema, p_source_table_pois
    );

    EXECUTE sql;

    -- Tweede tabel: afgeleide voor csv
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         SELECT 
             poi_id,
             weight,
             infra_distance,
             observed_distance,
             trip_mode,
			 vanaf_station_obv_buffer
         FROM %I.%I
         WHERE vanaf_station = TRUE;',
        -- DROP/CREATE tabel
        p_schema, p_target_table_csv,
        p_schema, p_target_table_csv,
        -- Bron: de eerder aangemaakte hoofdtabel
        p_schema, p_target_table_main
    );

    EXECUTE sql;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sommeren_trips_vanaf_station_per_poi(
    p_schema TEXT,
    p_target_table TEXT,
    p_source_table TEXT
)
RETURNS void AS
$$
DECLARE
    sql TEXT;
BEGIN
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         SELECT 
             poi_id,
			 COUNT(DISTINCT tracker_id) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN'') AS aantal_unieke_trackers,
			 AVG(journey_distance) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN'') AS journey_distance_gem,
			 COUNT(*) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN'' AND journey_distance > 10000) AS aantal_regionale_reizen,
			 (COUNT(*) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN'' AND journey_distance > 10000)::NUMERIC) /
			 NULLIF(COUNT(*) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN''), 0) AS aandeel_regionale_reizen,
			 
             COUNT(*) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN'') AS aantal_trips,
			 COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND vanaf_station_obv_buffer = TRUE) AS aantal_trips_trein_station_buffer,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''FOOT'') AS aantal_trips_lopen,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''BIKE'') AS aantal_trips_fiets,
             COUNT(*) FILTER (WHERE dominant_transport_mode IN (''BUS'',''TRAM'',''METRO'',''LIGHTRAIL'')) AS aantal_trips_BTM,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'') AS aantal_trips_trein,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''CAR'') AS aantal_trips_auto,
             
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> ''UNKNOWN''), 0) AS aantal_trips_gewogen,
			 COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND vanaf_station_obv_buffer = TRUE), 0) AS aantal_trips_trein_station_buffer_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''FOOT''), 0) AS aantal_trips_lopen_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''BIKE''), 0) AS aantal_trips_fiets_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode IN (''BUS'',''TRAM'',''METRO'',''LIGHTRAIL'')), 0) AS aantal_trips_BTM_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN''), 0) AS aantal_trips_trein_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''CAR''), 0) AS aantal_trips_auto_gewogen,

             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'') AS aantal_trips_station,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''FOOT'') AS aantal_trips_station_lopen,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''BIKE'') AS aantal_trips_station_fiets,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode IN (''BUS'',''TRAM'',''METRO'',''LIGHTRAIL'')) AS aantal_trips_station_BTM,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''TRAIN'') AS aantal_trips_station_trein,
             COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''CAR'') AS aantal_trips_station_auto,

             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN''), 0) AS aantal_trips_station_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''FOOT''), 0) AS aantal_trips_station_lopen_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''BIKE''), 0) AS aantal_trips_station_fiets_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode IN (''BUS'',''TRAM'',''METRO'',''LIGHTRAIL'')), 0) AS aantal_trips_station_BTM_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''TRAIN''), 0) AS aantal_trips_station_trein_gewogen,
             COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''CAR''), 0) AS aantal_trips_station_auto_gewogen,

             (SUM(infra_distance) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''FOOT'')) / 
             NULLIF(COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND trip_mode = ''FOOT''), 0) AS loopafstand_gem
         FROM %I.%I
         GROUP BY poi_id
         ORDER BY aantal_trips_station DESC;',
        p_schema, p_target_table,
        p_schema, p_target_table,
        p_schema, p_source_table
    );

    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

--COUNT(*) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND vanaf_station_obv_buffer = TRUE AND trip_mode IN (''FOOT'',''BIKE'')) AS aantal_trips_trein_station_buffer,
--COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = ''TRAIN'' AND vanaf_station_obv_buffer = TRUE AND trip_mode IN (''FOOT'',''BIKE'')), 0) AS aantal_trips_trein_station_buffer_gewogen,

CREATE OR REPLACE FUNCTION maak_uitvoer_data(
    p_schema TEXT,
    p_target_table TEXT,
    p_brondata_pois TEXT,
    p_brondata_trips TEXT,
    p_poi_type_col TEXT  -- nieuw toegevoegd
)
RETURNS void AS
$$
DECLARE
    sql TEXT;
BEGIN
    sql := format(
        'DROP TABLE IF EXISTS %I.%I;
         CREATE TABLE %I.%I AS
         SELECT 
            pois.poi_id,
            %L AS poi_type,  -- dynamisch toegevoegde kolom
            pois.aantal,
            pois.afstand_poi_station,
            tripdata.loopafstand_gem,
            pois.naam,
            pois.station_naam,
            pois.inuit,
            pois.station_type,
            tripdata.aantal_unieke_trackers,
            tripdata.aantal_trips,
			tripdata.aantal_trips_trein_station_buffer,
            tripdata.journey_distance_gem,
            tripdata.aantal_regionale_reizen,
            tripdata.aandeel_regionale_reizen,
            tripdata.aantal_trips_lopen,
            tripdata.aantal_trips_fiets,
            tripdata.aantal_trips_BTM,
            tripdata.aantal_trips_trein,
            tripdata.aantal_trips_auto,
            ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_lopen::numeric / tripdata.aantal_trips) END, 3) AS fractie_lopen,
            ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_fiets::numeric / tripdata.aantal_trips) END, 3) AS fractie_fiets,
            ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_BTM::numeric / tripdata.aantal_trips) END, 3) AS fractie_BTM,
            ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_trein::numeric / tripdata.aantal_trips) END, 3) AS fractie_trein,
			ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_trein_station_buffer::numeric / tripdata.aantal_trips) END, 3) AS fractie_trein_station_buffer,
            ROUND(CASE WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0 ELSE (tripdata.aantal_trips_auto::numeric / tripdata.aantal_trips) END, 3) AS fractie_auto,
            ROUND(tripdata.aantal_trips_gewogen::numeric,3) AS aantal_trips_gewogen,
            ROUND(tripdata.aantal_trips_lopen_gewogen::numeric,3) AS aantal_trips_lopen_gewogen,
            ROUND(tripdata.aantal_trips_fiets_gewogen::numeric,3) AS aantal_trips_fiets_gewogen,
            ROUND(tripdata.aantal_trips_BTM_gewogen::numeric,3) AS aantal_trips_BTM_gewogen,
            ROUND(tripdata.aantal_trips_trein_gewogen::numeric,3) AS aantal_trips_trein_gewogen,
			ROUND(tripdata.aantal_trips_trein_station_buffer_gewogen::numeric,3) AS aantal_trips_trein_station_buffer_gewogen,
            ROUND(tripdata.aantal_trips_auto_gewogen::numeric,3) AS aantal_trips_auto_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_lopen_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_lopen_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_fiets_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_fiets_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_BTM_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_BTM_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_trein_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_trein_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_trein_station_buffer_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_trein_station_buffer_gewogen,
			ROUND(CASE WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_auto_gewogen::numeric / tripdata.aantal_trips_gewogen) END, 3) AS fractie_auto_gewogen,
            tripdata.aantal_trips_station,
            tripdata.aantal_trips_station_lopen,
            tripdata.aantal_trips_station_fiets,
            tripdata.aantal_trips_station_BTM,
            tripdata.aantal_trips_station_trein,
            tripdata.aantal_trips_station_auto,
            ROUND(tripdata.aantal_trips_station_gewogen::numeric,1) AS aantal_trips_station_gewogen,
            ROUND(tripdata.aantal_trips_station_lopen_gewogen::numeric,1) AS aantal_trips_station_lopen_gewogen,
            ROUND(tripdata.aantal_trips_station_fiets_gewogen::numeric,1) AS aantal_trips_station_fiets_gewogen,
            ROUND(tripdata.aantal_trips_station_BTM_gewogen::numeric,1) AS aantal_trips_station_BTM_gewogen,
            ROUND(tripdata.aantal_trips_station_trein_gewogen::numeric,1) AS aantal_trips_station_trein_gewogen,
            ROUND(tripdata.aantal_trips_station_auto_gewogen::numeric,1) AS aantal_trips_station_auto_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_station = 0 OR tripdata.aantal_trips_station IS NULL THEN 0 ELSE (tripdata.aantal_trips_station_lopen::numeric / tripdata.aantal_trips_station) END, 3) AS fractie_station_lopen,
            ROUND(CASE WHEN tripdata.aantal_trips_station = 0 OR tripdata.aantal_trips_station IS NULL THEN 0 ELSE ((tripdata.aantal_trips_station_lopen::numeric + tripdata.aantal_trips_station_trein::numeric) / tripdata.aantal_trips_station) END, 3) AS fractie_station_lopen_en_trein,
            ROUND(CASE WHEN tripdata.aantal_trips_station_gewogen = 0 OR tripdata.aantal_trips_station_gewogen IS NULL THEN 0 ELSE (tripdata.aantal_trips_station_lopen_gewogen::numeric / tripdata.aantal_trips_station_gewogen) END, 3) AS fractie_station_lopen_gewogen,
            ROUND(CASE WHEN tripdata.aantal_trips_station_gewogen = 0 OR tripdata.aantal_trips_station_gewogen IS NULL THEN 0 ELSE ((tripdata.aantal_trips_station_lopen_gewogen::numeric + tripdata.aantal_trips_station_trein_gewogen::numeric) / tripdata.aantal_trips_station_gewogen) END, 3) AS fractie_station_lopen_en_trein_gewogen,
            pois.geom_polygoon,
            pois.station_geom
         FROM %I.%I pois
         LEFT JOIN %I.%I tripdata USING(poi_id);',
        p_schema, p_target_table,
        p_schema, p_target_table,
        p_poi_type_col,  -- dynamische kolom
        p_schema, p_brondata_pois,
        p_schema, p_brondata_trips
    );

    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

--AANROEP

--schema, tabelnaam, brontabel, buffer
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'stadion_od_locaties_vlakken', 'osm.poisa_stadion', 50); --46
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'gezondheid_od_locaties_vlakken', 'osm.poisa_gezondheid', 10); --107 -> 115
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'cultuur_od_locaties_vlakken', 'osm.poisa_cultuur', 1); --79
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'bioscoop_od_locaties_vlakken', 'osm.poisa_bioscoop', 10); --8
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'attractiepark_od_locaties_vlakken', 'osm.poisa_attractiepark', 10); --205 -> 277
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'ijsbaan_od_locaties_vlakken', 'osm.poisa_ijsbaan', 50); --7 ->15
SELECT bepaal_od_locaties_vlakken('hb_stromen', 'sport_od_locaties_vlakken', 'osm.poisa_sport', 25); --271 -> 517

--schema, tabelnaam_ods, brontabel, minimum aantal ods, tabelnaam_pois 
SELECT filter_locaties_op_aantallen('hb_stromen', 'stadion_od_locaties_gefiltered', 'stadion_od_locaties_vlakken', 10, 'stadion_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'gezondheid_od_locaties_gefiltered', 'gezondheid_od_locaties_vlakken', 10, 'gezondheid_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'cultuur_od_locaties_gefiltered', 'cultuur_od_locaties_vlakken', 10, 'cultuur_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'bioscoop_od_locaties_gefiltered', 'bioscoop_od_locaties_vlakken', 10, 'bioscoop_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'attractiepark_od_locaties_gefiltered', 'attractiepark_od_locaties_vlakken', 10, 'attractiepark_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'ijsbaan_od_locaties_gefiltered', 'ijsbaan_od_locaties_vlakken', 10, 'ijsbaan_poisa_gefiltered');
SELECT filter_locaties_op_aantallen('hb_stromen', 'sport_od_locaties_gefiltered', 'sport_od_locaties_vlakken', 10, 'sport_poisa_gefiltered');

--schema, tabelnaam, brontabel
SELECT toevoegen_trip_informatie('hb_stromen', 'stadion_od_locaties_tripdata', 'stadion_od_locaties_gefiltered'); 
SELECT toevoegen_trip_informatie('hb_stromen', 'gezondheid_od_locaties_tripdata', 'gezondheid_od_locaties_gefiltered'); 
SELECT toevoegen_trip_informatie('hb_stromen', 'cultuur_od_locaties_tripdata', 'cultuur_od_locaties_gefiltered');
SELECT toevoegen_trip_informatie('hb_stromen', 'bioscoop_od_locaties_tripdata', 'bioscoop_od_locaties_gefiltered');
SELECT toevoegen_trip_informatie('hb_stromen', 'attractiepark_od_locaties_tripdata', 'attractiepark_od_locaties_gefiltered');
SELECT toevoegen_trip_informatie('hb_stromen', 'ijsbaan_od_locaties_tripdata', 'ijsbaan_od_locaties_gefiltered');
SELECT toevoegen_trip_informatie('hb_stromen', 'sport_od_locaties_tripdata', 'sport_od_locaties_gefiltered');

--schema, tabelnaam, brontabel
SELECT toevoegen_journey_informatie('hb_stromen', 'stadion_od_locaties_journeydata', 'stadion_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'gezondheid_od_locaties_journeydata', 'gezondheid_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'cultuur_od_locaties_journeydata', 'cultuur_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'bioscoop_od_locaties_journeydata', 'bioscoop_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'attractiepark_od_locaties_journeydata', 'attractiepark_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'ijsbaan_od_locaties_journeydata', 'ijsbaan_od_locaties_tripdata');
SELECT toevoegen_journey_informatie('hb_stromen', 'sport_od_locaties_journeydata', 'sport_od_locaties_tripdata');

--FORMAT TABEL MET STATIONS
ALTER TABLE stations.stations_spectrum_ns
ALTER COLUMN geometry TYPE geometry(Point, 28992)
USING ST_SetSRID(geometry, 28992);

DROP TABLE IF EXISTS stations.stations_ns_buffer;
CREATE TABLE stations.stations_ns_buffer AS
	SELECT *,
	ST_Transform(
			ST_Buffer(ST_Transform(geometry, 28992), 250),
			4326
		) AS geom_buffer
	FROM stations.stations_spectrum_ns;

ALTER TABLE stations.stations_ns_buffer ADD COLUMN geom_buffer_28992 geometry(Polygon, 28992);

UPDATE stations.stations_ns_buffer
SET geom_buffer_28992 = ST_Transform(geom_buffer, 28992);

CREATE INDEX stations_ns_buffer_geom_28992_idx
ON stations.stations_ns_buffer
USING GIST (geom_buffer_28992);

CREATE INDEX stations_ns_buffer_geom_idx
ON stations.stations_ns_buffer
USING GIST (geom_buffer);

--schema, tabelnaam, brontabel
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'stadion_poisa_dichtbijzijnde_station', 'stadion_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'gezondheid_poisa_dichtbijzijnde_station', 'gezondheid_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'cultuur_poisa_dichtbijzijnde_station', 'cultuur_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'bioscoop_poisa_dichtbijzijnde_station', 'bioscoop_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'attractiepark_poisa_dichtbijzijnde_station', 'attractiepark_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'ijsbaan_poisa_dichtbijzijnde_station', 'ijsbaan_poisa_gefiltered');
SELECT bepaal_dichtstbijzijnde_station('hb_stromen', 'sport_poisa_dichtbijzijnde_station', 'sport_poisa_gefiltered');

--schema, tabelnaam, brontabel_journey, brontabel_pois, tabelnaam_csv
SELECT selecteren_trips_vanaf_station('hb_stromen', 'stadion_analyse_vanaf_station', 'stadion_od_locaties_journeydata', 'stadion_poisa_gefiltered', 'stadion_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'gezondheid_analyse_vanaf_station', 'gezondheid_od_locaties_journeydata', 'gezondheid_poisa_gefiltered', 'gezondheid_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'cultuur_analyse_vanaf_station', 'cultuur_od_locaties_journeydata', 'cultuur_poisa_gefiltered', 'cultuur_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'bioscoop_analyse_vanaf_station', 'bioscoop_od_locaties_journeydata', 'bioscoop_poisa_gefiltered', 'bioscoop_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'attractiepark_analyse_vanaf_station', 'attractiepark_od_locaties_journeydata', 'attractiepark_poisa_gefiltered', 'attractiepark_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'ijsbaan_analyse_vanaf_station', 'ijsbaan_od_locaties_journeydata', 'ijsbaan_poisa_gefiltered', 'ijsbaan_analyse_vanaf_station_voorna');
SELECT selecteren_trips_vanaf_station('hb_stromen', 'sport_analyse_vanaf_station', 'sport_od_locaties_journeydata', 'sport_poisa_gefiltered', 'sport_analyse_vanaf_station_voorna');

--schema, tabelnaam, brontabel
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'stadion_poisa_aantal_vanaf_station', 'stadion_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'gezondheid_poisa_aantal_vanaf_station', 'gezondheid_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'cultuur_poisa_aantal_vanaf_station', 'cultuur_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'bioscoop_poisa_aantal_vanaf_station', 'bioscoop_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'attractiepark_poisa_aantal_vanaf_station', 'attractiepark_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'ijsbaan_poisa_aantal_vanaf_station', 'ijsbaan_analyse_vanaf_station');
SELECT sommeren_trips_vanaf_station_per_poi('hb_stromen', 'sport_poisa_aantal_vanaf_station', 'sport_analyse_vanaf_station');

--schema, tabelnaam, brontabel_trips, brontabel_pois, naam_poi
SELECT maak_uitvoer_data('hb_stromen', 'stadion_data', 'stadion_poisa_dichtbijzijnde_station', 'stadion_poisa_aantal_vanaf_station', 'stadion');
SELECT maak_uitvoer_data('hb_stromen', 'gezondheid_data', 'gezondheid_poisa_dichtbijzijnde_station', 'gezondheid_poisa_aantal_vanaf_station', 'gezondheid');
SELECT maak_uitvoer_data('hb_stromen', 'cultuur_data', 'cultuur_poisa_dichtbijzijnde_station', 'cultuur_poisa_aantal_vanaf_station', 'cultuur');
SELECT maak_uitvoer_data('hb_stromen', 'bioscoop_data', 'bioscoop_poisa_dichtbijzijnde_station', 'bioscoop_poisa_aantal_vanaf_station', 'bioscoop');
SELECT maak_uitvoer_data('hb_stromen', 'attractiepark_data', 'attractiepark_poisa_dichtbijzijnde_station', 'attractiepark_poisa_aantal_vanaf_station', 'attractiepark');
SELECT maak_uitvoer_data('hb_stromen', 'ijsbaan_data', 'ijsbaan_poisa_dichtbijzijnde_station', 'ijsbaan_poisa_aantal_vanaf_station', 'ijsbaan');
SELECT maak_uitvoer_data('hb_stromen', 'sport_data', 'sport_poisa_dichtbijzijnde_station', 'sport_poisa_aantal_vanaf_station', 'sport');

--1 gecombineerde tabel maken 
DROP TABLE IF EXISTS hb_stromen.poi_data;
CREATE TABLE hb_stromen.poi_data AS
	SELECT 
		*		
	FROM hb_stromen.stadion_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.gezondheid_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.cultuur_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.bioscoop_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.attractiepark_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.ijsbaan_data
	
	UNION ALL
	
	SELECT 
		*
	FROM hb_stromen.sport_data;
	
---CODE ZONDER FUNCTIES
/* DROP TABLE IF EXISTS hb_stromen.od_locaties_stadion;
CREATE TABLE hb_stromen.od_locaties_stadion AS
	WITH buffer_om_polygoon AS (
	SELECT *,
		ST_Transform(
			ST_Buffer(ST_Transform(geom, 28992), 25),
			4326
		) AS geom_buffer
	FROM osm.poisa_stadion	   
	)
	SELECT 
		od.*,
		buffer.geom AS geom_polygoon,
		buffer.name AS naam
	FROM nvp_2022.od_locations od
	JOIN (
		SELECT *,
			ST_Transform(geom_buffer, 28992) AS geom_buffer_28992
		FROM buffer_om_polygoon
	) buffer
	ON ST_Within(od.geom, buffer.geom_buffer_28992); */
	
-- DROP TABLE IF EXISTS hb_stromen.aantal_ods_per_stadion;
-- CREATE TABLE hb_stromen.aantal_ods_per_stadion AS	
	-- SELECT 
		-- naam,
		-- COUNT(*) AS aantal,
		-- geom_polygoon
	-- FROM hb_stromen.od_locaties_stadion
	-- GROUP BY naam, geom_polygoon
	-- ORDER BY COUNT(*) DESC;
	
/* DROP TABLE IF EXISTS hb_stromen.od_locaties_stadion_gefiltered;
CREATE TABLE hb_stromen.od_locaties_stadion_gefiltered AS
	WITH aantal_ods_per_polygoon AS (
		SELECT 
			naam,
			COUNT(*) AS aantal,
			geom_polygoon
		FROM hb_stromen.od_locaties_stadion
	GROUP BY naam, geom_polygoon
	)
	SELECT *
	FROM hb_stromen.od_locaties_stadion
	LEFT JOIN aantal_ods_per_polygoon USING(geom_polygoon,naam)
	WHERE aantal > 10;

DROP TABLE IF EXISTS hb_stromen.od_informatie_stadion;
CREATE TABLE hb_stromen.od_informatie_stadion AS
	SELECT 
		selectie.tracker_id,
		selectie.od_id,
		ods.origin,
		ods.destination,
		ods.sensing_record_id,
		ods.trip_mode,
		-- selectie.ntrip,
		-- selectie.nwalk,
		-- selectie.nbike,
		-- selectie.ncar,
		-- selectie.npt,	
		ods.infra_distance,
		ods.observed_distance,
		ods.starting_point_28992,
		ods.ending_point_28992,
		selectie.naam,
		selectie.geom_polygoon,
		selectie.geom
	FROM hb_stromen.od_locaties_stadion_gefiltered selectie
	LEFT JOIN federico_test.sensed_trips_2022_no_route ods
	ON (selectie.od_id::text = ods.origin OR selectie.od_id::text = ods.destination)
	WHERE route_is_valid = 'true';
	 */

--TOEVOEGEN JOURNEY DATA
-- DROP TABLE IF EXISTS hb_stromen.stadion_od_locaties_journeydata;
-- CREATE TABLE hb_stromen.stadion_od_locaties_journeydata AS
	-- WITH koppeling_trip_journey AS(
		-- SELECT trips.*,
		-- koppel.journey_id
		-- FROM hb_stromen.stadion_od_locaties_tripdata trips
		-- LEFT JOIN federico_test.koppeltabel koppel
		-- ON trips.sensing_record_id = koppel.sensing_record_id::INTEGER
	-- )
	-- SELECT
		-- *
	-- FROM koppeling_trip_journey
	-- LEFT JOIN federico_test.journeys2022 USING(journey_id);
	
/* CREATE INDEX journeydata_ending_point_idx
ON hb_stromen.stadion_od_locaties_journeydata
USING GIST (ending_point_28992);

CREATE INDEX journeydata_starting_point_idx
ON hb_stromen.stadion_od_locaties_journeydata
USING GIST (starting_point_28992); */

/* --BEPALEN DICHTSBIJZIJNDE STATION (1)
DROP TABLE IF EXISTS hb_stromen.stadion_poisa_dichtbijzijnde_station;
CREATE TABLE hb_stromen.stadion_poisa_dichtbijzijnde_station AS
WITH pois_met_centroid AS (
    SELECT 
        poi_id,
        naam,
        aantal,
        geom_polygoon,
        ST_Centroid(geom_polygoon) AS geom_middelpunt
    FROM hb_stromen.stadion_poisa_gefiltered
)
SELECT 
    pois.poi_id,
    pois.naam,
    pois.aantal,
    stations.station AS station_naam,
    stations.inuit,
	stations.station_type,
	ST_Distance(
        ST_Transform(pois.geom_middelpunt, 4326)::geography,
        ST_Transform(stations.geometry, 4326)::geography
    ) AS afstand_poi_station,
	pois.geom_polygoon,
    pois.geom_middelpunt,
    stations.geometry AS station_geom    
FROM 
    pois_met_centroid pois
JOIN LATERAL (
    SELECT 
        stations.station,
        stations."InUit2019" AS inuit,
		stations.type AS station_type,
        stations.geometry
    FROM 
        stations.stations_spectrum_ns stations
    ORDER BY 
        pois.geom_middelpunt <-> stations.geometry
    LIMIT 1
) stations ON true; */

/* --BEPALEN AANTAL VANAF STATION (2)
DROP TABLE IF EXISTS hb_stromen.stadion_analyse_vanaf_station;
CREATE TABLE hb_stromen.stadion_analyse_vanaf_station AS
SELECT 
    tripdata.poi_id,
    tripdata.tracker_id,
	tripdata.sensing_record_id,
	tripdata.journey_id,
	weights.ndays AS weight,
	-- SQRT(weights.ndays) AS weight,
    tripdata.od_id,
	tripdata.origin,
	tripdata.destination,
	tripdata.infra_distance,
	tripdata.observed_distance,
	tripdata.dominant_transport_mode,
	tripdata.odin_doel,
	CASE WHEN tripdata.od_id = tripdata.origin::bigint THEN 'vanaf_poi'
	ELSE 'naar_poi'
	END AS richting_trip,
    tripdata.trip_mode,
    CASE 
        WHEN EXISTS (
            SELECT 1
            FROM stations.stations_ns_buffer buffer
            WHERE 
                ST_Within(tripdata.ending_point_28992, geom_buffer_28992) AND tripdata.origin::bigint = tripdata.od_id OR 
                ST_Within(tripdata.starting_point_28992, geom_buffer_28992) AND tripdata.destination::bigint = tripdata.od_id 
        )
        THEN TRUE
		WHEN trip_mode = 'TRAIN' THEN TRUE
        ELSE FALSE
    END AS vanaf_station_obv_buffer,
	CASE 
        WHEN dominant_transport_mode = 'TRAIN' THEN TRUE
        ELSE FALSE
    END AS vanaf_station,
    tripdata.ending_point_28992,
    tripdata.starting_point_28992,
    ST_MakeLine(tripdata.starting_point_28992, tripdata.ending_point_28992) AS lijn_start_eind,
    geom_polygoon
FROM hb_stromen.stadion_od_locaties_journeydata tripdata
LEFT JOIN federico_test.weights_trackers weights USING(tracker_id) 
LEFT JOIN hb_stromen.stadion_poisa_gefiltered pois
USING (geom_polygoon)
WHERE tripdata.ending_point_28992 IS NOT NULL
   OR tripdata.starting_point_28992 IS NOT NULL;
 
DROP TABLE IF EXISTS hb_stromen.stadion_analyse_vanaf_station_voorna;
CREATE TABLE hb_stromen.stadion_analyse_vanaf_station_voorna AS 
SELECT 
	poi_id,
	weight,
	infra_distance,
	observed_distance,
	trip_mode
FROM hb_stromen.stadion_analyse_vanaf_station
WHERE vanaf_station = 'TRUE'; */

/* --SOMMEREN AANTAL VANAF STATION (3)
DROP TABLE IF EXISTS hb_stromen.stadion_poisa_aantal_vanaf_station;
CREATE TABLE hb_stromen.stadion_poisa_aantal_vanaf_station AS
SELECT 
    poi_id,
	-- dominant transport mode
	COUNT(*) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> 'UNKNOWN') AS aantal_trips,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'FOOT') AS aantal_trips_lopen,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'BIKE') AS aantal_trips_fiets,
	COUNT(*) FILTER (WHERE dominant_transport_mode IN ('BUS','TRAM','METRO','LIGHTRAIL')) AS aantal_trips_BTM,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN') AS aantal_trips_trein,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'CAR') AS aantal_trips_auto,
	-- dominant transport mode gewogen
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode IS NOT NULL AND dominant_transport_mode <> 'UNKNOWN'), 0) AS aantal_trips_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'FOOT'), 0) AS aantal_trips_lopen_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'BIKE'), 0) AS aantal_trips_fiets_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode IN ('BUS','TRAM','METRO','LIGHTRAIL')), 0) AS aantal_trips_BTM_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN'), 0) AS aantal_trips_trein_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'CAR'), 0) AS aantal_trips_auto_gewogen,
	-- dominant transport mode = trein, trip mode
    COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN') AS aantal_trips_station,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'FOOT') AS aantal_trips_station_lopen,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'BIKE') AS aantal_trips_station_fiets,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode IN ('BUS','TRAM','METRO','LIGHTRAIL')) AS aantal_trips_station_BTM,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'TRAIN') AS aantal_trips_station_trein,
	COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'CAR') AS aantal_trips_station_auto,
	-- dominant transport mode = trein, trip mode gewogen
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN'), 0) AS aantal_trips_station_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'FOOT'), 0) AS aantal_trips_station_lopen_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'BIKE'), 0) AS aantal_trips_station_fiets_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode IN ('BUS','TRAM','METRO','LIGHTRAIL')), 0) AS aantal_trips_station_BTM_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'TRAIN'), 0) AS aantal_trips_station_trein_gewogen,
	COALESCE(SUM(weight) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'CAR'), 0) AS aantal_trips_station_auto_gewogen,
	-- gemiddelde loopaftand
	(SUM(infra_distance) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'FOOT')) / (COUNT(*) FILTER (WHERE dominant_transport_mode = 'TRAIN' AND trip_mode = 'FOOT')) AS loopafstand_gem
FROM hb_stromen.stadion_analyse_vanaf_station
GROUP BY poi_id
ORDER BY aantal_trips_station DESC
; */

/* --SAMENVOEGEN DATA (4)
DROP TABLE IF EXISTS hb_stromen.stadion_data;
CREATE TABLE hb_stromen.stadion_data AS
SELECT 
    pois.poi_id,
	pois.aantal,
	pois.afstand_poi_station,
	tripdata.loopafstand_gem,
    pois.naam,
    pois.station_naam,
	pois.inuit,
	pois.station_type,
    tripdata.aantal_trips,
    tripdata.aantal_trips_lopen,
	tripdata.aantal_trips_fiets,
    tripdata.aantal_trips_BTM,
	tripdata.aantal_trips_trein,
	tripdata.aantal_trips_auto,
	ROUND(
        CASE 
            WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0
            ELSE (tripdata.aantal_trips_lopen::numeric / tripdata.aantal_trips)::numeric
        END, 
        3
    ) AS fractie_lopen,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0
            ELSE (tripdata.aantal_trips_fiets::numeric / tripdata.aantal_trips)::numeric
        END, 
        3
    ) AS fractie_fiets,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0
            ELSE (tripdata.aantal_trips_BTM::numeric / tripdata.aantal_trips)::numeric
        END, 
        3
    ) AS fractie_BTM,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0
            ELSE (tripdata.aantal_trips_trein::numeric / tripdata.aantal_trips)::numeric
        END, 
        3
    ) AS fractie_trein,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips = 0 OR tripdata.aantal_trips IS NULL THEN 0
            ELSE (tripdata.aantal_trips_auto::numeric / tripdata.aantal_trips)::numeric
        END, 
        3
    ) AS fractie_auto,	
    ROUND(tripdata.aantal_trips_gewogen::numeric,3) AS aantal_trips_gewogen,
	ROUND(tripdata.aantal_trips_lopen_gewogen::numeric,3) AS aantal_trips_lopen_gewogen,
	ROUND(tripdata.aantal_trips_fiets_gewogen::numeric,3) AS aantal_trips_fiets_gewogen,
    ROUND(tripdata.aantal_trips_BTM_gewogen::numeric,3) AS aantal_trips_BTM_gewogen,
	ROUND(tripdata.aantal_trips_trein_gewogen::numeric,3) AS aantal_trips_trein_gewogen,
	ROUND(tripdata.aantal_trips_auto_gewogen::numeric,3) AS aantal_trips_auto_gewogen,
	ROUND(
        CASE 
            WHEN tripdata.aantal_trips_lopen_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0
            ELSE (tripdata.aantal_trips_lopen_gewogen::numeric / tripdata.aantal_trips_gewogen)::numeric
        END, 
        3
    ) AS fractie_lopen_gewogen,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0
            ELSE (tripdata.aantal_trips_fiets_gewogen::numeric / tripdata.aantal_trips_gewogen)::numeric
        END, 
        3
    ) AS fractie_fiets_gewogen,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0
            ELSE (tripdata.aantal_trips_BTM_gewogen::numeric / tripdata.aantal_trips_gewogen)::numeric
        END, 
        3
    ) AS fractie_BTM_gewogen,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0
            ELSE (tripdata.aantal_trips_trein_gewogen::numeric / tripdata.aantal_trips_gewogen)::numeric
        END, 
        3
    ) AS fractie_trein_gewogen,
	 ROUND(
        CASE 
            WHEN tripdata.aantal_trips_gewogen = 0 OR tripdata.aantal_trips_gewogen IS NULL THEN 0
            ELSE (tripdata.aantal_trips_auto_gewogen::numeric / tripdata.aantal_trips_gewogen)::numeric
        END, 
        3
    ) AS fractie_auto_gewogen,
	tripdata.aantal_trips_station,
    tripdata.aantal_trips_station_lopen,
	tripdata.aantal_trips_station_fiets,
    tripdata.aantal_trips_station_BTM,
	tripdata.aantal_trips_station_trein,
	tripdata.aantal_trips_station_auto,
    ROUND(tripdata.aantal_trips_station_gewogen::numeric,1) AS aantal_trips_station_gewogen,
	ROUND(tripdata.aantal_trips_station_lopen_gewogen::numeric,1) AS aantal_trips_station_lopen_gewogen,
	ROUND(tripdata.aantal_trips_station_fiets_gewogen::numeric,1) AS aantal_trips_station_fiets_gewogen,
    ROUND(tripdata.aantal_trips_station_BTM_gewogen::numeric,1) AS aantal_trips_station_BTM_gewogen,
	ROUND(tripdata.aantal_trips_station_trein_gewogen::numeric,1) AS aantal_trips_station_trein_gewogen,
	ROUND(tripdata.aantal_trips_station_auto_gewogen::numeric,1) AS aantal_trips_station_auto_gewogen,
    ROUND(
        CASE 
            WHEN tripdata.aantal_trips_station = 0 OR tripdata.aantal_trips_station IS NULL THEN 0
            ELSE ((tripdata.aantal_trips_station_lopen::numeric)  / tripdata.aantal_trips_station)::numeric
        END,
        3
    ) AS fractie_station_lopen,
	ROUND(
        CASE 
            WHEN tripdata.aantal_trips_station = 0 OR tripdata.aantal_trips_station IS NULL THEN 0
            ELSE ((tripdata.aantal_trips_station_lopen::numeric + tripdata.aantal_trips_station_trein::numeric )  / tripdata.aantal_trips_station)::numeric
        END,
        3
    ) AS fractie_station_lopen_en_trein,
	ROUND(
        CASE 
            WHEN tripdata.aantal_trips_station_gewogen = 0 OR tripdata.aantal_trips_station_gewogen IS NULL THEN 0
            ELSE ((tripdata.aantal_trips_station_lopen_gewogen::numeric) / tripdata.aantal_trips_station_gewogen::numeric)
        END,
        3
    ) AS fractie_station_lopen_gewogen,
	ROUND(
        CASE 
            WHEN tripdata.aantal_trips_station_gewogen = 0 OR tripdata.aantal_trips_station_gewogen IS NULL THEN 0
            ELSE ((tripdata.aantal_trips_station_lopen_gewogen::numeric + tripdata.aantal_trips_station_trein_gewogen::numeric) / tripdata.aantal_trips_station_gewogen::numeric)
        END,
        3
    ) AS fractie_station_lopen_en_trein_gewogen,
    pois.geom_polygoon,
    pois.station_geom    
FROM hb_stromen.stadion_poisa_dichtbijzijnde_station pois
LEFT JOIN hb_stromen.stadion_poisa_aantal_vanaf_station tripdata
USING(poi_id); */


/* --BEPALEN TRIPMODE ERVOOR
DROP TABLE IF EXISTS federico_test.sensed_trips_2022_no_route_koppel;
CREATE TABLE federico_test.sensed_trips_2022_no_route_koppel AS
SELECT trips.*,
       koppel.journey_id
FROM federico_test.sensed_trips_2022_no_route trips
LEFT JOIN (
    SELECT DISTINCT ON (sensing_record_id) 
           sensing_record_id::INTEGER AS sensing_record_id,
           journey_id
    FROM federico_test.koppeltabel
    ORDER BY sensing_record_id, journey_id  
) koppel
ON trips.sensing_record_id = koppel.sensing_record_id;

CREATE INDEX idx_koppeltabel_sensing_journey
ON federico_test.koppeltabel (sensing_record_id, journey_id);

CREATE INDEX idx_trips_sensing
ON federico_test.sensed_trips_2022_no_route (sensing_record_id);

DROP TABLE IF EXISTS federico_test.sensed_trips_2022_no_route_koppel;
CREATE TABLE federico_test.sensed_trips_2022_no_route_koppel AS
SELECT trips.*,
       koppel.journey_id
FROM federico_test.sensed_trips_2022_no_route trips
LEFT JOIN (
    SELECT DISTINCT ON (sensing_record_id) 
           sensing_record_id::INTEGER AS sensing_record_id,
           journey_id
    FROM federico_test.koppeltabel
    ORDER BY sensing_record_id, journey_id  
) koppel
ON trips.sensing_record_id = koppel.sensing_record_id;

CREATE INDEX idx_koppeltabel_sensing_journey
ON federico_test.koppeltabel (sensing_record_id, journey_id);

CREATE INDEX idx_trips_sensing
ON federico_test.sensed_trips_2022_no_route (sensing_record_id);

DROP TABLE IF EXISTS federico_test.sensing_record_ervoor;
CREATE TABLE federico_test.sensing_record_ervoor AS
SELECT 
	trip.sensing_record_id,
	trip.trip_mode,
	trip_ervoor.sensing_record_id AS sensing_record_ervoor,
	trip_ervoor.trip_mode AS trip_mode_ervoor
FROM hb_stromen.stadion_od_locaties_journeydata trip
LEFT JOIN federico_test.sensed_trips_2022_no_route_koppel trip_ervoor
ON trip.journey_id = trip_ervoor.journey_id
AND trip.origin = trip_ervoor.destination; --werkt nog niet zie: sensing record 174544636, journey id 11695151425 */

--schema, tabelnaam, brontabel, vlakkentabel
/* SELECT bepaal_od_locaties_punten('hb_stromen', 'stadion_od_locaties_punten', 'osm.pois_stadion', 'stadion_od_locaties_vlakken'); -- niet meenemen (er is maar 1 punt, een drafcentrum) 
SELECT bepaal_od_locaties_punten('hb_stromen', 'gezondheid_od_locaties_punten', 'osm.pois_gezondheid', 'gezondheid_od_locaties_vlakken'); --alleen code 2210 meenemen
SELECT bepaal_od_locaties_punten('hb_stromen', 'cultuur_od_locaties_punten', 'osm.pois_cultuur', 'cultuur_od_locaties_vlakken'); --niet meenemen
SELECT bepaal_od_locaties_punten('hb_stromen', 'bisocoop_od_locaties_punten', 'osm.pois_bioscoop', 'bisocoop_od_locaties_vlakken'); --niet meenemen
SELECT bepaal_od_locaties_punten('hb_stromen', 'attractiepark_od_locaties_punten', 'osm.pois_attractiepark', 'attractiepark_od_locaties_vlakken'); --TODO LATER RUNNEN
SELECT bepaal_od_locaties_punten('hb_stromen', 'ijsbaan_od_locaties_punten', 'osm.pois_ijsbaan', 'ijsbaan_od_locaties_vlakken'); --niet meenemen
SELECT bepaal_od_locaties_punten('hb_stromen', 'sport_od_locaties_punten', 'osm.pois_sport', 'sport_od_locaties_vlakken'); --niet meenemen */

/* DROP TABLE IF EXISTS gezondheid_puntlocaties;
CREATE TABLE gezondheid_puntlocaties AS
WITH buffer_om_punt AS (
	SELECT *,
		ST_Transform(
			ST_Buffer(ST_Transform(geom, 28992), 50),
			4326
		) AS geom_buffer
	FROM osm.pois_gezondheid WHERE code = '2110'   
	)
	SELECT 
		od.*,
		buffer.geom_buffer AS geom_polygoon,
		buffer.name AS naam
	FROM nvp_2022.od_locations od
	JOIN (
		SELECT *,
			ST_Transform(geom_buffer, 28992) AS geom_buffer_28992
		FROM buffer_om_punt
	) buffer
	ON ST_Within(od.geom, buffer.geom_buffer_28992); */