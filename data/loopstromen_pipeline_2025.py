"""Loopstromen data pipeline.


What this pipeline does
-----------------------
1. Extract province boundary data from a ZIP file.
2. Extract national BGT source files (vegetation and water) from a ZIP file.
3. Split those national BGT files into one file per province.
4. Match OSM loopnetwerk links to NWB road segments.
5. Enrich loopnetwerk links with RDW attributes.
6. Add nearby vegetation counts and a dominant vegetation type.
7. Add a "vegetation per 100 m" indicator.
8. Add a dominant nearby water type.


Required data structure
-----------------------
Put all input and output data inside the "data" folder.

project_root/
    loopstromen_pipeline.py
    README_bilingual.txt
    data/
        Geo/
            bestuurlijkegrenzen_gpkg_2021.zip
                Source: Dutch administrative boundaries download.
                Used for: extracting province boundaries.
            bestuurlijkegrenzen.gpkg
                Source: extracted from the ZIP above, or added manually.
                Used for: reading the "provincies" layer during province-based processing.
            loopnetwerk_nl.gpkg
                Source: original OSM loopnetwerk dataset.
                Used for: the starting pedestrian/cycling network input before province-level enrichment.
        BGT/
            BGT_extract.zip
                Source: national BGT extract.
                Used for: finding vegetation objects and water bodies near network links.
            bgt_extracted/
                Source: created by this script after unzipping BGT_extract.zip.
                Used for: temporary extracted national BGT layers.
        RDW/
            [RDW input files]
                Source: RDW / NWB exports.
                Used for: adding road width, speed, crossings, and related road attributes.
        Output/
            [province output files]
                Used for: per-province loopnetwerk inputs and enriched outputs.
        Output_BGT/
            [province BGT files]
                Source: created by this script.
                Used for: storing BGT water and vegetation files split per province.

Important notes about filenames
-------------------------------
- The BGT ZIP file is expected to be named exactly: BGT_extract.zip
- The administrative boundary files are expected in: data/Geo/
- The RDW files are expected in: data/RDW/
- Province-level outputs are expected in: data/Output/
- Province-level split BGT files are written to: data/Output_BGT/

Example usage
-------------
python loopstromen_pipeline.py extract-provinces --project-root "/path/to/project_root"
python loopstromen_pipeline.py split-bgt --project-root "/path/to/project_root"
python loopstromen_pipeline.py match-nwb --project-root "/path/to/project_root" --provinces gelderland
python loopstromen_pipeline.py enrich-rdw --project-root "/path/to/project_root" --province gelderland
python loopstromen_pipeline.py add-vegetation --project-root "/path/to/project_root" --province gelderland
python loopstromen_pipeline.py add-veg-density --project-root "/path/to/project_root" --province gelderland
python loopstromen_pipeline.py add-water --project-root "/path/to/project_root" --province gelderland
"""

from __future__ import annotations

import argparse
import csv
import gc
import re
import shutil
import tempfile
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import fiona
import geopandas as gpd
import numpy as np
import pandas as pd
import pyproj
from shapely.ops import transform as shapely_transform

try:
    from shapely import make_valid as shapely_make_valid
except Exception:  # pragma: no cover - depends on local shapely version
    shapely_make_valid = None


METRIC_CRS = "EPSG:28992"  # Dutch RD New; convenient because distances are in metres.


@dataclass(frozen=True)
class ProjectPaths:
    """Convenient collection of commonly used project folders."""

    root: Path

    @property
    def data(self) -> Path:
        return self.root / "data"

    @property
    def geo(self) -> Path:
        return self.data / "Geo"

    @property
    def bgt(self) -> Path:
        return self.data / "BGT"

    @property
    def rdw(self) -> Path:
        return self.data / "RDW"

    @property
    def bgt_extracted(self) -> Path:
        return self.bgt / "bgt_extracted"

    @property
    def by_province(self) -> Path:
        return self.data / "Output"

    @property
    def by_province_bgt(self) -> Path:
        return self.data / "Output_BGT"


# -----------------------------------------------------------------------------
# Small utility functions
# -----------------------------------------------------------------------------

def slug(text: str) -> str:
    """Convert text into a simple folder/file friendly name."""
    return re.sub(r"[^a-z0-9_-]+", "_", text.strip().lower())


def slug_norm(text: str) -> str:
    """Normalize accents and punctuation so province names compare reliably."""
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9_-]+", "_", text.lower()).strip("_")


def canonical_slug(text: str) -> str:
    """Handle province names that may appear in more than one spelling."""
    aliases = {
        "friesland": "fryslan",
        "fryslan": "fryslan",
        "fryslan_": "fryslan",
        "fryslan__": "fryslan",
    }
    return aliases.get(slug_norm(text), slug_norm(text))


def ensure_metric_crs(gdf: gpd.GeoDataFrame, target_crs: str = METRIC_CRS) -> gpd.GeoDataFrame:
    """Ensure a GeoDataFrame uses the metric CRS expected by the project."""
    if gdf.crs is None:
        return gdf.set_crs(target_crs, allow_override=True)
    if str(gdf.crs).lower() != target_crs.lower():
        return gdf.to_crs(target_crs)
    return gdf


def get_source_crs(path: Path, layer: str | None = None):
    """Read CRS information from a vector file without loading all features."""
    with fiona.Env():
        with fiona.open(str(path), layer=layer) as src:
            return src.crs_wkt or src.crs


