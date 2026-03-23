UPDATE stations_spectrum_ns
SET geometry = ST_SetSRID(geometry, 28992)
WHERE ST_SRID(geometry) = 0;

--- ALLE ONDERWIJSINSTELLINGEN PER POSTCODE 4 GEBIED (1147)
DROP TABLE IF EXISTS onderwijsinstellingen_koppeling_pc4;
CREATE TABLE onderwijsinstellingen_koppeling_pc4 AS
	SELECT 
		onderwijs.namen AS instellingsnaam,
		CASE
			WHEN onderwijs.leerlingen_middelbaarberoepsonderwijs > 0 
			THEN onderwijs.leerlingen_middelbaarberoepsonderwijs
			ELSE onderwijs.leerlingen_hogeronderwijs
		END AS aantal_leerlingen,
		CASE
			WHEN onderwijs.leerlingen_middelbaarberoepsonderwijs > 0 
			THEN 'mbo'
			ELSE 'ho'
		END AS onderwijstype,
		--onderwijs.leerlingen_middelbaarberoepsonderwijs,
		--onderwijs.leerlingen_hogeronderwijs,
		postcode.postcode,
		postcode.geometry AS postcode_geom,
		onderwijs.geometrie AS onderwijs_geom	
FROM pc4 postcode
JOIN public.d005_aantal_leerlingen_per_bag_adres onderwijs
ON ST_Contains(postcode.geometry, onderwijs.geometrie)
WHERE onderwijs.leerlingen_hogeronderwijs > 0 
OR onderwijs.leerlingen_middelbaarberoepsonderwijs > 0 
OR (onderwijs.leerlingen_hogeronderwijs > 0 AND onderwijs.leerlingen_middelbaarberoepsonderwijs > 0);

--- AANTAL ONDERWIJSINSTELLINGEN PER POSTCODE 4 GEBIED (508)
DROP TABLE IF EXISTS pc4_aantal_onderwijsinstellingen;
CREATE TABLE pc4_aantal_onderwijsinstellingen AS
	SELECT 
		postcode,
		COUNT(*) AS aantal_onderwijsinstellingen,
		STRING_AGG(DISTINCT onderwijstype, ', ') AS onderwijstypes,
		postcode_geom,
		ST_Centroid(ST_Collect(onderwijs_geom)) AS centrum_onderwijs_geom,
		ST_SetSRID(
			ST_MakePoint(
				SUM(ST_X(onderwijs_geom) * aantal_leerlingen) / SUM(aantal_leerlingen),
				SUM(ST_Y(onderwijs_geom) * aantal_leerlingen) / SUM(aantal_leerlingen)
			),
			ST_SRID(postcode_geom)  
		) AS centrum_onderwijs_gewogen_geom
FROM onderwijsinstellingen_koppeling_pc4
GROUP BY postcode, postcode_geom;

--- DICHTSBIJZIJNDE STATION PER POSTCODE 4 GEBIED (508)
DROP TABLE IF EXISTS pc4_aantal_onderwijsinstellingen_en_koppeling_stations;
CREATE TABLE pc4_aantal_onderwijsinstellingen_en_koppeling_stations AS
SELECT 
	postcode.postcode,
	postcode.aantal_onderwijsinstellingen,
	postcode.onderwijstypes,
    stations.station AS station_naam,
	stations.inuit,
	postcode_geom,
	centrum_onderwijs_gewogen_geom,
    stations.geometry AS station_geom,
    ST_Distance(
        ST_Transform(postcode.centrum_onderwijs_gewogen_geom, 4326)::geography,
        ST_Transform(stations.geometry, 4326)::geography
    ) AS afstand_centrum_onderwijs_station
FROM 
    public.pc4_aantal_onderwijsinstellingen postcode
JOIN LATERAL (
    SELECT 
        stations.station,
		stations."InUit2019" AS inuit,
        stations.geometry
    FROM 
        public.stations_spectrum_ns stations
    ORDER BY 
        postcode.centrum_onderwijs_gewogen_geom <-> stations.geometry
    LIMIT 1
) stations ON true;

--- AFSTAND TOT DICHTSBIJZIJNDE STATION (1147)
DROP TABLE IF EXISTS onderwijsinstellingen_koppeling_pc4_en_stations;
CREATE TABLE onderwijsinstellingen_koppeling_pc4_en_stations AS
WITH koppeling AS(
	SELECT 
		onderwijs.instellingsnaam,
		onderwijs.aantal_leerlingen,
		onderwijs.onderwijstype,
		onderwijs.postcode,
		pc4.aantal_onderwijsinstellingen,
		pc4.onderwijstypes,
		pc4.station_naam,
		pc4.inuit,
		pc4.afstand_centrum_onderwijs_station,
		ST_Distance(
			ST_Transform(onderwijs.onderwijs_geom, 4326)::geography,
			ST_Transform(pc4.station_geom, 4326)::geography
		) AS afstand_station,
		ST_Distance(
			ST_Transform(onderwijs.onderwijs_geom, 4326)::geography,
			ST_Transform(pc4.station_geom, 4326)::geography
		) * onderwijs.aantal_leerlingen AS afstand_station_keer_leerlingen,
		onderwijs.postcode_geom,
		onderwijs.onderwijs_geom,
		pc4.centrum_onderwijs_gewogen_geom,
		pc4.station_geom
	FROM onderwijsinstellingen_koppeling_pc4 onderwijs
	LEFT JOIN pc4_aantal_onderwijsinstellingen_en_koppeling_stations pc4
	USING(postcode)),
	gewogen_afstand AS(
		SELECT
			postcode,
			SUM(afstand_station_keer_leerlingen) / SUM(aantal_leerlingen) AS gewogen_afstand_station
		FROM koppeling
		GROUP BY postcode)
	SELECT 
		instellingsnaam,
		aantal_leerlingen,
		onderwijstypes,
		postcode,
		aantal_onderwijsinstellingen,
		station_naam,
		inuit,
		afstand_centrum_onderwijs_station,
		gewogen_afstand_station,
		afstand_station,
		postcode_geom,
		onderwijs_geom,
		centrum_onderwijs_gewogen_geom,
		station_geom	
	FROM koppeling
	LEFT JOIN gewogen_afstand USING(postcode)
	ORDER BY postcode;

