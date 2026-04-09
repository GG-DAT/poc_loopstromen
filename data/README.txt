LOOPSTROMEN DATA PIPELINE


====================
NEDERLANDSE VERSIE
====================

Deze repository bevat een geospatiale dataverwerkingspipeline om loopnetwerkdata in Nederland te verrijken met omgevings- en infrastructuurgegevens.

De pipeline verwerkt nationale datasets (BGT, bestuurlijke grenzen, RDW/NWB-data en een oorspronkelijk OSM-loopnetwerkbestand) en genereert verrijkte datasets per provincie.

---

WAT DOET DIT PROJECT

De pipeline:
- Splitst nationale datasets per provincie
- Verrijkt loopnetwerkdata met:
  - Nabijheid van vegetatie
  - Nabijheid en type water
  - Wegkenmerken (via RDW/NWB)
- Produceert GeoPackages per provincie

---

PROJECTSTRUCTUUR

project-root/
│
├── loopstromen_pipeline.py
├── README_bilingual.txt
├── requirements.txt
│
└── data/
    ├── Geo/
    │   ├── bestuurlijkegrenzen_gpkg_2021.zip
    │   ├── bestuurlijkegrenzen.gpkg
    │   └── loopnetwerk_nl.gpkg
    │
    ├── BGT/
    │   ├── BGT_extract.zip
    │   └── bgt_extracted/
    │
    ├── RDW/
    │   ├── [RDW-invoerbestanden]
    │
    ├── Output/
    │   ├── [invoer- en uitvoerbestanden per provincie]
    │
    └── Output_BGT/
        ├── [BGT-bestanden per provincie die door de pipeline worden gemaakt]

---

EXACTE DATASTRUCTUUR VOOR EEN DATA ZIP

Zet deze bestanden en mappen in je data-zip:

1. data/Geo/bestuurlijkegrenzen_gpkg_2021.zip
   Bron: download met Nederlandse bestuurlijke grenzen
   Gebruikt voor: het bepalen van provinciegrenzen

2. data/Geo/bestuurlijkegrenzen.gpkg
   Bron: uitgepakt uit bovenstaande ZIP, of direct opgeslagen
   Gebruikt voor: het lezen van de laag 'provincies'

3. data/Geo/loopnetwerk_nl.gpkg
   Bron: oorspronkelijk OSM-loopnetwerkbestand
   Gebruikt voor: de basisinvoer van het netwerk

4. data/BGT/BGT_extract.zip
   Bron: nationale BGT-extractie
   Gebruikt voor: brondata over water en vegetatie

5. data/RDW/
   Bron: RDW / NWB-exportmap
   Gebruikt voor: verrijking met wegkenmerken

6. data/Output/
   Gebruikt voor: invoer en uitvoer per provincie

7. data/Output_BGT/
   Gebruikt voor: BGT-bestanden die door het script per provincie worden opgesplitst
   Deze map mag in het begin leeg zijn als je de pipeline die wilt laten aanmaken

---

GEBRUIK

Voorbeeld:

python loopstromen_pipeline.py extract-provinces
python loopstromen_pipeline.py split-bgt
python loopstromen_pipeline.py add-water --province gelderland

---

OUTPUT

data/Output/*_enriched_final.gpkg


====================
ENGLISH VERSION
====================

This repository contains a geospatial data processing pipeline used to enrich pedestrian network data in the Netherlands with environmental and infrastructural attributes.

The pipeline processes national datasets (BGT, administrative boundaries, RDW/NWB data, and an original OSM loopnetwerk file) and produces enriched datasets per province.

---

WHAT THIS PROJECT DOES

The pipeline:
- Splits national datasets into provinces
- Enriches pedestrian network data with:
  - Vegetation proximity
  - Water proximity and type
  - Road characteristics (via RDW/NWB)
- Outputs GeoPackages per province

---

PROJECT STRUCTURE

project-root/
│
├── loopstromen_pipeline.py
├── README_bilingual.txt
├── requirements.txt
│
└── data/
    ├── Geo/
    │   ├── bestuurlijkegrenzen_gpkg_2021.zip
    │   ├── bestuurlijkegrenzen.gpkg
    │   └── loopnetwerk_nl.gpkg
    │
    ├── BGT/
    │   ├── BGT_extract.zip
    │   └── bgt_extracted/
    │
    ├── RDW/
    │   ├── [RDW input files]
    │
    ├── Output/
    │   ├── [per-province input and output files]
    │
    └── Output_BGT/
        ├── [per-province BGT files created by the pipeline]

---

EXACT DATA FILES TO COLLECT IN A DATA ZIP

Put these files and folders inside your data zip:

1. data/Geo/bestuurlijkegrenzen_gpkg_2021.zip
   Source: Dutch administrative boundaries download
   Used for: extracting province boundaries

2. data/Geo/bestuurlijkegrenzen.gpkg
   Source: extracted from the ZIP above, or stored directly
   Used for: reading the layer 'provincies'

3. data/Geo/loopnetwerk_nl.gpkg
   Source: original OSM loopnetwerk file
   Used for: base network input

4. data/BGT/BGT_extract.zip
   Source: national BGT extract
   Used for: water and vegetation source data

5. data/RDW/
   Source: RDW / NWB export folder
   Used for: road-related enrichment

6. data/Output/
   Used for: province-level input and output files

7. data/Output_BGT/
   Used for: BGT files split per province by the script
   This folder can be empty initially if you want the pipeline to create it

---

USAGE

Example:

python loopstromen_pipeline.py extract-provinces
python loopstromen_pipeline.py split-bgt
python loopstromen_pipeline.py add-water --province gelderland

---

OUTPUT

data/Output/*_enriched_final.gpkg

---