def transform_geometry(geom, from_crs, to_crs):
    """Reproject a single Shapely geometry from one CRS to another."""
    if geom is None or geom.is_empty:
        return geom
    transformer = pyproj.Transformer.from_crs(from_crs, to_crs, always_xy=True)
    return shapely_transform(transformer.transform, geom)


def make_valid_series(geo_series: gpd.GeoSeries) -> gpd.GeoSeries:
    """Repair invalid geometries as safely as possible.

    Spatial operations can fail when geometries are self-intersecting or broken.
    We first try shapely.make_valid(), and fall back to buffer(0) when needed.
    """
    if shapely_make_valid is not None:
        try:
            return geo_series.apply(shapely_make_valid)
        except Exception:
            pass
    return geo_series.buffer(0)


def read_first_layer(path: Path) -> gpd.GeoDataFrame:
    """Read the first layer from a spatial file.

    Many GeoPackage files in this project only have a single layer. This helper keeps
    the calling code short and makes the intent obvious.
    """
    if path.suffix.lower() == ".gpkg":
        layers = fiona.listlayers(str(path))
        return gpd.read_file(path, layer=layers[0])
    return gpd.read_file(path)


def find_existing_file(folder: Path, candidate_names: Sequence[str]) -> Path | None:
    """Return the first matching file from a list of possible names."""
    for name in candidate_names:
        candidate = folder / name
        if candidate.exists():
            return candidate
    return None


def pick_type_col(columns: Iterable[str]) -> str | None:
    """Pick the attribute column that contains the most likely type label."""
    lower_to_original = {c.lower(): c for c in columns}
    for candidate in (
        "plus-type",
        "plus_type",
        "plustype",
        "type",
        "watertype",
        "water_type",
    ):
        if candidate in lower_to_original:
            return lower_to_original[candidate]
    return None


def dominant_type(series: pd.Series):
    """Return the most common value with alphabetical tie-break.

    This makes the result deterministic: if two values occur equally often,
    the alphabetically first one is chosen.
    """
    values = series.dropna().astype(str)
    if values.empty:
        return pd.NA
    counts = values.value_counts()
    winners = sorted(counts[counts == counts.max()].index)
    return winners[0]


def canon_wvk(series: pd.Series) -> pd.Series:
    """Normalize road segment IDs so joins work across files with mixed types."""
    normalized = pd.to_numeric(series, errors="coerce").astype("Int64")
    return normalized.astype(str).replace({"<NA>": pd.NA})


def find_column_case_insensitive(df: pd.DataFrame, *candidates: str) -> str | None:
    """Find a column by name without caring about uppercase/lowercase."""
    lookup = {c.lower(): c for c in df.columns}
    for candidate in candidates:
        if candidate.lower() in lookup:
            return lookup[candidate.lower()]
    return None


def read_csv_flexible(path: Path) -> pd.DataFrame:
    """Read a CSV even when encoding or delimiter is inconsistent.

    Government datasets sometimes vary in separator and text encoding. This helper tries
    a few common combinations before giving up.
    """
    for encoding in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            with open(path, "r", encoding=encoding, errors="replace") as handle:
                sample = handle.read(8192)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters=",;\t|")
                sep = dialect.delimiter
            except csv.Error:
                sep = None
            frame = pd.read_csv(path, sep=sep, engine="python", encoding=encoding)
            frame.columns = [c.strip() for c in frame.columns]
            return frame
        except Exception:
            continue

    frame = pd.read_csv(path, engine="python")
    frame.columns = [c.strip() for c in frame.columns]
    return frame


def read_first_csv_from_zip(zip_path: Path) -> pd.DataFrame:
    """Read the first CSV file found inside a ZIP archive."""
    with zipfile.ZipFile(zip_path, "r") as zf, tempfile.TemporaryDirectory() as tmp_dir:
        csv_names = [name for name in zf.namelist() if name.lower().endswith(".csv")]
        if not csv_names:
            raise FileNotFoundError(f"No CSV file found inside {zip_path.name}")
        inner_name = csv_names[0]
        zf.extract(inner_name, tmp_dir)
        return read_csv_flexible(Path(tmp_dir) / inner_name)


def read_provinces(path: Path, layer: str = "provincies") -> gpd.GeoDataFrame:
    """Load province boundaries and reproject them to the project CRS."""
    layers = fiona.listlayers(str(path))
    if layer not in layers:
        raise ValueError(f"Layer '{layer}' not found in {path}. Available layers: {layers}")
    return ensure_metric_crs(gpd.read_file(path, layer=layer))


def read_by_bbox_then_clip(
    path: Path,
    layer: str | None,
    mask_geom_target_crs,
    keep_cols: Sequence[str] | None = None,
    buffer_m: int = 0,
    target_crs: str = METRIC_CRS,
) -> gpd.GeoDataFrame:
    """Read only the part of a large file that overlaps a province.

    Why this is useful:
    - national BGT files can be very large;
    - reading the whole file would be slow and memory-heavy;
    - using a bounding box first is faster;
    - clipping afterwards keeps only the exact province area.
    """
    src_crs = get_source_crs(path, layer) or target_crs
    mask = mask_geom_target_crs.buffer(buffer_m) if buffer_m else mask_geom_target_crs

    mask_src = transform_geometry(mask, from_crs=target_crs, to_crs=src_crs)
    if mask_src is None or mask_src.is_empty:
        return gpd.GeoDataFrame(geometry=[], crs=target_crs)

    gdf = gpd.read_file(path, layer=layer, bbox=mask_src.bounds)
    if gdf.empty:
        return gdf

    if keep_cols is not None:
        selected_cols = [c for c in keep_cols if c in gdf.columns]
        if "geometry" in gdf.columns and "geometry" not in selected_cols:
            selected_cols.append("geometry")
        if selected_cols:
            gdf = gdf[selected_cols]

    if gdf.crs is None:
        gdf = gdf.set_crs(src_crs, allow_override=True)
    if str(gdf.crs).lower() != target_crs.lower():
        gdf = gdf.to_crs(target_crs)

    gdf = gdf[gdf.geometry.notna() & (~gdf.geometry.is_empty)].copy()
    gdf.geometry = make_valid_series(gdf.geometry)

    valid_mask = shapely_make_valid(mask_geom_target_crs) if shapely_make_valid else mask_geom_target_crs.buffer(0)
    return gpd.clip(gdf, valid_mask)