--- PER POSTCODE 4 GEWOGEN AFSTAND TOT DICHTSBIJZIJNDE STATION 
DROP TABLE IF EXISTS pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand;
CREATE TABLE pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand AS
SELECT 
	DISTINCT ON (postcode.postcode)
	postcode.postcode,
	postcode.aantal_onderwijsinstellingen,
	postcode.onderwijstypes,
    postcode.station_naam,
	postcode.inuit,
	afstand.gewogen_afstand_station,
	afstand.afstand_centrum_onderwijs_station,
	postcode.postcode_geom,
	postcode.centrum_onderwijs_gewogen_geom,
    postcode.station_geom
FROM public.pc4_aantal_onderwijsinstellingen_en_koppeling_stations postcode
LEFT JOIN onderwijsinstellingen_koppeling_pc4_en_stations afstand USING (postcode);
	
-- SUBSETS VOOR DE PC4s DIE IN ODIN VOORKOMEN
DROP TABLE IF EXISTS pc4_odin_subset;
CREATE TABLE pc4_odin_subset AS
	SELECT 
	*
	FROM odin_aantallen odin 
	LEFT JOIN pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand pc4 
	ON pc4.postcode = CAST(odin.onderwijslocatie AS bigint);
	
DROP TABLE IF EXISTS pc4_odin_subset_incl_15_17;
CREATE TABLE pc4_odin_subset_incl_15_17 AS
	SELECT 
	*
	FROM odin_aantallen_incl_15_17 odin 
	LEFT JOIN pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand pc4 
	ON pc4.postcode = CAST(odin.onderwijslocatie AS bigint);

DROP TABLE IF EXISTS pc4_odin_subset_all;
CREATE TABLE pc4_odin_subset_all AS
	SELECT 
	*
	FROM odin_aantallen odin 
	LEFT JOIN pc4 pc4 
	ON pc4.postcode = CAST(odin.onderwijslocatie AS bigint);
	
-- SUBSETS VOOR DE PC4s DIE IN ODIN VOORKOMEN
DROP TABLE IF EXISTS pc4_odin_subset_trein_voet;
CREATE TABLE pc4_odin_subset_trein_voet AS
	SELECT 
	*
	FROM odin_aantallen_trein_voet odin 
	LEFT JOIN pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand pc4 
	ON pc4.postcode = CAST(odin.onderwijslocatie AS bigint);
	
	--er zitten postcode null's in -> geen onderwijs in spectrum
	
-- SUBSETS VOOR DE PC4s DIE IN ODIN VOORKOMEN
DROP TABLE IF EXISTS pc4_odin_subset_trein_voet_incl_15_17;
CREATE TABLE pc4_odin_subset_trein_voet_incl_15_17 AS
	SELECT 
	*
	FROM odin_aantallen_trein_voet_incl_15_17 odin 
	LEFT JOIN pc4_aantal_onderwijsinstellingen_en_koppeling_stations_incl_afstand pc4 
	ON pc4.postcode = CAST(odin.onderwijslocatie AS bigint);
	
-- ANALYSE OP PC4's MET 1 ONDERWIJSINSTELLING 
DROP TABLE IF EXISTS pc4_odin_subset_1_instelling;
CREATE TABLE pc4_odin_subset_1_instelling AS
	SELECT 
		postcode,
		gemiddelde_loopafstand,
		maximale_loopafstand,
		minimale_loopafstand,
		gewogen_afstand_station,
		aantal_trein_voet,
		onderwijsstation,
		station_naam,
		inuit,
		onderwijstypes,
		postcode_geom	
	FROM pc4_odin_subset odin
	WHERE aantal_onderwijsinstellingen = 1
	ORDER BY aantal_trein_voet DESC;
	
-- ANALYSE OP PC4's MET 1 ONDERWIJSINSTELLING 
DROP TABLE IF EXISTS pc4_odin_subset_trein_voet_1_instelling;
CREATE TABLE pc4_odin_subset_trein_voet_1_instelling AS
	SELECT 
		postcode,
		gemiddelde_loopafstand,
		maximale_loopafstand,
		minimale_loopafstand,
		gewogen_afstand_station,
		aantal_trein_voet,
		onderwijsstation,
		station_naam,
		inuit,
		onderwijstypes,
		postcode_geom	
	FROM pc4_odin_subset_trein_voet odin
	WHERE aantal_onderwijsinstellingen = 1
	ORDER BY aantal_trein_voet DESC;