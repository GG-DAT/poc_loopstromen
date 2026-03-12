# -*- coding: utf-8 -*-
"""
Created on Tue Mar  4 16:36:28 2025

@author: tthomas
"""

import numpy as np
import geopandas as gpd
import networkx as nx


                
def assignment_routes(hbnode,aantal,linkindex,
                      linknodes,linklengths,weights,qfract):

    # nodepairs
    nodes_to_links = {}
    for link in linknodes:
        nodes_to_links[linknodes[link][0],linknodes[link][1]] = link
        nodes_to_links[linknodes[link][1],linknodes[link][0]] = link

    # initiate weight category for paths links  
    weights_links = {}
    for link in linknodes:
        weights_links[link] = 2   # initiate for last path (weight = 1)

    hpaths = {}
    qroutes = np.zeros(len(linknodes),dtype=int)
    for iroute in range(len(weights)):    
        # linkweights
        linkweights = {}
        for link in linklengths:
            linkweights[link] = linklengths[link] * weights[iroute][weights_links[link]]

        # directional graph: add edges with weights
        G = nx.DiGraph()
        for link in linknodes:
            G.add_edge(linknodes[link][0],linknodes[link][1],weight=linkweights[link])
            G.add_edge(linknodes[link][1],linknodes[link][0],weight=linkweights[link])

        # calculate shortest path and update weight category of path links 
        hlength = 0
        hpaths[iroute] = nx.dijkstra_path(G,hbnode[0],hbnode[1])
        for i in range(len(hpaths[iroute])-1):
            node1 = hpaths[iroute][i]
            node2 = hpaths[iroute][i+1]
            ilink = linkindex[nodes_to_links[node1,node2]]
            qroutes[ilink] += int(round(aantal*qfract[iroute]))
            hlength += linklengths[nodes_to_links[node1,node2]]
        print('lengte kortste route in km:',hlength/1000)
                
        # update weight category
        for j in range(iroute+1):
            for i in range(len(hpaths[iroute-j])-1):
                node1 = hpaths[iroute-j][i]
                node2 = hpaths[iroute-j][i+1]
                link = nodes_to_links[node1,node2]
                weights_links[link] = iroute-j
        
    return qroutes
    


if __name__ == '__main__':

    wfract = 0.2            # toename afstand route die leidt tot halvering in aandeel dat die route kiest
    
    # gewichten routes: gaan uit van 3 iteraties --> max 3 onafhankelijke routes
    weights = {}
    weights[0] = [1,1,1]    
    weights[1] = [1+wfract,1,1]             # gewichten 1-na kortste route na elke iteratie
    weights[2] = [1+2*wfract,1+1.5*wfract,1]  # gewichten links kortste route na elke iteratie
    qfract = np.array([1,1/2,1/4])
    qfract = qfract / np.sum(qfract)
        

    hbnodes = {'VU':[215666,214177],'HBO_Almere':[186734,113487],
               'NEMO':[354004,344752], 
               'NEMO_plus':[354004,344752]}
    aantal_lopen = {'VU': 6996, 'HBO_Almere': 1598,
                    'NEMO': 200, 'NEMO_plus': 2200}
    fractie_lopen = {'VU':0.15,'HBO_Almere':0.40, 
                     'NEMO':0.30, 'NEMO_plus':0.30}
        
    hbolist = ['VU','HBO_Almere','NEMO','NEMO_plus']
    for naam in hbolist:

        # inlezen 
        naam1 = naam
        if naam == 'NEMO_plus':
            naam1 = 'NEMO'
        path_network = 'data/'+naam1+'.gpkg'
        path_model_out = 'data/'+naam+'_qmodel.gpkg'
        gdf_nodes = gpd.read_file(path_network,layer='nodes')
        gdf_links = gpd.read_file(path_network,layer='links')
        links = gdf_links['link'].to_list()
        linkindex = {}
        for i in range(len(links)):
            linkindex[links[i]] = i

        # Haal tripgeneratie nodes op
        nodexys = {}
        gdf_nodes['x'] = gdf_nodes['geometry'].x
        gdf_nodes['y'] = gdf_nodes['geometry'].y
        for i in range(len(gdf_nodes['node'])):
            node = gdf_nodes['node'][i]
            nodexys[node] = (gdf_nodes['x'][i],gdf_nodes['y'][i])
    
        # haal netwerk en intensiteiten op
        linksarr = np.array(gdf_links['link'])
        linknodes, linklengths = {}, {}
        for i in range(len(linksarr)):
            link = linksarr[i]
            linknodes[link] = [gdf_links['node1'][i],gdf_links['node2'][i]]
            linklengths[link] = gdf_links['lengte'][i]

        # Assignment with routes
        qroutes = assignment_routes(hbnodes[naam],aantal_lopen[naam],linkindex,
                                      linknodes,linklengths,weights,qfract)
        gdf_links['qroutes'] = qroutes

   
        gdf_links = gdf_links[['link','qroutes','geometry']]
        gdf_links.to_file(path_model_out, driver="GPKG")
        