def find_province_dir(project: ProjectPaths, province_slug: str, prefer_bgt: bool = False) -> Path:
    """Find the folder for one province.

    The original notebook used both 'by province' and 'by_province'. In this cleaned
    version we standardize on 'by_province', but we still check a few alternatives so
    older project folders continue to work.
    """
    possible_roots = [project.by_province_bgt, project.by_province] if prefer_bgt else [project.by_province, project.by_province_bgt]

    for root in possible_roots:
        if not root.exists():
            continue
        exact = root / province_slug
        if exact.exists():
            return exact
        for folder in root.iterdir():
            if folder.is_dir() and province_slug in folder.name.lower():
                return folder

    raise FileNotFoundError(f"Could not find province folder for '{province_slug}'")


# -----------------------------------------------------------------------------
# Step 1 - Extract province boundaries from ZIP
# -----------------------------------------------------------------------------

def extract_province_boundaries_from_zip(
    project: ProjectPaths,
    zip_name: str = "bestuurlijkegrenzen_gpkg_2021.zip",
    output_name: str = "bestuurlijkegrenzen.gpkg",
) -> Path:
    """Extract the province boundary GeoPackage from a ZIP archive."""
    zip_path = project.data / zip_name
    if not zip_path.exists():
        raise FileNotFoundError(f"Province ZIP not found: {zip_path}")

    temp_dir = project.root / "_tmp_province_boundaries"
    temp_dir.mkdir(parents=True, exist_ok=True)
    project.data.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(zip_path, "r") as zf:
        gpkg_names = [name for name in zf.namelist() if name.lower().endswith(".gpkg")]
        if not gpkg_names:
            raise FileNotFoundError(f"No .gpkg file found inside {zip_path.name}")
        first_gpkg = gpkg_names[0]
        extracted_path = temp_dir / Path(first_gpkg).name
        if not extracted_path.exists():
            zf.extract(first_gpkg, temp_dir)
            nested_path = temp_dir / first_gpkg
            if nested_path.exists() and nested_path != extracted_path:
                nested_path.rename(extracted_path)

    destination = project.data / output_name
    shutil.copy2(extracted_path, destination)
    print(f"Copied province boundaries to: {destination}")
    print(f"Layers: {fiona.listlayers(str(destination))}")
    return destination


# -----------------------------------------------------------------------------
# Step 2 - Extract and split national BGT files
# -----------------------------------------------------------------------------

def detect_and_extract_bgt_sources(
    bgt_zip: Path,
    extract_dir: Path,
) -> dict[str, dict[str, object]]:
    """Extract the national BGT source files needed later in the pipeline.

    Returns a dictionary that describes where the vegetation and water source files are.
    This structure is then reused by the province splitting step.
    """
    if not bgt_zip.exists():
        raise FileNotFoundError(f"BGT ZIP not found: {bgt_zip}")

    extract_dir.mkdir(parents=True, exist_ok=True)
    vegetation_path: Path | None = None
    water_paths: list[Path] = []

    with zipfile.ZipFile(bgt_zip, "r") as archive:
        names = archive.namelist()
        vegetation_candidates = [n for n in names if n.lower().endswith(".gml") and "vegetatie" in n.lower()]
        water_candidates = [n for n in names if n.lower().endswith(".gml") and "waterdeel" in n.lower()]

        def extract_member(member_name: str) -> Path:
            output = extract_dir / Path(member_name).name
            if not output.exists():
                archive.extract(member_name, extract_dir)
                nested = extract_dir / member_name
                if nested.exists() and nested != output and nested.is_file():
                    nested.rename(output)
            return output

        if vegetation_candidates:
            # Use the largest vegetation file; usually that is the national layer we need.
            ranked = sorted(
                ((name, archive.getinfo(name).file_size) for name in vegetation_candidates),
                key=lambda item: item[1],
                reverse=True,
            )
            vegetation_path = extract_member(ranked[0][0])

        for water_name in water_candidates:
            water_paths.append(extract_member(water_name))

    datasets: dict[str, dict[str, object]] = {}
    if vegetation_path and vegetation_path.exists():
        datasets["bgt_vegetatie"] = {
            "paths": [vegetation_path],
            "layer": None,
            "cols": ["plus-type", "geometry"],
            "buffer_m": 2000,
        }
    if water_paths:
        datasets["bgt_water"] = {
            "paths": water_paths,
            "layer": None,
            "cols": ["plus-type", "geometry"],
            "buffer_m": 5000,
        }

    if not datasets:
        raise FileNotFoundError("Could not detect suitable BGT vegetation/water GML files in the ZIP archive")

    return datasets


