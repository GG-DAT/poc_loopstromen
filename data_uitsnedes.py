# -*- coding: utf-8 -*-
"""
Created on Tue Mar  4 16:36:28 2025

@author: tthomas
"""

import numpy as np
import geopandas as gpd
import pandas as pd
from shapely.geometry import Point
from shapely.ops import linemerge
from shapely.geometry import LineString, MultiLineString

cases = {
    'flevoland': {
        'HBO_Almere': [143519, 487324],
        'Almere_Haven': [143482, 483429]
    },
    'noord-holland': {
        'VU': [119406, 483319],
        'NEMO': [122305, 487703]
    }
}

# ====== instellingen ======
rbuffer = 3000  # meter (pas aan)
snap = 0.01    # meter (0.01 = 1 cm)


def get_endpoints(geom):
    """
    Return (x1,y1,x2,y2) for LineString / MultiLineString.
    For MultiLineString: try linemerge; if still multipart, take longest part.
    """
    if geom is None or geom.is_empty:
        return None

    gtype = geom.geom_type

    if gtype == "LineString":
        coords = list(geom.coords)
        return coords[0][0], coords[0][1], coords[-1][0], coords[-1][1]

    if gtype == "MultiLineString":
        merged = linemerge(geom)
        # linemerge kan LineString of MultiLineString teruggeven
        if merged.geom_type == "LineString":
            coords = list(merged.coords)
            return coords[0][0], coords[0][1], coords[-1][0], coords[-1][1]
        elif merged.geom_type == "MultiLineString":
            # kies het langste deel
            longest = max(list(merged.geoms), key=lambda g: g.length)
            coords = list(longest.coords)
            return coords[0][0], coords[0][1], coords[-1][0], coords[-1][1]

    raise NotImplementedError(f"Unsupported geometry type for endpoints: {gtype}")

def snap_xy(x, y, snap=0.01):
    # snap op 0.01 m
    xs = round(x / snap) * snap
    ys = round(y / snap) * snap
    # voorkom float-ruis in dictionary keys
    return (float(f"{xs:.2f}"), float(f"{ys:.2f}"))


def process_case(gdf_links, center_xy, rbuffer, snap=0.01):
    """
    Input: gdf_links met kolommen ['link','geometry'] (projected CRS, meters)
    Output: (gdf_links_sel, gdf_nodes_sel)
    """
    # lengte
    gdf = gdf_links[['link', 'geometry']].copy()
    gdf["lengte"] = gdf.geometry.length

    # endpoints per link -> snapped coords
    # node1 = startpunt, node2 = eindpunt
    node1_xy = []
    node2_xy = []

    for geom in gdf.geometry:
        ep = get_endpoints(geom)
        if ep is None:
            node1_xy.append(None)
            node2_xy.append(None)
            continue

        x1, y1, x2, y2 = ep
        node1_xy.append(snap_xy(x1, y1, snap=snap))
        node2_xy.append(snap_xy(x2, y2, snap=snap))

    gdf["node1_xy"] = node1_xy
    gdf["node2_xy"] = node2_xy

    # (optioneel) drop links met missende endpoints (lege geometrie etc.)
    gdf = gdf.dropna(subset=["node1_xy", "node2_xy"]).copy()

    # unieke nodes maken
    unique_xys = pd.Index(gdf["node1_xy"].tolist() + gdf["node2_xy"].tolist()).unique().tolist()
    nodes_df = pd.DataFrame(unique_xys, columns=["x", "y"])
    nodes_df["node"] = np.arange(100000, 100000 + len(nodes_df), dtype=int)

    # mapping xy -> node id
    xy_to_node = {(row.x, row.y): int(row.node) for row in nodes_df.itertuples(index=False)}

    gdf["node1"] = gdf["node1_xy"].map(lambda t: xy_to_node[(t[0], t[1])])
    gdf["node2"] = gdf["node2_xy"].map(lambda t: xy_to_node[(t[0], t[1])])

    # nodes GeoDataFrame
    gdf_nodes = gpd.GeoDataFrame(
        nodes_df[["node"]].copy(),
        geometry=gpd.GeoSeries([Point(xy) for xy in unique_xys]),
        crs=gdf.crs
    )

    # selectie: beide nodes binnen buffer rondom center
    cx, cy = center_xy
    center_pt = Point(cx, cy)
    buffer_geom = center_pt.buffer(rbuffer)

    # vlag per node: binnen buffer
    gdf_nodes["in_buffer"] = gdf_nodes.geometry.within(buffer_geom)
    inbuf_nodes = set(gdf_nodes.loc[gdf_nodes["in_buffer"], "node"].astype(int).tolist())

    # links waarvoor beide eindnodes binnen buffer liggen
    sel_mask = gdf["node1"].isin(inbuf_nodes) & gdf["node2"].isin(inbuf_nodes)
    gdf_sel = gdf.loc[sel_mask, ["link", "node1", "node2", "lengte", "geometry"]].copy()

    # nodes beperken tot nodes die in geselecteerde links voorkomen
    used_nodes = set(gdf_sel["node1"].astype(int).tolist()) | set(gdf_sel["node2"].astype(int).tolist())
    gdf_nodes_sel = gdf_nodes.loc[gdf_nodes["node"].isin(used_nodes), ["node", "geometry"]].copy()

    return gdf_sel, gdf_nodes_sel




# ====== run ======
for province, province_cases in cases.items():
    path_links = f"data/{province}_loopnetwerk_enriched_final.gpkg"
    gdf_links = gpd.read_file(path_links)[["link", "geometry"]]

    # Check CRS (buffer is in meters)
    if gdf_links.crs is None:
        raise ValueError(f"CRS ontbreekt in {path_links}. Stel CRS in (bijv. EPSG:28992) voordat je buffert.")

    for case_name, center_xy in province_cases.items():
        gdf_links_sel, gdf_nodes_sel = process_case(
            gdf_links=gdf_links,
            center_xy=center_xy,
            rbuffer=rbuffer,
            snap=snap
        )

        out_gpkg = f"data/{case_name}.gpkg"

        # schrijf links en nodes als aparte layers in dezelfde gpkg
        # (handig: 1 file per case)
        gdf_links_sel.to_file(out_gpkg, layer="links", driver="GPKG")
        gdf_nodes_sel.to_file(out_gpkg, layer="nodes", driver="GPKG")

        print(f"[{province} - {case_name}] links: {len(gdf_links_sel)} | nodes: {len(gdf_nodes_sel)} -> {out_gpkg}")