def split_bgt_by_province(
    project: ProjectPaths,
    province_gpkg: Path | None = None,
    province_layer: str = "provincies",
    bgt_zip_name: str = "BGT_extract.zip",
    output_root: Path | None = None,
    skip_existing: bool = True,
) -> None:
    """Split national BGT source files into one output file per province."""
    province_gpkg = province_gpkg or (project.data / "bestuurlijkegrenzen.gpkg")
    output_root = output_root or project.by_province_bgt
    output_root.mkdir(parents=True, exist_ok=True)

    datasets = detect_and_extract_bgt_sources(project.data / bgt_zip_name, project.bgt_extracted)
    provinces = read_provinces(province_gpkg, province_layer)
    name_col = next(
        (c for c in provinces.columns if c.lower() in {"provincienaam", "naam", "name", "provincie"}),
        provinces.columns[0],
    )

    print(f"Splitting BGT data for {len(provinces)} provinces...")
    for _, row in provinces.iterrows():
        province_name = str(row[name_col])
        province_geom = row.geometry
        province_slug = slug(province_name)
        province_output = output_root / province_slug
        province_output.mkdir(parents=True, exist_ok=True)

        print(f"\nProcessing province: {province_name}")
        for dataset_name, config in datasets.items():
            out_file = province_output / f"{province_slug}_{dataset_name}.gpkg"
            if skip_existing and out_file.exists():
                print(f"  - {dataset_name}: skipped (already exists)")
                continue

            parts: list[gpd.GeoDataFrame] = []
            for src_path in config["paths"]:
                part = read_by_bbox_then_clip(
                    path=src_path,
                    layer=config["layer"],
                    mask_geom_target_crs=province_geom,
                    keep_cols=config.get("cols"),
                    buffer_m=int(config.get("buffer_m", 0)),
                )
                if not part.empty:
                    parts.append(part)

            if not parts:
                print(f"  - {dataset_name}: no overlapping features found")
                continue

            combined = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True), crs=METRIC_CRS)
            if out_file.exists():
                out_file.unlink()
            combined.to_file(out_file, driver="GPKG", layer=dataset_name, index=False)
            print(f"  - {dataset_name}: wrote {len(combined):,} features to {out_file.name}")
            del combined
            gc.collect()


def recut_bgt_for_province(
    project: ProjectPaths,
    province_name: str,
    province_gpkg: Path | None = None,
    province_layer: str = "provincies",
) -> None:
    """Overwrite one province's BGT files using the already extracted national files.

    The original notebook used this as a repair step for provinces whose earlier output
    looked incomplete. Keeping it as a separate function makes that repair explicit.
    """
    province_gpkg = province_gpkg or (project.data / "bestuurlijkegrenzen.gpkg")
    datasets = detect_and_extract_bgt_sources(project.data / "BGT_extract.zip", project.bgt_extracted)
    provinces = read_provinces(province_gpkg, province_layer)
    name_col = next(
        (c for c in provinces.columns if c.lower() in {"provincienaam", "naam", "name", "provincie"}),
        provinces.columns[0],
    )

    province_row = provinces[provinces[name_col].astype(str).str.lower() == province_name.lower()]
    if len(province_row) != 1:
        raise ValueError(f"Province not found or ambiguous: {province_name}")

    province_geom = province_row.iloc[0].geometry
    province_slug = slug(str(province_row.iloc[0][name_col]))
    province_output = project.by_province_bgt / province_slug
    province_output.mkdir(parents=True, exist_ok=True)

    print(f"Re-cutting province: {province_name}")
    for dataset_name, config in datasets.items():
        parts: list[gpd.GeoDataFrame] = []
        for src_path in config["paths"]:
            part = read_by_bbox_then_clip(
                path=src_path,
                layer=config["layer"],
                mask_geom_target_crs=province_geom,
                keep_cols=config.get("cols"),
                buffer_m=int(config.get("buffer_m", 0)),
            )
            if not part.empty:
                parts.append(part)

        out_file = province_output / f"{province_slug}_{dataset_name}.gpkg"
        if out_file.exists():
            out_file.unlink()

        if not parts:
            print(f"  - {dataset_name}: no features found")
            continue

        combined = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True), crs=METRIC_CRS)
        combined.to_file(out_file, driver="GPKG", layer=dataset_name, index=False)
        print(f"  - {dataset_name}: wrote {len(combined):,} features")


def audit_bgt_outputs(
    project: ProjectPaths,
    province_gpkg: Path | None = None,
    province_layer: str = "provincies",
) -> pd.DataFrame:
    """Create a simple QA table for per-province BGT outputs."""
    province_gpkg = province_gpkg or (project.data / "bestuurlijkegrenzen.gpkg")
    provinces = read_provinces(province_gpkg, province_layer)
    name_col = next(
        (c for c in provinces.columns if c.lower() in {"provincienaam", "naam", "name", "provincie"}),
        provinces.columns[0],
    )

    dataset_patterns = {
        "bgt_vegetatie": ["{slug}_bgt_vegetatie.gpkg", "bgt_vegetatie.gpkg"],
        "bgt_water": ["{slug}_bgt_water.gpkg", "bgt_water.gpkg"],
    }

    rows: list[dict[str, object]] = []
    for _, row in provinces.iterrows():
        province_name = str(row[name_col])
        province_slug = canonical_slug(province_name)
        province_geom = row.geometry

        try:
            province_dir = find_province_dir(project, province_slug, prefer_bgt=True)
        except FileNotFoundError:
            rows.append({"province": province_name, "dataset": "(folder)", "ok": False, "message": "missing folder"})
            continue

        for dataset_name, patterns in dataset_patterns.items():
            resolved_patterns = [pattern.format(slug=province_slug) for pattern in patterns]
            path = find_existing_file(province_dir, resolved_patterns)
            if path is None:
                rows.append({"province": province_name, "dataset": dataset_name, "ok": False, "message": "file missing"})
                continue

            try:
                gdf = ensure_metric_crs(read_first_layer(path))
                centroid_inside_pct = round(float(gdf.geometry.centroid.within(province_geom).mean() * 100), 2) if len(gdf) else np.nan
                rows.append(
                    {
                        "province": province_name,
                        "dataset": dataset_name,
                        "ok": True,
                        "message": "ok",
                        "rows": len(gdf),
                        "crs": str(gdf.crs),
                        "geom_types": dict(gdf.geom_type.value_counts()),
                        "pct_centroid_inside": centroid_inside_pct,
                    }
                )
            except Exception as exc:
                rows.append({"province": province_name, "dataset": dataset_name, "ok": False, "message": str(exc)})

    result = pd.DataFrame(rows).sort_values(["province", "dataset"]).reset_index(drop=True)
    return result


# -----------------------------------------------------------------------------
# Step 3.1 - Match loopnetwerk links to NWB road segments
# -----------------------------------------------------------------------------

def match_loopnetwerk_to_nwb(
    project: ProjectPaths,
    provinces: Sequence[str] | None = None,
    buffer_distance: int = 20,
) -> None:
    """Match OSM loopnetwerk links to NWB road segments using buffered overlap.

    This creates two outputs per province:
    - matches_loop_nwb.gpkg : all candidate matches from the spatial join;
    - best_loop_nwb.gpkg    : exactly one best NWB match per loop link.
    """
    province_root = project.by_province
    if not province_root.exists():
        raise FileNotFoundError(f"Province folder does not exist: {province_root}")

    province_dirs = sorted([p for p in province_root.iterdir() if p.is_dir()])
    if provinces:
        wanted = {slug(p) for p in provinces}
        province_dirs = [p for p in province_dirs if slug(p.name) in wanted or any(w in slug(p.name) for w in wanted)]

    if not province_dirs:
        raise RuntimeError("No matching province folders found")

    keep_loop = ["link", "pedtype", "length", "geometry"]
    keep_nwb = ["wvk_id", "st_lengthshape", "geometry"]

    for province_dir in province_dirs:
        print(f"\nMatching NWB for province: {province_dir.name}")
        loop_path = find_existing_file(province_dir, ["loopnetwerk_nl.gpkg", f"{province_dir.name}_loopnetwerk_nl.gpkg"])
        nwb_path = find_existing_file(province_dir, ["wegvakken.gpkg", f"{province_dir.name}_wegvakken.gpkg", "nwb_wegen.gpkg"])

        if loop_path is None or nwb_path is None:
            print("  - Missing loopnetwerk_nl.gpkg or wegvakken.gpkg; skipping")
            continue

        loop = ensure_metric_crs(read_first_layer(loop_path))
        nwb = ensure_metric_crs(read_first_layer(nwb_path))

        loop = loop[[c for c in keep_loop if c in loop.columns]].copy()
        nwb = nwb[[c for c in keep_nwb if c in nwb.columns]].copy()

        loop["buffer_link"] = loop.geometry.buffer(buffer_distance)
        nwb["buffer_nwb"] = nwb.geometry.buffer(buffer_distance)

        loop_buffered = loop.set_geometry("buffer_link")
        nwb_buffered = nwb[[c for c in ["wvk_id", "st_lengthshape", "buffer_nwb"] if c in nwb.columns]].copy().set_geometry("buffer_nwb")
        nwb_buffered["buffer_nwb_copy"] = nwb_buffered.geometry

        joined = gpd.sjoin(loop_buffered, nwb_buffered, how="left", predicate="intersects")

        if "link" in joined.columns:
            joined["link"] = pd.to_numeric(joined["link"], errors="coerce").astype("Int64")
        if "wvk_id" in joined.columns:
            joined["wvk_id"] = pd.to_numeric(joined["wvk_id"], errors="coerce").astype("Int64")

        joined["overlap_area"] = joined.apply(
            lambda row: row["buffer_link"].intersection(row["buffer_nwb_copy"]).area if pd.notna(row.get("buffer_nwb_copy")) else 0.0,
            axis=1,
        )
        joined["link_buffer_area"] = joined["buffer_link"].area
        joined["nwb_buffer_area"] = joined["buffer_nwb_copy"].apply(lambda geom: geom.area if geom is not None else 0.0)
        joined["link_overlap_ratio"] = np.where(
            joined["link_buffer_area"] > 0,
            joined["overlap_area"] / joined["link_buffer_area"],
            0.0,
        )
        joined["wegvak_overlap_ratio"] = np.where(
            joined["nwb_buffer_area"] > 0,
            joined["overlap_area"] / joined["nwb_buffer_area"],
            0.0,
        )

        matches_out = province_dir / "matches_loop_nwb.gpkg"
        matches_to_save = joined.copy().set_geometry("geometry")
        matches_to_save = matches_to_save.drop(columns=[c for c in ["buffer_link", "buffer_nwb_copy"] if c in matches_to_save.columns], errors="ignore")
        if matches_out.exists():
            matches_out.unlink()
        matches_to_save.to_file(matches_out, driver="GPKG", layer="matches", index=False)

        ranked = joined.copy()
        ranked["__lor__"] = ranked["link_overlap_ratio"].fillna(-1)
        ranked["__wor__"] = ranked["wegvak_overlap_ratio"].fillna(-1)
        ranked["__area__"] = ranked["overlap_area"].fillna(-1)
        if {"st_lengthshape", "length"}.issubset(ranked.columns):
            ranked["__len_diff__"] = (ranked["st_lengthshape"] - ranked["length"]).abs()
        else:
            ranked["__len_diff__"] = np.inf

        best = (
            ranked.sort_values(
                ["link", "__lor__", "__wor__", "__area__", "__len_diff__"],
                ascending=[True, False, False, False, True],
            )
            .drop_duplicates(subset="link", keep="first")
            .reset_index(drop=True)
        )
        best = best.drop(columns=[c for c in ["__lor__", "__wor__", "__area__", "__len_diff__", "buffer_link", "buffer_nwb_copy"] if c in best.columns], errors="ignore")
        best = best.set_geometry("geometry")

        best_out = province_dir / "best_loop_nwb.gpkg"
        if best_out.exists():
            best_out.unlink()
        best.to_file(best_out, driver="GPKG", layer="best", index=False)

        matched_count = int(best["wvk_id"].notna().sum()) if "wvk_id" in best.columns else 0
        print(f"  - Saved {matches_out.name} and {best_out.name}")
        print(f"  - Matched {matched_count:,} of {len(best):,} loopnetwerk links")

        del loop, nwb, loop_buffered, nwb_buffered, joined, matches_to_save, ranked, best
        gc.collect()


# -----------------------------------------------------------------------------
# Step 3.2 - Add RDW attributes to loopnetwerk
# -----------------------------------------------------------------------------

def enrich_loopnetwerk_with_rdw(project: ProjectPaths, province: str) -> Path:
    """Merge RDW attributes into the per-province loopnetwerk layer."""
    province_slug = slug(province)
    province_dir = find_province_dir(project, province_slug)

    loop_path = find_existing_file(province_dir, ["loopnetwerk_nl.gpkg", f"{province_dir.name}_loopnetwerk_nl.gpkg"])
    best_nwb_path = province_dir / "best_loop_nwb.gpkg"
    if loop_path is None:
        raise FileNotFoundError(f"Could not find loopnetwerk file in {province_dir}")
    if not best_nwb_path.exists():
        raise FileNotFoundError(f"Missing {best_nwb_path}. Run the NWB matching step first.")

    loop = ensure_metric_crs(read_first_layer(loop_path))
    best_nwb = ensure_metric_crs(read_first_layer(best_nwb_path))

    keep_loop = [c for c in ["link", "pedtype", "length", "geometry"] if c in loop.columns]
    loop = loop[keep_loop].copy()
    loop["link"] = loop["link"].astype(str)

    nwb_cols = [c for c in ["link", "wvk_id", "link_overlap_ratio", "wegvak_overlap_ratio"] if c in best_nwb.columns]
    best_nwb = best_nwb[nwb_cols].copy()
    best_nwb["link"] = best_nwb["link"].astype(str)
    if {"link", "link_overlap_ratio"}.issubset(best_nwb.columns):
        best_nwb = best_nwb.sort_values(["link", "link_overlap_ratio"], ascending=[True, False]).drop_duplicates("link")
    else:
        best_nwb = best_nwb.drop_duplicates("link")

    enriched = loop.merge(best_nwb, on="link", how="left", validate="one_to_one")
    enriched["wvk_key"] = canon_wvk(enriched["wvk_id"])

    width_path = project.rdw / "wkd_036-WEGBRDTV2.csv"
    if width_path.exists():
        width = read_csv_flexible(width_path)
        wvk_col = find_column_case_insensitive(width, "wvk_id")
        width_col = find_column_case_insensitive(width, "breedte")
        if wvk_col and width_col:
            width["wvk_key"] = canon_wvk(width[wvk_col])
            width_small = width[["wvk_key", width_col]].rename(columns={width_col: "wegbreedte"})
            width_small["wegbreedte"] = width_small["wegbreedte"].replace({"WaardeOnbekend": "onbekend"})
            enriched = enriched.merge(width_small.drop_duplicates("wvk_key"), on="wvk_key", how="left")

    speed_zip = project.rdw / "max_snelheid_01-01-2023.zip"
    if speed_zip.exists():
        speed = read_first_csv_from_zip(speed_zip)
        wvk_col = find_column_case_insensitive(speed, "wvk_id")
        speed_col = (
            find_column_case_insensitive(speed, "hde_sht")
            or find_column_case_insensitive(speed, "hde")
            or find_column_case_insensitive(speed, "hde_snelheid")
        )
        if wvk_col and speed_col:
            speed["wvk_key"] = canon_wvk(speed[wvk_col])
            speed_small = speed[["wvk_key", speed_col]].rename(columns={speed_col: "max_snelheid"})
            enriched = enriched.merge(speed_small.drop_duplicates("wvk_key"), on="wvk_key", how="left")

    crossing_ids: set[str] = set()
    for name in ["wkd_024-OVERSTKLOC.csv", "wkd_025-Voetgangesoversteekplaats.csv"]:
        path = project.rdw / name
        if path.exists():
            frame = read_csv_flexible(path)
            wvk_col = find_column_case_insensitive(frame, "wvk_id")
            if wvk_col:
                crossing_ids |= set(canon_wvk(frame[wvk_col]).dropna())

    has_key = enriched["wvk_key"].notna()
    enriched["Oversteekplaats"] = pd.Series(pd.NA, index=enriched.index, dtype="object")
    enriched.loc[has_key, "Oversteekplaats"] = "Nee"
    if crossing_ids:
        enriched.loc[has_key & enriched["wvk_key"].isin(crossing_ids), "Oversteekplaats"] = "Ja"

    out_path = province_dir / f"{province_slug}_loopnetwerk_enriched.gpkg"
    if out_path.exists():
        out_path.unlink()
    enriched.to_file(out_path, driver="GPKG", layer="enriched", index=False)
    print(f"Saved RDW-enriched loopnetwerk to: {out_path}")
    return out_path


# -----------------------------------------------------------------------------
# Step 4.1 - Add vegetation counts and a dominant type
# -----------------------------------------------------------------------------

def add_vegetation_to_loopnetwerk(project: ProjectPaths, province: str, buffer_m: int = 20) -> Path:
    """Count nearby vegetation features per loop link and add the dominant type."""
    province_slug = slug(province)
    province_dir = find_province_dir(project, province_slug)

    enriched_in = province_dir / f"{province_slug}_loopnetwerk_enriched.gpkg"
    vegetation_path = find_existing_file(province_dir, [f"{province_slug}_bgt_vegetatie.gpkg", "bgt_vegetatie.gpkg"])
    if not enriched_in.exists():
        raise FileNotFoundError(f"Missing input file: {enriched_in}")
    if vegetation_path is None:
        raise FileNotFoundError(f"Could not find vegetation file in {province_dir}")

    enriched = ensure_metric_crs(read_first_layer(enriched_in))
    vegetation = ensure_metric_crs(read_first_layer(vegetation_path))
    enriched["link"] = enriched["link"].astype(str)

    buffers = gpd.GeoDataFrame({"link": enriched["link"]}, geometry=enriched.geometry.buffer(buffer_m), crs=enriched.crs)
    vegetation = vegetation[vegetation.geometry.notna()].copy()
    vegetation.geometry = make_valid_series(vegetation.geometry)
    type_col = pick_type_col(vegetation.columns)

    hits = gpd.sjoin(
        buffers[["link", "geometry"]],
        vegetation[["geometry", type_col]] if type_col else vegetation[["geometry"]],
        how="inner",
        predicate="intersects",
    )

    veg_count_all = pd.Series(0, index=enriched["link"], dtype="int64")
    if not hits.empty:
        counts = hits.groupby("link").size().astype("int64")
        veg_count_all.loc[counts.index] = counts.values

    vegetation_type = pd.Series(pd.NA, index=enriched["link"], dtype="object")
    if type_col and not hits.empty:
        votes = hits[["link", type_col]].dropna().copy()
        if not votes.empty:
            counts = votes.groupby(["link", type_col]).size().reset_index(name="n")
            counts = counts.sort_values(["link", "n", type_col], ascending=[True, False, True])
            winners = counts.drop_duplicates("link", keep="first")
            vegetation_type.loc[winners["link"]] = winners[type_col].values

    out = enriched.copy()
    out["veg_count_all"] = veg_count_all.values
    out["vegetatie_type"] = vegetation_type.values

    out_path = province_dir / f"{province_slug}_loopnetwerk_enriched2.gpkg"
    if out_path.exists():
        out_path.unlink()
    out.to_file(out_path, driver="GPKG", layer="enriched", index=False)
    print(f"Saved vegetation-enriched loopnetwerk to: {out_path}")
    return out_path


# -----------------------------------------------------------------------------
# Step 4.2 - Add vegetation density per 100 metres
# -----------------------------------------------------------------------------

def add_vegetation_density(project: ProjectPaths, province: str) -> Path:
    """Create the integer indicator 'veg_per_100m' from counts and link length."""
    province_slug = slug(province)
    province_dir = find_province_dir(project, province_slug)
    enriched_path = province_dir / f"{province_slug}_loopnetwerk_enriched2.gpkg"
    if not enriched_path.exists():
        raise FileNotFoundError(f"Missing input file: {enriched_path}")

    gdf = ensure_metric_crs(read_first_layer(enriched_path))
    if "veg_count_all" not in gdf.columns:
        raise KeyError("Column 'veg_count_all' is missing")
    if "length" not in gdf.columns:
        raise KeyError("Column 'length' is missing")

    lengths = pd.to_numeric(gdf["length"], errors="coerce").replace(0, np.nan)
    counts = pd.to_numeric(gdf["veg_count_all"], errors="coerce").fillna(0)
    veg_per_100m_float = ((counts / lengths) * 100).fillna(0)

    # The original notebook explicitly avoided banker's rounding.
    gdf["veg_per_100m"] = np.floor(veg_per_100m_float + 0.5).astype("int32")

    if enriched_path.exists():
        enriched_path.unlink()
    gdf.to_file(enriched_path, driver="GPKG", layer="enriched", index=False)
    print(f"Updated vegetation density in: {enriched_path}")
    return enriched_path


# -----------------------------------------------------------------------------
# Step 5.1 - Add dominant nearby water type
# -----------------------------------------------------------------------------

def add_water_to_loopnetwerk(project: ProjectPaths, province: str, buffer_m: int = 20) -> Path:
    """Add one dominant nearby water type to each loop link."""
    province_slug = slug(province)
    province_dir = find_province_dir(project, province_slug)

    enriched_path = province_dir / f"{province_slug}_loopnetwerk_enriched2.gpkg"
    water_path = find_existing_file(province_dir, [f"{province_slug}_bgt_water.gpkg", "bgt_water.gpkg"])
    if not enriched_path.exists():
        raise FileNotFoundError(f"Missing input file: {enriched_path}")
    if water_path is None:
        raise FileNotFoundError(f"Could not find water file in {province_dir}")

    loop = ensure_metric_crs(read_first_layer(enriched_path))
    water = ensure_metric_crs(read_first_layer(water_path))
    if "link" not in loop.columns:
        loop = loop.reset_index().rename(columns={"index": "link"})
    loop["link"] = loop["link"].astype(str)

    type_col = pick_type_col(water.columns)
    if type_col is None:
        raise KeyError(f"Could not find a water type column in {water_path.name}")

    buffers = gpd.GeoDataFrame({"link": loop["link"]}, geometry=loop.geometry.buffer(buffer_m), crs=loop.crs)
    water = water[water.geometry.notna()].copy()

    hits = gpd.sjoin(water[["geometry", type_col]], buffers[["link", "geometry"]], how="inner", predicate="intersects")

    if hits.empty:
        grouped = pd.Series(dtype="object", name="water_type")
        links_with_hits = pd.Index([], dtype="object")
    else:
        grouped = hits.groupby("link")[type_col].agg(dominant_type).rename("water_type")
        links_with_hits = pd.Index(hits["link"].astype(str).unique())

    if "water_type" in loop.columns:
        loop = loop.rename(columns={"water_type": "water_type_old"})

    loop_final = loop.merge(grouped, on="link", how="left")
    loop_final["water_type"] = loop_final["water_type"].astype("string")

    unnamed_mask = loop_final["water_type"].str.lower().eq("waardeonbekend")
    loop_final.loc[unnamed_mask, "water_type"] = "Water (unnamed)"
    loop_final.loc[loop_final["link"].isin(links_with_hits) & loop_final["water_type"].isna(), "water_type"] = "Water (unnamed)"

    out_path = province_dir / f"{province_slug}_loopnetwerk_enriched_final.gpkg"
    if out_path.exists():
        out_path.unlink()
    loop_final.to_file(out_path, driver="GPKG", layer="enriched_final", index=False)
    print(f"Saved final loopnetwerk output to: {out_path}")
    return out_path


# -----------------------------------------------------------------------------
# Command-line interface
# -----------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    """Create the command-line interface for the script."""
    parser = argparse.ArgumentParser(description="Loopstromen geospatial data pipeline")
    parser.add_argument("--project-root", required=True, help="Path to the project root folder")

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("extract-provinces", help="Extract province boundaries from ZIP")
    subparsers.add_parser("split-bgt", help="Extract national BGT files and split them by province")

    recut = subparsers.add_parser("recut-bgt", help="Rebuild BGT files for one province from national source files")
    recut.add_argument("--province", required=True, help="Province name, for example Utrecht or Flevoland")

    subparsers.add_parser("audit-bgt", help="Create a QA table for per-province BGT outputs")

    match_nwb = subparsers.add_parser("match-nwb", help="Match loopnetwerk links to NWB road segments")
    match_nwb.add_argument("--provinces", nargs="*", help="Optional list of province names/slugs")
    match_nwb.add_argument("--buffer-distance", type=int, default=20, help="Buffer distance in metres")

    enrich_rdw = subparsers.add_parser("enrich-rdw", help="Merge RDW attributes into loopnetwerk")
    enrich_rdw.add_argument("--province", required=True, help="Province slug, for example gelderland")

    add_veg = subparsers.add_parser("add-vegetation", help="Add nearby vegetation counts and a type")
    add_veg.add_argument("--province", required=True)
    add_veg.add_argument("--buffer-distance", type=int, default=20)

    add_veg_density = subparsers.add_parser("add-veg-density", help="Add vegetation per 100 metres")
    add_veg_density.add_argument("--province", required=True)

    add_water = subparsers.add_parser("add-water", help="Add dominant nearby water type")
    add_water.add_argument("--province", required=True)
    add_water.add_argument("--buffer-distance", type=int, default=20)

    return parser


def main() -> None:
    """Parse command-line arguments and run the requested pipeline step."""
    parser = build_parser()
    args = parser.parse_args()
    project = ProjectPaths(root=Path(args.project_root))

    if args.command == "extract-provinces":
        extract_province_boundaries_from_zip(project)
    elif args.command == "split-bgt":
        split_bgt_by_province(project)
    elif args.command == "recut-bgt":
        recut_bgt_for_province(project, province_name=args.province)
    elif args.command == "audit-bgt":
        audit = audit_bgt_outputs(project)
        output_path = project.root / "bgt_audit.csv"
        audit.to_csv(output_path, index=False)
        print(f"Saved audit table to: {output_path}")
    elif args.command == "match-nwb":
        match_loopnetwerk_to_nwb(project, provinces=args.provinces, buffer_distance=args.buffer_distance)
    elif args.command == "enrich-rdw":
        enrich_loopnetwerk_with_rdw(project, province=args.province)
    elif args.command == "add-vegetation":
        add_vegetation_to_loopnetwerk(project, province=args.province, buffer_m=args.buffer_distance)
    elif args.command == "add-veg-density":
        add_vegetation_density(project, province=args.province)
    elif args.command == "add-water":
        add_water_to_loopnetwerk(project, province=args.province, buffer_m=args.buffer_distance)
    else:  # pragma: no cover - argparse should prevent this.
        parser.error(f"Unknown command: {args.command}")


if __name__ == "__main__":
    main()
